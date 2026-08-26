import XCTest

@testable import PokemonChampionsCore

/// 共用驗收向量：與 Node 原型跑同一份 data/test_vectors.json。
struct TestVectors: Decodable {
    struct Effectiveness: Decodable {
        let attack: String
        let defense: [String]
        let expect: Double
    }
    struct DefensiveProfile: Decodable {
        let defense: [String]
        let expectPartial: [String: Double]
        enum CodingKeys: String, CodingKey {
            case defense
            case expectPartial = "expect_partial"
        }
    }
    struct Lookup: Decodable {
        let query: String
        let expectId: Int
        enum CodingKeys: String, CodingKey {
            case query
            case expectId = "expect_id"
        }
    }
    struct Extract: Decodable {
        let text: String
        let expectIds: [Int]
        enum CodingKeys: String, CodingKey {
            case text
            case expectIds = "expect_ids"
        }
    }
    let effectiveness: [Effectiveness]
    let defensiveProfile: [DefensiveProfile]
    let lookup: [Lookup]
    let fuzzy: [Lookup]
    let extract: [Extract]
    let extractNormalized: [Extract]

    enum CodingKeys: String, CodingKey {
        case effectiveness, lookup, fuzzy, extract
        case defensiveProfile = "defensive_profile"
        case extractNormalized = "extract_normalized"
    }
}

final class EngineTests: XCTestCase {
    static var chart: TypeChart!
    static var dex: Pokedex!
    static var vectors: TestVectors!

    override class func setUp() {
        super.setUp()
        chart = try! CoreDataStore.loadTypeChart()
        dex = try! CoreDataStore.loadPokedex()
        let url = Bundle.module.url(forResource: "test_vectors", withExtension: "json")!
        vectors = try! JSONDecoder().decode(TestVectors.self, from: Data(contentsOf: url))
    }

    var chart: TypeChart { Self.chart }
    var dex: Pokedex { Self.dex }
    var vectors: TestVectors { Self.vectors }

    func testChartComplete() {
        XCTAssertEqual(chart.types.count, 18)
        let legal: Set<Double> = [0, 0.5, 1, 2]
        for a in chart.types {
            for d in chart.types {
                let v = chart.effectiveness(attack: a.identifier, defense: [d.identifier])
                XCTAssertTrue(legal.contains(v), "\(a.identifier)→\(d.identifier) = \(v)")
            }
        }
    }

    func testEffectivenessVectors() {
        for v in vectors.effectiveness {
            XCTAssertEqual(
                chart.effectiveness(attack: v.attack, defense: v.defense), v.expect,
                "\(v.attack) vs \(v.defense) 應為 \(v.expect)")
        }
    }

    func testDefensiveProfileVectors() {
        for v in vectors.defensiveProfile {
            let profile = chart.defensiveProfile(defense: v.defense)
            for (atk, expected) in v.expectPartial {
                XCTAssertEqual(profile[atk], expected, "\(atk) vs \(v.defense) 應為 \(expected)")
            }
        }
    }

    func testLookupVectors() {
        for v in vectors.lookup {
            let hit = dex.lookup(v.query)
            XCTAssertNotNil(hit, "「\(v.query)」應可查到")
            XCTAssertEqual(hit?.id, v.expectId, "「\(v.query)」應為 id \(v.expectId)")
        }
    }

    func testFuzzyVectors() {
        for v in vectors.fuzzy {
            let hit = dex.fuzzy(v.query)
            XCTAssertNotNil(hit, "「\(v.query)」應可模糊比對到")
            XCTAssertEqual(
                hit?.entry.id, v.expectId,
                "「\(v.query)」應比對到 id \(v.expectId)（實際:「\(hit?.entry.nameZh ?? "?")」）")
        }
    }

    func testExtractVectors() {
        for v in vectors.extract {
            let ids = dex.extract(from: v.text).map { $0.id }
            XCTAssertEqual(ids, v.expectIds, "「\(v.text)」")
        }
    }

    func testExtractNormalizedVectors() {
        for v in vectors.extractNormalized {
            let ids = dex.extract(from: normalizeOcrText(v.text)).map { $0.id }
            XCTAssertEqual(ids, v.expectIds, "「\(v.text)」")
        }
    }

    func testAnalyzePikachuVsCharizard() {
        let r = analyze(chart: chart, mine: dex.lookup("皮卡丘"), opponent: dex.lookup("噴火龍")!)
        XCTAssertEqual(r.myStab?.first?.multiplier, 2)  // 電打火/飛 = 2
        XCTAssertEqual(
            r.weaknesses.map { $0.type }.sorted(), ["electric", "rock", "water"])
        XCTAssertEqual(r.weaknesses.first?.type, "rock")  // 岩 4× 排最前
        XCTAssertEqual(r.immunities.first?.type, "ground")
        XCTAssertEqual(r.threats?.map { $0.multiplier }, [1, 0.5])
    }

    func testLevenshtein() {
        XCTAssertEqual(levenshtein("", "abc"), 3)
        XCTAssertEqual(levenshtein("皮卡丘", "皮卡丘"), 0)
        XCTAssertEqual(levenshtein("皮卡丘", "皮丘"), 1)
        XCTAssertEqual(levenshtein("噴火龍", "暴鯉龍"), 2)
    }
}
