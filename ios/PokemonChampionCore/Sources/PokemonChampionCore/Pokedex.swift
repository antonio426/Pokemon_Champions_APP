import Foundation

/// 一筆圖鑑條目（一個形態）。欄位與 data/pokedex.json 一對一。
public struct PokedexEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let speciesId: Int
    public let slug: String
    public let isDefault: Bool
    public let zh: String?
    public let zhBase: String?
    public let form: String?
    public let ja: String?
    public let en: String?
    public let types: [PokemonType]
    public let sprite: String?

    /// 顯示用名稱。繁中優先，缺了退回英文，再退回 slug。
    public var displayName: String { zh ?? en ?? slug }
}

/// 名稱解析的結果。
public struct PokedexMatch: Sendable {
    public let entry: PokedexEntry
    /// 1.0 表示精確命中；模糊比對會小於 1。
    public let score: Double
    public let matched: String
    public let exact: Bool
}

/// 賽季可用清單。清單存在時，模糊比對只會在清單內尋找候選。
public struct SeasonPool: Sendable {
    public let name: String
    public let entries: [PokedexEntry]
}

/// 圖鑑查詢：把 OCR 吐出來的髒字串變成圖鑑條目。
public final class Pokedex: @unchecked Sendable {

    public static let shared = Pokedex()

    public let entries: [PokedexEntry]
    public let generatedAt: String

    /// 正規化後的名稱 → 條目。繁中、日文、英文、slug 都建索引。
    private let exactIndex: [String: [PokedexEntry]]
    private let byId: [Int: PokedexEntry]

    /// `@unchecked Sendable` 的唯一可變狀態。設定頁改清單時，Broadcast Extension
    /// 可能正在另一條執行緒上 resolve —— 所有存取都得過這把鎖。
    private let poolLock = NSLock()
    private var pool: SeasonPool?

    private struct File: Decodable {
        let generatedAt: String
        let entries: [PokedexEntry]
    }

    private init() {
        guard let url = Bundle.module.url(forResource: "pokedex", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            fatalError("PokemonChampionCore: 無法載入 pokedex.json —— 資源沒有被打包進 bundle")
        }

        self.entries = file.entries
        self.generatedAt = file.generatedAt

        var exact: [String: [PokedexEntry]] = [:]
        var ids: [Int: PokedexEntry] = [:]
        for e in file.entries {
            ids[e.id] = e
            for case let key? in [e.zh, e.zhBase, e.en, e.slug, e.ja] {
                let norm = Pokedex.normalize(key)
                guard !norm.isEmpty else { continue }
                exact[norm, default: []].append(e)
            }
        }
        self.exactIndex = exact
        self.byId = ids
    }

    // MARK: - 正規化

