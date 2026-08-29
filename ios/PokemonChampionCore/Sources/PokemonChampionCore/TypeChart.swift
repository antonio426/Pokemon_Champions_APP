import Foundation

/// 18 種屬性。rawValue 與 data/types.json 的鍵一致，順序即矩陣索引。
public enum PokemonType: String, CaseIterable, Codable, Sendable {
    case normal, fire, water, electric, grass, ice, fighting, poison, ground
    case flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy

    /// 在 18×18 矩陣中的索引。
    public var index: Int { PokemonType.orderIndex[self]! }

    private static let orderIndex: [PokemonType: Int] = {
        var map: [PokemonType: Int] = [:]
        for (i, t) in PokemonType.allCases.enumerated() { map[t] = i }
        return map
    }()

    public var zh: String { TypeChart.shared.names[self]?.zh ?? rawValue }
}

public struct TypeNames: Decodable, Sendable {
    public let zh: String
    public let ja: String
    public let en: String
}

/// 屬性相剋計算。
///
/// 資料以「攻擊方 → 超效／半減／免疫」的稀疏形式存在 JSON 裡（比 324 格密集表好審核），
/// 初始化時展開成密集矩陣，之後每次查詢都是兩次陣列索引。
public final class TypeChart: @unchecked Sendable {

    public static let shared = TypeChart()

    public let names: [PokemonType: TypeNames]

    /// matrix[攻擊][防禦]
    private let matrix: [[Double]]

    /// 繁中名與常見別名 → 屬性。OCR 讀到什麼都盡量接得住。
    private let zhLookup: [String: PokemonType]

    private struct Relations: Decodable {
        let superEffective: [PokemonType]
        let notVery: [PokemonType]
        let immune: [PokemonType]

        // `super` 是 Swift 保留字，必須改名對應。
        enum CodingKeys: String, CodingKey {
            case superEffective = "super"
            case notVery
            case immune
        }
    }

    private struct File: Decodable {
        let order: [PokemonType]
        let names: [String: TypeNames]
        let chart: [String: Relations]
    }

    private init() {
        guard let url = Bundle.module.url(forResource: "types", withExtension: "json") else {
            fatalError("PokemonChampionCore: types.json 沒有被打包進 bundle")
        }
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: try Data(contentsOf: url))
        } catch {
            // 資料由 scripts/sync-swift-data.mjs 再生，schema 打錯時要看得到真正的欄位錯誤。
            fatalError("PokemonChampionCore: types.json 解碼失敗 —— \(error)")
        }

        precondition(file.order == PokemonType.allCases,
                     "types.json 的屬性順序與 PokemonType 不一致，矩陣索引會錯位")

        var namesByType: [PokemonType: TypeNames] = [:]
        for (key, value) in file.names {
            if let t = PokemonType(rawValue: key) { namesByType[t] = value }
        }
        self.names = namesByType

        let count = PokemonType.allCases.count
        var m = Array(repeating: Array(repeating: 1.0, count: count), count: count)
        for attacker in PokemonType.allCases {
            guard let rel = file.chart[attacker.rawValue] else {
                fatalError("types.json 缺少 \(attacker.rawValue) 的相剋定義")
            }
            for d in rel.superEffective { m[attacker.index][d.index] = 2 }
            for d in rel.notVery { m[attacker.index][d.index] = 0.5 }
            for d in rel.immune { m[attacker.index][d.index] = 0 }
        }
        self.matrix = m

        var lookup: [String: PokemonType] = [:]
        for (t, n) in namesByType { lookup[n.zh] = t }
        for (alias, type) in TypeChart.aliases { lookup[alias] = type }
        self.zhLookup = lookup
    }

    private static let aliases: [String: PokemonType] = [
        "普通": .normal, "一般系": .normal,
        "火系": .fire, "火焰": .fire,
        "水系": .water,
        "電系": .electric, "電氣": .electric,
        "草系": .grass,
        "冰系": .ice, "冰凍": .ice,
        "格鬥系": .fighting, "戰鬥": .fighting,
        "毒系": .poison,
        "地面系": .ground,
        "飛行系": .flying,
        "超能": .psychic, "超能力系": .psychic, "念力": .psychic,
        "蟲系": .bug, "昆蟲": .bug,
        "岩石系": .rock, "岩": .rock,
        "幽靈系": .ghost, "鬼": .ghost,
        "龍系": .dragon,
        "惡系": .dark, "邪惡": .dark,
        "鋼系": .steel,
        "妖精系": .fairy, "仙子": .fairy
    ]

    /// 把使用者或 OCR 給的字串正規化成屬性；認不得回傳 nil。
    public func type(from input: String) -> PokemonType? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = PokemonType(rawValue: trimmed) { return t }
        if let t = PokemonType(rawValue: trimmed.lowercased()) { return t }
        return zhLookup[trimmed]
    }

    /// 單一招式屬性打向防禦方的最終倍率：0 / 0.25 / 0.5 / 1 / 2 / 4。
    public func effectiveness(of attack: PokemonType, against defenders: [PokemonType]) -> Double {
        precondition(!defenders.isEmpty, "至少需要一個防禦方屬性")
        precondition(defenders.count <= 2, "寶可夢最多只有兩種屬性")
        // 重複屬性視為單屬，不能平方。
        var seen: Set<PokemonType> = []
        var result = 1.0
        for d in defenders where seen.insert(d).inserted {
            result *= matrix[attack.index][d.index]
        }
        return result
    }

    public func effectiveness(of attack: PokemonType, against defender: PokemonType) -> Double {
        matrix[attack.index][defender.index]
    }
}

