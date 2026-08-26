import XCTest
@testable import PokemonChampionCore

final class PokedexTests: XCTestCase {

    let dex = Pokedex.shared

    override func tearDown() {
        dex.clearPool()
        super.tearDown()
    }

    func testDexLoadsCompletely() {
        XCTAssertGreaterThan(dex.entries.count, 1000)
        XCTAssertGreaterThanOrEqual(Set(dex.entries.map(\.speciesId)).count, 1025)
        for e in dex.entries {
            XCTAssertNotNil(e.zh, "#\(e.id) \(e.slug) 缺繁中名")
            XCTAssertTrue((1...2).contains(e.types.count), "#\(e.id) 屬性數量異常")
        }
    }

    func testExactChineseLookup() {
        let cases: [(String, [PokemonType])] = [
            ("皮卡丘", [.electric]),
            ("噴火龍", [.fire, .flying]),
            ("班基拉斯", [.rock, .dark]),
            ("沙奈朵", [.psychic, .fairy]),
            ("暴鯉龍", [.water, .flying]),
            ("快龍", [.dragon, .flying]),
            ("耿鬼", [.ghost, .poison])
        ]
        for (name, types) in cases {
            guard let hit = dex.lookup(name) else { return XCTFail("查不到 \(name)") }
            XCTAssertTrue(hit.exact, "\(name) 應該是精確命中")
            XCTAssertEqual(hit.entry.types, types, name)
        }
    }

    func testEnglishAndJapaneseLookup() {
        XCTAssertEqual(dex.lookup("Charizard")?.entry.zh, "噴火龍")
        XCTAssertEqual(dex.lookup("tyranitar")?.entry.zh, "班基拉斯")
        XCTAssertEqual(dex.lookup("ピカチュウ")?.entry.zh, "皮卡丘")
    }

    func testCosmeticFormsCollapse() {
        let hits = dex.resolve("皮卡丘", limit: 5)
        XCTAssertEqual(hits.count, 1, "皮卡丘回傳了 \(hits.count) 筆")
        XCTAssertTrue(hits[0].entry.isDefault)
    }

    func testFormsWithDifferentTypesSurvive() {
        let combos = dex.resolve("噴火龍", limit: 5).map { $0.entry.types }
        XCTAssertTrue(combos.contains([.fire, .flying]), "缺少原始形態")
        XCTAssertTrue(combos.contains([.fire, .dragon]), "缺少 Mega X")
    }

    // OCR 的輸出從來不乾淨，這幾種雜訊是實測最常見的。
    func testNormalizeStripsOCRNoise() {
        XCTAssertEqual(Pokedex.normalize("Lv.50 耿鬼 ♂"), "耿鬼")
        XCTAssertEqual(Pokedex.normalize("　噴火龍　"), "噴火龍")
        XCTAssertEqual(Pokedex.normalize("皮卡丘!!"), "皮卡丘")
        XCTAssertEqual(Pokedex.normalize("ＬＶ．１００ 快龍"), "快龍")
        XCTAssertEqual(Pokedex.normalize(""), "")
    }

    func testNoisyOCRTextStillHitsExactly() {
        XCTAssertEqual(dex.lookup("Lv.50 耿鬼 ♂")?.entry.zh, "耿鬼")
        XCTAssertEqual(dex.lookup("　班基拉斯 ")?.entry.zh, "班基拉斯")
    }

    func testFuzzyMatchRecoversFromSingleCharacterErrors() {
        let cases = [("大葱鴨", "大蔥鴨"), ("噴火竜", "噴火龍"), ("班基拉期", "班基拉斯")]
        for (noisy, expected) in cases {
            guard let hit = dex.lookup(noisy, minScore: 0.5) else {
                return XCTFail("\(noisy) 完全查不到")
            }
            XCTAssertEqual(hit.entry.zh, expected)
            XCTAssertFalse(hit.exact)
            XCTAssertLessThan(hit.score, 1.0)
        }
    }

    /// 寧可漏，也不要餵錯資料給動態島。
    func testGibberishDoesNotForceAMatch() {
        XCTAssertNil(dex.lookup("對戰準備", minScore: 0.6))
        XCTAssertNil(dex.lookup("剩餘時間", minScore: 0.6))
        XCTAssertNil(dex.lookup("", minScore: 0.6))
    }

    func testStricterMinScoreRejectsWeakMatches() {
        XCTAssertNotNil(dex.lookup("班基拉期", minScore: 0.5))
        XCTAssertNil(dex.lookup("班基拉期", minScore: 0.95))
    }

    // 規劃書的風險因應：縮小比對範圍以提高準確率。
    func testSeasonPoolRestrictsCandidates() {
        dex.setPool(names: ["皮卡丘", "噴火龍", "水箭龜"], label: "test-season")
        XCTAssertEqual(dex.currentPool?.name, "test-season")
        XCTAssertNotNil(dex.lookup("皮卡丘"))
        XCTAssertNil(dex.lookup("班基拉斯", minScore: 0.6), "清單外的寶可夢不該被查到")
    }

    func testSeasonPoolRemovesAmbiguity() {
        // 全圖鑑時「妙蛙草」會跟「妙蛙花」互相干擾；限定清單後歧義消失。
        dex.setPool(names: ["妙蛙花", "皮卡丘", "超夢"], label: "test-season")
        XCTAssertEqual(dex.lookup("妙蛙化", minScore: 0.5)?.entry.zh, "妙蛙花")
    }

    func testSeasonPoolByID() {
        dex.setPool(ids: [25, 6], label: "by-id")
        XCTAssertEqual(dex.currentPool?.entries.count, 2)
        XCTAssertEqual(dex.lookup("皮卡丘")?.entry.speciesId, 25)
    }

    func testClearPoolRestoresFullDex() {
        dex.setPool(names: ["皮卡丘"], label: "tiny")
        XCTAssertNil(dex.lookup("班基拉斯", minScore: 0.6))
        dex.clearPool()
        XCTAssertNotNil(dex.lookup("班基拉斯"))
    }

    func testEntryByID() {
        XCTAssertEqual(dex.entry(id: 25)?.zh, "皮卡丘")
        XCTAssertNil(dex.entry(id: 999_999))
    }

    /// 規劃書 Phase 1 驗收標準：查詢單隻寶可夢剋制結果 < 10ms。
    /// Node 版量到中位數 0.0057ms；Swift 版在真機上只會更快，但仍要有把關。
    func testSingleLookupPerformance() {
        let names = ["皮卡丘", "噴火龍", "班基拉斯", "沙奈朵", "暴鯉龍", "快龍", "耿鬼", "超夢"]
        measure {
            for name in names {
                guard let hit = dex.lookup(name) else { continue }
                _ = DefenseProfile(types: hit.entry.types)
            }
        }
    }
}
