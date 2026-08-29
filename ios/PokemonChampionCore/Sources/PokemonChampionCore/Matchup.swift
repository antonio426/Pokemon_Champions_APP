import Foundation

/// 場上的一個作戰單位。可以來自圖鑑條目，也可以只給屬性。
public struct Combatant: Sendable, Hashable {
    public let label: String
    public let types: [PokemonType]
    public let entryId: Int?

    public init(label: String, types: [PokemonType], entryId: Int? = nil) {
        // bestSTAB 與 OffenseProfile 都會取 types[0]；空陣列在這裡就擋下來，
        // 錯誤才會指向真正的呼叫端，而不是深處的陣列索引。
        precondition(!types.isEmpty, "Combatant 至少要有一個屬性")
        self.label = label
        self.types = types
        self.entryId = entryId
    }

    public init(entry: PokedexEntry) {
        self.init(label: entry.displayName, types: entry.types, entryId: entry.id)
    }

    /// 用名稱解析，查不到回傳 nil。
    public init?(name: String, pokedex: Pokedex = .shared) {
        guard let hit = pokedex.lookup(name) else { return nil }
        self.init(entry: hit.entry)
    }
}

/// 一次本系打點的結果。
public struct STABHit: Sendable {
    public let multiplier: Double
    public let via: PokemonType
    public var verdict: String { Matchup.verdict(for: multiplier) }
}

public struct PairMatchup: Sendable {
    public enum Edge: String, Sendable { case favorable, unfavorable, even }

    public let mine: Combatant
    public let theirs: Combatant
    public let outgoing: STABHit
    public let incoming: STABHit
    public let edge: Edge
}

public struct MatrixCell: Sendable {
    public let outgoing: Double
    public let outgoingVia: PokemonType
    public let incoming: Double
    public let incomingVia: PokemonType
}

public struct ThreatEntry: Sendable {
    public struct Hit: Sendable {
        public let target: String
        public let multiplier: Double
        public let via: PokemonType
    }
    public let combatant: Combatant
    public let hits: [Hit]
    public let peak: Double
    public var count: Int { hits.count }
}

public struct AnswerEntry: Sendable {
    public let combatant: Combatant
    public let hits: [ThreatEntry.Hit]
    public let worstIncoming: Double
    public var count: Int { hits.count }
    public var safe: Bool { worstIncoming <= 1 }
}

public struct TeamMatchup: Sendable {
    public let mine: [Combatant]
    public let theirs: [Combatant]
    public let matrix: [[MatrixCell]]
    public let threats: [ThreatEntry]
    public let answers: [AnswerEntry]
}

/// 動態島要顯示的內容。空間只夠放一行威脅、一行解答。
///
/// 這個型別之後會直接成為 Live Activity 的 `ContentState`：
/// 它必須是 `Codable` 且小，因為 ActivityKit 每次更新都要序列化它。
public struct LiveSummary: Codable, Sendable, Hashable {
    public let threat: String
    public let answer: String
    public let threatCount: Int
    public let answerCount: Int
}

public enum Matchup {

    /// 把倍率翻成一句人話。動態島空間極小，這是要直接顯示的文案。
    public static func verdict(for multiplier: Double) -> String {
        if multiplier == 0 { return "無效" }
        if multiplier >= 4 { return "致命" }
        if multiplier >= 2 { return "克制" }
        if multiplier > 1 { return "有利" }
        if multiplier == 1 { return "普通" }
        if multiplier >= 0.5 { return "不利" }
        return "幾乎無效"
    }

    /// 這隻的本系招式打向對手時，最好的那一發是幾倍、用哪個屬性。
    public static func bestSTAB(_ attacker: Combatant, _ defender: Combatant,
                                chart: TypeChart = .shared) -> STABHit {
        var best = -1.0
        var via = attacker.types[0]
        for attack in attacker.types {
            let m = chart.effectiveness(of: attack, against: defender.types)
            if m > best { best = m; via = attack }
        }
        return STABHit(multiplier: best, via: via)
    }

    /// 單挑分析：我打牠幾倍、牠打我幾倍，以及誰佔上風。
    public static func pair(mine: Combatant, theirs: Combatant,
                            chart: TypeChart = .shared) -> PairMatchup {
        let out = bestSTAB(mine, theirs, chart: chart)
        let inc = bestSTAB(theirs, mine, chart: chart)
        let edge: PairMatchup.Edge =
            out.multiplier > inc.multiplier ? .favorable
            : out.multiplier < inc.multiplier ? .unfavorable
            : .even
        return PairMatchup(mine: mine, theirs: theirs, outgoing: out, incoming: inc, edge: edge)
    }

