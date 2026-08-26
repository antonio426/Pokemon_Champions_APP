import XCTest
@testable import PokemonChampionCore

/// 這些測試刻意與 Node 版的 test/typechart.test.mjs 一一對應。
/// 移植的驗收標準就是「兩邊算出來的數字一樣」。
final class TypeChartTests: XCTestCase {

    let chart = TypeChart.shared

    func testAllEighteenTypesLoad() {
        XCTAssertEqual(PokemonType.allCases.count, 18)
        for t in PokemonType.allCases {
            XCTAssertFalse(t.zh.isEmpty, "\(t.rawValue) 缺少繁中名稱")
        }
    }

    /// 18×18 = 324 個格子都必須是合法的單屬倍率。
    func testDenseChartHasOnlyLegalMultipliers() {
        var cells = 0
        for attack in PokemonType.allCases {
            for defend in PokemonType.allCases {
                let m = chart.effectiveness(of: attack, against: defend)
                XCTAssertTrue([0, 0.5, 1, 2].contains(m),
                              "\(attack.rawValue)→\(defend.rawValue) 得到非法倍率 \(m)")
                cells += 1
            }
        }
        XCTAssertEqual(cells, 324)
    }

    /// 規劃書 Phase 1 驗收標準：涵蓋所有屬性組合。
    /// 單屬 18 + 雙屬 C(18,2)=153 = 171 種防禦組合 × 18 種攻擊屬性 = 3078 組。
    func testEveryTypeCombination() {
        var defenders: [[PokemonType]] = []
        let all = PokemonType.allCases
        for i in all.indices {
            defenders.append([all[i]])
            for j in (i + 1)..<all.count {
                defenders.append([all[i], all[j]])
            }
        }
        XCTAssertEqual(defenders.count, 171)

        var checked = 0
        for attack in all {
            for defend in defenders {
                let expected = defend.reduce(1.0) { $0 * chart.effectiveness(of: attack, against: $1) }
                let actual = chart.effectiveness(of: attack, against: defend)
                XCTAssertEqual(actual, expected, accuracy: 0,
                               "\(attack.rawValue) → \(defend.map(\.rawValue).joined(separator: "/"))")
                XCTAssertTrue([0, 0.25, 0.5, 1, 2, 4].contains(actual))
                checked += 1
            }
        }
        XCTAssertEqual(checked, 18 * 171)
    }

    func testImmunityDominates() {
        XCTAssertEqual(chart.effectiveness(of: .ground, against: [.flying, .steel]), 0)
        XCTAssertEqual(chart.effectiveness(of: .normal, against: [.ghost, .normal]), 0)
        XCTAssertEqual(chart.effectiveness(of: .dragon, against: [.fairy, .dragon]), 0)
        XCTAssertEqual(chart.effectiveness(of: .psychic, against: [.dark, .fighting]), 0)
        XCTAssertEqual(chart.effectiveness(of: .poison, against: [.steel, .grass]), 0)
        XCTAssertEqual(chart.effectiveness(of: .electric, against: [.ground, .water]), 0)
    }

    func testClassicBattleScenarios() {
        let cases: [(PokemonType, [PokemonType], Double)] = [
            (.electric, [.water, .flying], 4),   // 暴鯉龍
            (.ice, [.dragon, .flying], 4),       // 快龍
            (.fighting, [.rock, .dark], 4),      // 班基拉斯
            (.rock, [.fire, .flying], 4),        // 噴火龍
            (.bug, [.psychic, .dark], 4),
            (.fairy, [.dragon, .dark], 4),
            (.normal, [.rock, .steel], 0.25),
            (.bug, [.fire, .steel], 0.25),
            (.fighting, [.flying, .psychic], 0.25)
        ]
        for (attack, defend, expected) in cases {
            XCTAssertEqual(chart.effectiveness(of: attack, against: defend), expected,
                           "\(attack.rawValue) → \(defend.map(\.rawValue).joined(separator: "/"))")
        }
    }

    func testFairyRelationships() {
        XCTAssertEqual(chart.effectiveness(of: .dragon, against: .fairy), 0)
        XCTAssertEqual(chart.effectiveness(of: .fairy, against: .dragon), 2)
        XCTAssertEqual(chart.effectiveness(of: .poison, against: .fairy), 2)
        XCTAssertEqual(chart.effectiveness(of: .steel, against: .fairy), 2)
        XCTAssertEqual(chart.effectiveness(of: .fairy, against: .steel), 0.5)
    }

    func testSteelNoLongerResistsDarkOrGhost() {
        XCTAssertEqual(chart.effectiveness(of: .dark, against: .steel), 1)
        XCTAssertEqual(chart.effectiveness(of: .ghost, against: .steel), 1)
    }

    func testDefenseProfileBucketsArePartition() {
        for types in [[PokemonType.steel, .fairy], [.water, .flying], [.normal], [.ghost, .dark]] {
            let p = DefenseProfile(types: types)
            let all = p.x4 + p.x2 + p.x1 + p.x05 + p.x025 + p.x0
            XCTAssertEqual(all.count, 18)
            XCTAssertEqual(Set(all).count, 18)
        }
    }

    func testMawileDefenseProfile() {
        let p = DefenseProfile(types: [.steel, .fairy])
        XCTAssertEqual(p.x0, [.poison, .dragon])
        XCTAssertEqual(p.x025, [.bug])
        XCTAssertEqual(p.x2, [.fire, .ground])
        XCTAssertTrue(p.x4.isEmpty)
    }

    func testOffenseProfileTakesBestSingleType() {
        let p = OffenseProfile(types: [.fire, .flying])   // 噴火龍
        XCTAssertEqual(p.multipliers[.grass], 2)
        XCTAssertEqual(p.multipliers[.fighting], 2)
        XCTAssertEqual(p.via[.fighting], .flying)
        XCTAssertEqual(p.multipliers[.rock], 0.5)
        XCTAssertEqual(p.multipliers[.water], 1)          // 不會把兩系相乘
        XCTAssertEqual(p.via[.water], .flying)
    }

    func testTypeParsingAcceptsChineseAndAliases() {
        XCTAssertEqual(chart.type(from: "psychic"), .psychic)
        XCTAssertEqual(chart.type(from: "超能力"), .psychic)
        XCTAssertEqual(chart.type(from: "超能"), .psychic)
        XCTAssertEqual(chart.type(from: "Fire"), .fire)
        XCTAssertEqual(chart.type(from: " 妖精 "), .fairy)
        XCTAssertEqual(chart.type(from: "岩"), .rock)
        XCTAssertNil(chart.type(from: "不存在的屬性"))
    }

    func testDuplicateTypeIsNotSquared() {
        XCTAssertEqual(chart.effectiveness(of: .water, against: [.fire, .fire]), 2)
    }
}
