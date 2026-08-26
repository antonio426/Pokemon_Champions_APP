import XCTest
@testable import PokemonChampionCore

final class MatchupTests: XCTestCase {

    private func c(_ name: String) -> Combatant {
        guard let combatant = Combatant(name: name) else {
            fatalError("測試資料有問題：查不到 \(name)")
        }
        return combatant
    }

    func testCombatantFromName() {
        XCTAssertEqual(c("噴火龍").types, [.fire, .flying])
        XCTAssertNil(Combatant(name: "這不是寶可夢的名字"))
    }

    func testBestSTAB() {
        let hit = Matchup.bestSTAB(c("噴火龍"), c("妙蛙花"))
        XCTAssertEqual(hit.multiplier, 2)
        XCTAssertEqual(hit.via, .fire)
    }

    func testPairMatchup() {
        let m = Matchup.pair(mine: c("噴火龍"), theirs: c("水箭龜"))
        XCTAssertEqual(m.outgoing.multiplier, 1)
        XCTAssertEqual(m.incoming.multiplier, 2)
        XCTAssertEqual(m.incoming.via, .water)
        XCTAssertEqual(m.edge, .unfavorable)
    }

    func testPairMatchupIsSymmetric() {
        let m = Matchup.pair(mine: c("水箭龜"), theirs: c("噴火龍"))
        XCTAssertEqual(m.outgoing.multiplier, 2)
        XCTAssertEqual(m.incoming.multiplier, 1)
        XCTAssertEqual(m.edge, .favorable)
    }

    func testEvenMatchup() {
        let m = Matchup.pair(mine: c("耿鬼"), theirs: c("沙奈朵"))
        XCTAssertEqual(m.edge, .even)
        XCTAssertEqual(m.outgoing.multiplier, m.incoming.multiplier)
    }

    func testVerdictStrings() {
        XCTAssertEqual(Matchup.verdict(for: 4), "致命")
        XCTAssertEqual(Matchup.verdict(for: 2), "克制")
        XCTAssertEqual(Matchup.verdict(for: 1), "普通")
        XCTAssertEqual(Matchup.verdict(for: 0.5), "不利")
        XCTAssertEqual(Matchup.verdict(for: 0.25), "幾乎無效")
        XCTAssertEqual(Matchup.verdict(for: 0), "無效")
    }

    func testTeamMatrixDimensions() {
        let mine = ["噴火龍", "沙奈朵", "耿鬼"].map(c)
        let theirs = ["水箭龜", "班基拉斯"].map(c)
        let r = Matchup.team(mine: mine, theirs: theirs)
        XCTAssertEqual(r.matrix.count, 3)
        r.matrix.forEach { XCTAssertEqual($0.count, 2) }
        XCTAssertEqual(r.matrix[0][1].incoming, 4)   // 班基拉斯的岩石打噴火龍
        XCTAssertEqual(r.matrix[0][1].incomingVia, .rock)
    }

    func testThreatRanking() {
        let r = Matchup.team(mine: ["噴火龍", "暴鯉龍", "快龍"].map(c),
                             theirs: ["皮卡丘", "妙蛙花", "班基拉斯"].map(c))
        XCTAssertEqual(r.threats[0].combatant.label, "班基拉斯")
        XCTAssertEqual(r.threats[0].count, 3)   // 岩石超效打中全部三隻飛行系
        XCTAssertEqual(r.threats[0].peak, 4)
    }

    func testAnswersFlagWhoIsSafe() {
        let r = Matchup.team(mine: ["沙奈朵", "噴火龍"].map(c), theirs: [c("班基拉斯")])
        let gardevoir = r.answers.first { $0.combatant.label == "沙奈朵" }
        let charizard = r.answers.first { $0.combatant.label == "噴火龍" }
        XCTAssertEqual(gardevoir?.safe, true)
        XCTAssertEqual(charizard?.safe, false)
        XCTAssertEqual(charizard?.worstIncoming, 4)
    }

    func testLiveSummary() {
        let s = Matchup.liveSummary(mine: ["噴火龍", "暴鯉龍", "快龍"].map(c),
                                    theirs: ["皮卡丘", "班基拉斯"].map(c))
        XCTAssertTrue(s.threat.contains("班基拉斯"), s.threat)
        XCTAssertTrue(s.threat.contains("4×"), s.threat)
        XCTAssertEqual(s.threatCount, 3)
    }

    func testLiveSummaryFallbackStrings() {
        let s = Matchup.liveSummary(mine: [c("伊布")], theirs: [c("百變怪")])
        XCTAssertEqual(s.threat, "目前無明顯剋制")
        XCTAssertEqual(s.answer, "本系無超效打點")
        XCTAssertEqual(s.threatCount, 0)
    }

    func testEmptyOpposingTeamDoesNotCrash() {
        let r = Matchup.team(mine: [c("噴火龍")], theirs: [])
        XCTAssertTrue(r.matrix[0].isEmpty)
        XCTAssertTrue(r.threats.isEmpty)
        XCTAssertEqual(r.answers[0].count, 0)
    }

    /// LiveSummary 會直接成為 Live Activity 的 ContentState，
    /// ActivityKit 每次更新都要序列化它，所以 Codable 必須是可靠的。
    func testLiveSummaryRoundTripsThroughCodable() throws {
        let original = Matchup.liveSummary(mine: [c("噴火龍")], theirs: [c("班基拉斯")])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LiveSummary.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertLessThan(data.count, 512, "動態島的 payload 不該這麼大")
    }

    func testMultiplierFormatting() {
        XCTAssertEqual(Matchup.format(4), "4")
        XCTAssertEqual(Matchup.format(2), "2")
        XCTAssertEqual(Matchup.format(1), "1")
        XCTAssertEqual(Matchup.format(0.5), "½")
        XCTAssertEqual(Matchup.format(0.25), "¼")
        XCTAssertEqual(Matchup.format(0), "0")
    }
}