    /// 隊伍對隊伍：完整矩陣，並挑出最該注意的與最該派上場的。
    public static func team(mine: [Combatant], theirs: [Combatant],
                            chart: TypeChart = .shared) -> TeamMatchup {
        let matrix: [[MatrixCell]] = mine.map { a in
            theirs.map { b in
                let out = bestSTAB(a, b, chart: chart)
                let inc = bestSTAB(b, a, chart: chart)
                return MatrixCell(outgoing: out.multiplier, outgoingVia: out.via,
                                  incoming: inc.multiplier, incomingVia: inc.via)
            }
        }

        // Node 版靠 JS sort 的穩定性讓同分者維持隊伍順序；Swift 的 sort 不保證穩定，
        // 所以這裡所有排序都帶原始索引當決勝值 —— 兩邊的動態島才會唸出同一個名字。
        func stableByMultiplier(_ hits: [ThreatEntry.Hit]) -> [ThreatEntry.Hit] {
            hits.enumerated()
                .sorted { a, b in
                    if a.element.multiplier != b.element.multiplier {
                        return a.element.multiplier > b.element.multiplier
                    }
                    return a.offset < b.offset
                }
                .map(\.element)
        }

        // 威脅：先看能超效打中幾隻，再看最重的一擊。
        var threats: [ThreatEntry] = []
        for (j, b) in theirs.enumerated() {
            var hits: [ThreatEntry.Hit] = []
            for (i, a) in mine.enumerated() where matrix[i][j].incoming > 1 {
                hits.append(.init(target: a.label,
                                  multiplier: matrix[i][j].incoming,
                                  via: matrix[i][j].incomingVia))
            }
            hits = stableByMultiplier(hits)
            threats.append(ThreatEntry(combatant: b, hits: hits, peak: hits.first?.multiplier ?? 0))
        }
        threats = threats.enumerated()
            .sorted { a, b in
                if a.element.count != b.element.count { return a.element.count > b.element.count }
                if a.element.peak != b.element.peak { return a.element.peak > b.element.peak }
                return a.offset < b.offset
            }
            .map(\.element)

        // 解答：能超效打到最多對手，且盡量不被超效反打。
        var answers: [AnswerEntry] = []
        for (i, a) in mine.enumerated() {
            var hits: [ThreatEntry.Hit] = []
            for (j, b) in theirs.enumerated() where matrix[i][j].outgoing > 1 {
                hits.append(.init(target: b.label,
                                  multiplier: matrix[i][j].outgoing,
                                  via: matrix[i][j].outgoingVia))
            }
            hits = stableByMultiplier(hits)
            let worst = theirs.indices.map { matrix[i][$0].incoming }.max() ?? 0
            answers.append(AnswerEntry(combatant: a, hits: hits, worstIncoming: worst))
        }
        answers = answers.enumerated()
            .sorted { a, b in
                if a.element.count != b.element.count { return a.element.count > b.element.count }
                if a.element.worstIncoming != b.element.worstIncoming {
                    return a.element.worstIncoming < b.element.worstIncoming
                }
                return a.offset < b.offset
            }
            .map(\.element)

        return TeamMatchup(mine: mine, theirs: theirs, matrix: matrix, threats: threats, answers: answers)
    }

    /// 動態島用的極簡摘要。
    public static func liveSummary(mine: [Combatant], theirs: [Combatant],
                                   chart: TypeChart = .shared) -> LiveSummary {
        let result = team(mine: mine, theirs: theirs, chart: chart)
        let topThreat = result.threats.first { $0.count > 0 }
        let topAnswer = result.answers.first { $0.count > 0 }

        return LiveSummary(
            threat: topThreat.map { t in
                "\(t.combatant.label) → \(t.hits[0].target) \(format(t.hits[0].multiplier))×"
            } ?? "目前無明顯剋制",
            answer: topAnswer.map { a in
                "\(a.combatant.label) → \(a.hits[0].target) \(format(a.hits[0].multiplier))×"
            } ?? "本系無超效打點",
            threatCount: topThreat?.count ?? 0,
            answerCount: topAnswer?.count ?? 0
        )
    }

    /// 倍率的顯示字串。整數不要拖著 `.0`，動態島每個字元都很貴。
    public static func format(_ multiplier: Double) -> String {
        switch multiplier {
        case 0.25: return "¼"
        case 0.5: return "½"
        default:
            return multiplier == multiplier.rounded()
                ? String(Int(multiplier))
                : String(multiplier)
        }
    }
}
