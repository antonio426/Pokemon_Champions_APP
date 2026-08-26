import Foundation

/// 某攻擊屬性對某防禦組合的乘數（含繁中屬性名，供 UI 直接顯示）。
public struct TypeMultiplier: Equatable, Sendable {
    public let type: String
    public let typeZh: String
    public let multiplier: Double
}

/// 對戰報告中一方的摘要。
public struct PokemonSummary: Equatable, Sendable {
    public let id: Int
    public let dex: Int
    public let nameZh: String?
    public let nameEn: String?
    public let types: [String]
    public let typesZh: [String]
}

/// 對戰分析報告——動態島/UI 要顯示的核心資訊。
/// 結構與 Node 原型 prototype-node/src/matchup.js 的輸出一對一對應。
public struct MatchupReport: Sendable {
    public let opponent: PokemonSummary
    /// 18 種攻擊屬性打對方的乘數，乘數高到低（同乘數依屬性 id）。
    public let offense: [TypeMultiplier]
    public let weaknesses: [TypeMultiplier]
    public let resistances: [TypeMultiplier]
    public let immunities: [TypeMultiplier]
    public let mine: PokemonSummary?
    /// 我方本屬性（STAB）打對方。
    public let myStab: [TypeMultiplier]?
    /// 對方本屬性（STAB）打我方——威脅度。
    public let threats: [TypeMultiplier]?
}

public func analyze(
    chart: TypeChart, mine: PokedexEntry?, opponent: PokedexEntry
) -> MatchupReport {
    let offense = chart.types
        .map { t in
            TypeMultiplier(
                type: t.identifier,
                typeZh: t.nameZh ?? t.identifier,
                multiplier: chart.effectiveness(attack: t.identifier, defense: opponent.types))
        }
        .sorted { a, b in
            if a.multiplier != b.multiplier { return a.multiplier > b.multiplier }
            return chart.typeId(a.type) < chart.typeId(b.type)
        }

    var mySummary: PokemonSummary?
    var myStab: [TypeMultiplier]?
    var threats: [TypeMultiplier]?
    if let mine {
        mySummary = summarize(chart: chart, entry: mine)
        myStab = mine.types.map {
            TypeMultiplier(
                type: $0, typeZh: chart.zhName($0),
                multiplier: chart.effectiveness(attack: $0, defense: opponent.types))
        }
        threats = opponent.types.map {
            TypeMultiplier(
                type: $0, typeZh: chart.zhName($0),
                multiplier: chart.effectiveness(attack: $0, defense: mine.types))
        }
    }

    return MatchupReport(
        opponent: summarize(chart: chart, entry: opponent),
        offense: offense,
        weaknesses: offense.filter { $0.multiplier > 1 },
        resistances: offense.filter { $0.multiplier < 1 && $0.multiplier > 0 },
        immunities: offense.filter { $0.multiplier == 0 },
        mine: mySummary,
        myStab: myStab,
        threats: threats)
}

private func summarize(chart: TypeChart, entry: PokedexEntry) -> PokemonSummary {
    PokemonSummary(
        id: entry.id,
        dex: entry.dex,
        nameZh: entry.nameZh,
        nameEn: entry.nameEn,
        types: entry.types,
        typesZh: entry.types.map { chart.zhName($0) })
}

/// 把乘數格式化成顯示字串（4× / 2× / 1× / ½× / ¼× / 0×）。
public func formatMultiplier(_ m: Double) -> String {
    if m == 0.5 { return "½×" }
    if m == 0.25 { return "¼×" }
    if m == m.rounded() { return "\(Int(m))×" }
    return "\(m)×"
}
