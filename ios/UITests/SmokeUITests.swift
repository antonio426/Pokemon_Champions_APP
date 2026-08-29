import XCTest

/// 端到端冒煙測試：五個分頁都能開、搜尋找得到、
/// 內建範例圖跑得完「Vision OCR → 分邊 → 剋制分析」整條管線，
/// 分析結果能帶回對戰分析頁並釘上動態島。
///
/// 注意：sheet 內部不做「點擊列」—— 這台環境上 XCUITest 對 SwiftUI sheet 的
/// 座標映射不可靠（會點到相鄰元素）。隊伍改由「截圖辨識 → 帶入對戰分析頁」
/// 這條主視窗路徑建立，sheet 只驗證搜尋結果存在後以下滑手勢關閉。
final class SmokeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAllTabsAndCoreFlows() throws {
        let app = XCUIApplication()
        app.launch()

        // SwiftUI 的 List 是懶載入：畫面外的列連 AX 節點都不存在，
        // 要先捲到可見才能斷言或點擊。先往下找，找不到再往回捲。
        func revealByScrolling(_ element: XCUIElement, maxSwipes: Int = 10) {
            if element.exists { return }
            for _ in 0..<maxSwipes {
                app.swipeUp()
                if element.exists { return }
            }
            for _ in 0..<maxSwipes {
                app.swipeDown()
                if element.exists { return }
            }
        }

        // ── 對戰分析：搜尋 sheet 打得開、模糊搜尋找得到、關得掉 ──
        XCTAssertTrue(app.tabBars.buttons["對戰分析"].waitForExistence(timeout: 30))
        app.buttons["加入寶可夢"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        field.typeText("Charizard\n")
        XCTAssertTrue(app.buttons["search-result-6"].waitForExistence(timeout: 30),
                      "搜尋 Charizard 應找到 #6 噴火龍")
        shot(app, "1-搜尋")
        // 下滑收掉 sheet（手勢不吃座標映射問題）
        app.navigationBars.firstMatch.swipeDown()
        let sheetGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [sheetGone], timeout: 20), .completed,
                       "下滑後 sheet 沒有收合")

        // ── 截圖辨識：內建範例圖 → 完整 OCR 管線 → 帶入隊伍 ──
        app.tabBars.buttons["截圖辨識"].tap()
        let demo = app.buttons["用內建範例圖試試"]
        XCTAssertTrue(demo.waitForExistence(timeout: 30))
        demo.tap()
        // Intel 模擬器上 Vision .accurate 需要一點時間
        XCTAssertTrue(app.staticTexts["我方（辨識結果）"].waitForExistence(timeout: 180),
                      "範例圖辨識沒有產出我方隊伍")
        shot(app, "2-截圖辨識結果")

        let matrixInDemo = app.staticTexts["對戰矩陣"]
        revealByScrolling(matrixInDemo)
        XCTAssertTrue(matrixInDemo.exists, "辨識完成後應有對戰矩陣區塊")
        shot(app, "3-截圖辨識矩陣")

        let carry = app.buttons["帶入對戰分析頁"]
        revealByScrolling(carry)
        XCTAssertTrue(carry.exists)
        carry.tap()

        // ── 對戰分析：隊伍已就位，完整分析區塊出現 ──
        app.tabBars.buttons["對戰分析"].tap()
        let summaryHeader = app.staticTexts["動態島摘要"]
        revealByScrolling(summaryHeader)
        XCTAssertTrue(summaryHeader.exists, "帶入隊伍後應出現動態島摘要")

        // ── 釘上動態島（模擬器支援 Live Activity）──
        let pin = app.buttons["釘上動態島"]
        revealByScrolling(pin, maxSwipes: 3)
        if pin.exists {
            pin.tap()
            XCTAssertTrue(app.buttons["更新動態島"].waitForExistence(timeout: 20),
                          "釘選後應出現更新／結束控制")
            shot(app, "4-動態島已釘選")
        }

        let threats = app.staticTexts["最該注意"]
        revealByScrolling(threats)
        XCTAssertTrue(threats.exists, "應有威脅分析區塊")
        shot(app, "5-對戰分析")

        // ── 圖鑑：清單 → 詳細頁 ──
        app.tabBars.buttons["圖鑑"].tap()
        let firstEntry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '妙蛙種子'")
        ).firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 30), "圖鑑第一筆應為妙蛙種子")
        firstEntry.tap()
        XCTAssertTrue(app.staticTexts["防禦面（被打）"].waitForExistence(timeout: 30))
        shot(app, "6-圖鑑詳細頁")

        // ── 屬性相剋 ──
        app.tabBars.buttons["屬性"].tap()
        XCTAssertTrue(app.staticTexts["防禦面總表"].waitForExistence(timeout: 30))
        shot(app, "7-屬性相剋")

        // ── 設定 ──
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.staticTexts["賽季清單"].waitForExistence(timeout: 30))
        shot(app, "8-設定")
    }
}