    /// OCR 的輸出從來不乾淨：等級前綴、性別符號、全形空白、標點都要清掉。
    ///
    /// 逐步鏡射 Node 版（src/pokedex.mjs 的 `normalize`）：NFKC → 去等級 → 白名單。
    /// 白名單刻意用同一個 script 正則，而不是 `CharacterSet.alphanumerics` ——
    /// alphanumerics 會多留下希臘、諺文、注音等雜訊字元，讓兩邊對同一個
    /// OCR 髒字串算出不同的比對結果。長音符號 ー 屬於 Script=Common，要單獨列。
    public static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping   // ≈ NFKC
        let withoutLevel = folded.replacingOccurrences(
            of: "[Ll][Vv]\\.?\\s*[0-9]+",
            with: "",
            options: .regularExpression
        )
        let kept = withoutLevel.replacingOccurrences(
            of: "[^\\p{Script=Han}\\p{Script=Katakana}\\p{Script=Hiragana}\\p{Script=Latin}\\p{Nd}ー]",
            with: "",
            options: .regularExpression
        )
        return kept.lowercased()
    }

    // MARK: - 賽季清單

    /// 規劃書把「縮小比對範圍」列為提高辨識準確率的主要手段。
    /// 設定後，模糊比對只掃清單內的條目。
    @discardableResult
    public func setPool(names: [String], label: String = "custom") -> SeasonPool? {
        var selected: [PokedexEntry] = []
        var seen: Set<Int> = []
        for name in names {
            for e in exactIndex[Pokedex.normalize(name)] ?? [] where seen.insert(e.id).inserted {
                selected.append(e)
            }
        }
        let newPool = selected.isEmpty ? nil : SeasonPool(name: label, entries: selected)
        setPool(newPool)
        return newPool
    }

    @discardableResult
    public func setPool(ids: [Int], label: String = "custom") -> SeasonPool? {
        let selected = ids.compactMap { byId[$0] }
        let newPool = selected.isEmpty ? nil : SeasonPool(name: label, entries: selected)
        setPool(newPool)
        return newPool
    }

    public func clearPool() { setPool(nil) }

    public var currentPool: SeasonPool? {
        poolLock.lock()
        defer { poolLock.unlock() }
        return pool
    }

    private func setPool(_ newPool: SeasonPool?) {
        poolLock.lock()
        pool = newPool
        poolLock.unlock()
    }

    // MARK: - 查詢

    public func entry(id: Int) -> PokedexEntry? { byId[id] }

    /// 把一段（可能有錯字的）文字解析成寶可夢。先精確命中，不中再模糊比對。
    public func resolve(_ text: String, limit: Int = 5, minScore: Double = 0.5) -> [PokedexMatch] {
        let query = Pokedex.normalize(text)
        guard !query.isEmpty else { return [] }

        // 進場先照一次快照，整趟查詢用同一份清單 —— 過程中換 pool 不會撕裂結果。
        let activePool = currentPool
        let allowed: Set<Int>? = activePool.map { Set($0.entries.map(\.id)) }
        let candidates = activePool?.entries ?? entries

        let exact = (exactIndex[query] ?? []).filter { allowed?.contains($0.id) ?? true }
        if !exact.isEmpty {
            return collapse(
                exact.map { PokedexMatch(entry: $0, score: 1, matched: query, exact: true) },
                limit: limit
            )
        }

        let queryChars = Array(query.unicodeScalars)
        var scored: [PokedexMatch] = []
        for e in candidates {
            for case let key? in [e.zh, e.zhBase, e.en, e.ja] {
                let norm = Pokedex.normalize(key)
                guard !norm.isEmpty else { continue }
                let keyChars = Array(norm.unicodeScalars)
                let longest = max(keyChars.count, queryChars.count)
                let maxDistance = max(1, Int((Double(longest) * (1 - minScore)).rounded(.up)))
                let d = Pokedex.editDistance(queryChars, keyChars, max: maxDistance)
                guard d <= maxDistance else { continue }
                let score = 1 - Double(d) / Double(longest)
                if score >= minScore {
                    scored.append(PokedexMatch(entry: e, score: score, matched: norm, exact: false))
                }
            }
        }
        return collapse(scored, limit: limit)
    }

    public func lookup(_ text: String, minScore: Double = 0.5) -> PokedexMatch? {
        resolve(text, limit: 1, minScore: minScore).first
    }

    // MARK: - 形態收斂

    /// 同一物種中「戰鬥上等價」的形態（皮卡丘的各種帽子、屬性與本體相同的 Mega）
    /// 對屬性剋制而言是同一個東西，收斂成一筆，並優先保留預設形態。
    private func collapse(_ matches: [PokedexMatch], limit: Int) -> [PokedexMatch] {
        var best: [String: PokedexMatch] = [:]
        for m in matches {
            let key = "\(m.entry.speciesId)|\(m.entry.types.map(\.rawValue).joined(separator: "/"))"
            if let prev = best[key] {
                if m.score > prev.score || (m.score == prev.score && Pokedex.prefers(m.entry, over: prev.entry)) {
                    best[key] = m
                }
            } else {
                best[key] = m
            }
        }
        return best.values
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return Pokedex.prefers(a.entry, over: b.entry)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func prefers(_ a: PokedexEntry, over b: PokedexEntry) -> Bool {
        if a.isDefault != b.isDefault { return a.isDefault }
        return a.id < b.id
    }

    // MARK: - 編輯距離

    /// 上限式編輯距離：超過 max 就提早收手，掃全圖鑑時省下大量無用計算。
    static func editDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], max maxDistance: Int) -> Int {
        let al = a.count, bl = b.count
        if abs(al - bl) > maxDistance { return maxDistance + 1 }
        if al == 0 { return bl }
        if bl == 0 { return al }

        var prev = Array(0...bl)
        var curr = Array(repeating: 0, count: bl + 1)

        for i in 1...al {
            curr[0] = i
            var rowMin = i
            for j in 1...bl {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = Swift.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
                if curr[j] < rowMin { rowMin = curr[j] }
            }
            if rowMin > maxDistance { return maxDistance + 1 }
            swap(&prev, &curr)
        }
        return prev[bl]
    }
}
