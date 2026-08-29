import XCTest
@testable import PokemonChampionCore

/// `Recognition` 是 `src/pipeline.mjs` 後半段（分邊 → 解析 → 去重）的移植。
/// 影像與 OCR 不在受測範圍 —— 測試直接餵合成的行，跟 Node 版對照同樣的行為。
final class RecognitionTests: XCTestCase {

    private func line(_ text: String, x: Double, y: Double = 0.5) -> RecognizedLine {
        RecognizedLine(text: text, centerX: x, centerY: y)
    }

    func testSplitsSidesByCenterX() {
        let r = Recognition.readTeams(lines: [
            line("噴火龍", x: 0.2),
            line("水箭龜", x: 0.8)
        ])
        XCTAssertEqual(r.mine.map(\.entry.zh), ["噴火龍"])
        XCTAssertEqual(r.theirs.map(\.entry.zh), ["水箭龜"])
        XCTAssertTrue(r.unresolved.isEmpty)
    }

    func testMiddleZoneIsDiscarded() {
        // 「對戰準備」是畫面標題，落在中間地帶 —— 要直接丟棄，
        // 連 unresolved 都不進，跟 Node 版一致。
        let r = Recognition.readTeams(lines: [line("對戰準備", x: 0.47)])
        XCTAssertTrue(r.isEmpty)
        XCTAssertTrue(r.unresolved.isEmpty)
    }

    func testUnresolvableTextIsReportedNotGuessed() {
        let r = Recognition.readTeams(lines: [line("回復藥", x: 0.2)])
        XCTAssertTrue(r.mine.isEmpty)
        XCTAssertEqual(r.unresolved.map(\.text), ["回復藥"])
    }

    func testShortLinesAreSkipped() {
        let r = Recognition.readTeams(lines: [line("龍", x: 0.2), line("  ", x: 0.2)])
        XCTAssertTrue(r.isEmpty)
        XCTAssertTrue(r.unresolved.isEmpty)
    }

    func testOCRNoiseIsTolerated() {
        // 等級前綴與形近字（竜→龍）都要救得回來 —— 與 PokedexTests 的容錯行為一致。
        let r = Recognition.readTeams(lines: [
            line("Lv.50 噴火竜", x: 0.1),
            line("班基拉斯♂", x: 0.9)
        ])
        XCTAssertEqual(r.mine.first?.entry.zh, "噴火龍")
        XCTAssertEqual(r.mine.first?.exact, false)
        XCTAssertEqual(r.theirs.first?.entry.zh, "班基拉斯")
    }

    func testDedupesPerSideAndOrdersTopToBottom() {
        let r = Recognition.readTeams(lines: [
            line("耿鬼", x: 0.2, y: 0.6),
            line("噴火龍", x: 0.2, y: 0.1),
            line("噴火龍", x: 0.2, y: 0.9),   // 同一隻重複出現，只留一筆
            line("噴火龍", x: 0.8, y: 0.3)    // 對面出現同名不受我方去重影響
        ])
        XCTAssertEqual(r.mine.map(\.entry.zh), ["噴火龍", "耿鬼"])
        XCTAssertEqual(r.theirs.map(\.entry.zh), ["噴火龍"])
    }

    func testAnalyzeProducesMatchupAndSummary() {
        let (reading, matchup, summary) = Recognition.analyze(lines: [
            line("噴火龍", x: 0.2, y: 0.1),
            line("暴鯉龍", x: 0.2, y: 0.3),
            line("班基拉斯", x: 0.8, y: 0.1)
        ])
        XCTAssertEqual(reading.mine.count, 2)
        XCTAssertEqual(matchup?.matrix.count, 2)
        XCTAssertEqual(matchup?.matrix[0][0].incoming, 4)   // 岩石 → 噴火龍
        XCTAssertTrue(summary?.threat.contains("班基拉斯") ?? false)
    }

    func testAnalyzeOnEmptyScreenReturnsNil() {
        let (reading, matchup, summary) = Recognition.analyze(lines: [])
        XCTAssertTrue(reading.isEmpty)
        XCTAssertNil(matchup)
        XCTAssertNil(summary)
    }

    func testLayoutDefaultsMatchNodePipeline() {
        // DEFAULT_LAYOUT 的數字是 Phase 0 實測出來的，兩邊必須一致。
        let l = BattleLayout.battlePrepSplit
        XCTAssertEqual(l.mineUntil, 0.45)
        XCTAssertEqual(l.theirsFrom, 0.5)
        XCTAssertEqual(l.top, 0.05)
        XCTAssertEqual(l.height, 0.85)
        XCTAssertEqual(l.scale, 0.4)
        XCTAssertEqual(l.minScore, 0.6)
    }
}