/// 防禦面總表：被 18 種屬性打分別吃多少倍，並依倍率分組。
public struct DefenseProfile: Sendable {
    public let types: [PokemonType]
    public let multipliers: [PokemonType: Double]
    public let x4: [PokemonType]
    public let x2: [PokemonType]
    public let x1: [PokemonType]
    public let x05: [PokemonType]
    public let x025: [PokemonType]
    public let x0: [PokemonType]

    public init(types: [PokemonType], chart: TypeChart = .shared) {
        self.types = types
        var mults: [PokemonType: Double] = [:]
        var b4: [PokemonType] = [], b2: [PokemonType] = [], b1: [PokemonType] = []
        var b05: [PokemonType] = [], b025: [PokemonType] = [], b0: [PokemonType] = []

        for attack in PokemonType.allCases {
            let m = chart.effectiveness(of: attack, against: types)
            mults[attack] = m
            switch m {
            case 4: b4.append(attack)
            case 2: b2.append(attack)
            case 1: b1.append(attack)
            case 0.5: b05.append(attack)
            case 0.25: b025.append(attack)
            default: b0.append(attack)
            }
        }
        self.multipliers = mults
        self.x4 = b4; self.x2 = b2; self.x1 = b1
        self.x05 = b05; self.x025 = b025; self.x0 = b0
    }
}

/// 攻擊面總表：以本系招式打出去，對 18 種單屬各是多少倍（取兩系中較好的）。
public struct OffenseProfile: Sendable {
    public let types: [PokemonType]
    public let multipliers: [PokemonType: Double]
    public let via: [PokemonType: PokemonType]

    public init(types: [PokemonType], chart: TypeChart = .shared) {
        precondition(!types.isEmpty, "OffenseProfile 至少需要一個攻擊屬性")
        self.types = types
        var best: [PokemonType: Double] = [:]
        var source: [PokemonType: PokemonType] = [:]
        for defender in PokemonType.allCases {
            var top = -1.0
            var topType = types[0]
            for attack in types {
                let m = chart.effectiveness(of: attack, against: defender)
                if m > top { top = m; topType = attack }
            }
            best[defender] = top
            source[defender] = topType
        }
        self.multipliers = best
        self.via = source
    }
}
