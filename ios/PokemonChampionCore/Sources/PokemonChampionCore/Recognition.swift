import Foundation

/// OCR 引擎輸出的一行文字，座標一律用「相對整張圖」的 0…1 比例。
///
/// 這是 `src/pipeline.mjs` 的移植。Node 版吃 Windows OCR 的像素座標再除以圖寬；
/// Swift 版直接要求呼叫端給比例座標 —— Vision 的 `boundingBox` 本來就是比例制，
/// 這樣核心邏輯完全不需要知道圖片尺寸，也不需要 import Vision。
public struct RecognizedLine: Sendable, Hashable {
    public let text: String
    /// 行中心的 x（0 = 最左、1 = 最右）。
    public let centerX: Double
    /// 行中心的 y（0 = 最上、1 = 最下）。注意 Vision 的原點在左下，呼叫端要先翻轉。
    public let centerY: Double

    public init(text: String, centerX: Double, centerY: Double) {
        self.text = text
        self.centerX = centerX
        self.centerY = centerY
    }
}

/// 畫面版面規則。與 `src/pipeline.mjs` 的 `DEFAULT_LAYOUT` 一對一，
/// 用比例而不是絕對像素，才能跨機型沿用。
public struct BattleLayout: Sendable {
    /// x 中心小於這個比例算我方。
    public var mineUntil: Double
    /// x 中心大於這個比例算對方；mineUntil 與 theirsFrom 之間的中間地帶
    /// （通常是標題、計時器）直接丟棄。
    public var theirsFrom: Double
    /// 送進 OCR 前先裁掉上方（標題列）的比例。
    public var top: Double
    /// 保留的高度比例（top + height 以下是按鈕列，也裁掉）。
    public var height: Double
    /// 送進 OCR 前的降取樣倍率。Phase 0 實測 0.4 反而比原尺寸準，而且快一倍。
    public var scale: Double
    /// 模糊比對低於這個相似度就不當成辨識結果 —— 寧可漏也不要餵錯資料給動態島。
    public var minScore: Double

    public init(mineUntil: Double = 0.45, theirsFrom: Double = 0.5,
                top: Double = 0.05, height: Double = 0.85,
                scale: Double = 0.4, minScore: Double = 0.6) {
        self.mineUntil = mineUntil
        self.theirsFrom = theirsFrom
        self.top = top
        self.height = height
        self.scale = scale
        self.minScore = minScore
    }

    public static let battlePrepSplit = BattleLayout()
}

/// 一張截圖經過「OCR → 分邊 → 名稱解析」後的結果。
public struct TeamReading: Sendable {
    /// 認出來的一隻。保留 OCR 原文與比對分數，介面上要能讓使用者覆核。
    public struct Recognized: Sendable, Hashable {
        public let entry: PokedexEntry
        public let ocrText: String
        public let score: Double
        public let exact: Bool
    }

    /// 沒能解析成寶可夢的文字。「對戰準備」這類 UI 標題落在這裡是正常的。
    public struct Unresolved: Sendable, Hashable {
        public let text: String
        public let centerX: Double
    }

    public let mine: [Recognized]
    public let theirs: [Recognized]
    public let unresolved: [Unresolved]

    public var mineCombatants: [Combatant] { mine.map { Combatant(entry: $0.entry) } }
    public var theirsCombatants: [Combatant] { theirs.map { Combatant(entry: $0.entry) } }
    public var isEmpty: Bool { mine.isEmpty && theirs.isEmpty }
}

public enum Recognition {

    /// OCR 行 → 雙方隊伍。`src/pipeline.mjs` 的 `readTeams` 後半段。
    ///
    /// 影像處理（裁切、降取樣）與文字辨識由呼叫端負責 —— 主 App 用 Vision，
    /// 測試直接餵合成的行。這裡只做分邊、名稱解析與去重，全部是純函式。
    public static func readTeams(lines: [RecognizedLine],
                                 layout: BattleLayout = .battlePrepSplit,
                                 pokedex: Pokedex = .shared) -> TeamReading {
        var mine: [(TeamReading.Recognized, Double, Int)] = []
        var theirs: [(TeamReading.Recognized, Double, Int)] = []
        var unresolved: [TeamReading.Unresolved] = []

        for (order, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // 用 UTF-16 長度，與 Node 版的 text.length 同一種數法。
            guard text.utf16.count >= 2 else { continue }

            let isMine = line.centerX < layout.mineUntil
            let isTheirs = line.centerX > layout.theirsFrom
            guard isMine || isTheirs else { continue }

            guard let best = pokedex.resolve(text, limit: 1, minScore: layout.minScore).first else {
                unresolved.append(.init(text: text, centerX: line.centerX))
                continue
            }
            let hit = TeamReading.Recognized(entry: best.entry, ocrText: text,
                                             score: best.score, exact: best.exact)
            if isMine { mine.append((hit, line.centerY, order)) }
            else { theirs.append((hit, line.centerY, order)) }
        }

        // 同一邊同一隻只留一筆，順序照畫面由上到下 —— 與 Node 版的 dedupe 一致。
        // Node 的 sort 是穩定的，Swift 的不保證，所以帶輸入序當決勝值。
        func dedupe(_ list: [(TeamReading.Recognized, Double, Int)]) -> [TeamReading.Recognized] {
            var seen: Set<Int> = []
            return list
                .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
                .compactMap { seen.insert($0.0.entry.id).inserted ? $0.0 : nil }
        }

        return TeamReading(mine: dedupe(mine), theirs: dedupe(theirs), unresolved: unresolved)
    }

    /// 截圖 → 完整剋制分析。`src/pipeline.mjs` 的 `analyzeScreenshot` 後半段。
    public static func analyze(lines: [RecognizedLine],
                               layout: BattleLayout = .battlePrepSplit,
                               pokedex: Pokedex = .shared,
                               chart: TypeChart = .shared)
    -> (reading: TeamReading, matchup: TeamMatchup?, summary: LiveSummary?) {
        let reading = readTeams(lines: lines, layout: layout, pokedex: pokedex)
        guard !reading.isEmpty else { return (reading, nil, nil) }
        let mine = reading.mineCombatants
        let theirs = reading.theirsCombatants
        return (reading,
                Matchup.team(mine: mine, theirs: theirs, chart: chart),
                Matchup.liveSummary(mine: mine, theirs: theirs, chart: chart))
    }
}
