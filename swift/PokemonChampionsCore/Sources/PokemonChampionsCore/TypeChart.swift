import Foundation

/// 單一屬性（18 種之一）。
public struct TypeInfo: Codable, Equatable, Sendable {
    public let id: Int
    public let identifier: String
    public let nameEn: String
    public let nameZh: String?

    enum CodingKeys: String, CodingKey {
        case id, identifier
        case nameEn = "name_en"
        case nameZh = "name_zh"
    }
}

/// data/type_chart.json 的檔案結構。
public struct TypeChartFile: Codable, Sendable {
    public let generation: Int
    public let types: [TypeInfo]
    public let chart: [String: [String: Double]]
}

/// 18×18 屬性剋制引擎。乘數只會是 0 / 0.25 / 0.5 / 1 / 2 / 4（2 的冪次，浮點相等安全）。
/// 演算法與 Node 原型 prototype-node/src/typechart.js 一對一對應。
public struct TypeChart: Sendable {
    public let types: [TypeInfo]
    private let chart: [String: [String: Double]]
    private let byIdentifier: [String: TypeInfo]

    public init(file: TypeChartFile) {
        self.types = file.types.sorted { $0.id < $1.id }
        self.chart = file.chart
        self.byIdentifier = Dictionary(
            uniqueKeysWithValues: file.types.map { ($0.identifier, $0) })
    }

    /// 單一攻擊屬性對（可能雙屬性的）防禦方的總乘數。
    public func effectiveness(attack: String, defense: [String]) -> Double {
        guard let row = chart[attack] else {
            preconditionFailure("未知攻擊屬性: \(attack)")
        }
        var mult = 1.0
        for d in defense {
            guard let v = row[d] else { preconditionFailure("未知防禦屬性: \(d)") }
            mult *= v
        }
        return mult
    }

    /// 全部 18 種攻擊屬性對此防禦組合的乘數表。
    public func defensiveProfile(defense: [String]) -> [String: Double] {
        var profile: [String: Double] = [:]
        for t in types {
            profile[t.identifier] = effectiveness(attack: t.identifier, defense: defense)
        }
        return profile
    }

    /// 繁中屬性名（"fire" → "火"）；查不到時原樣回傳。
    public func zhName(_ identifier: String) -> String {
        byIdentifier[identifier]?.nameZh ?? identifier
    }

    /// 屬性 id（排序用）。
    public func typeId(_ identifier: String) -> Int {
        byIdentifier[identifier]?.id ?? Int.max
    }
}
