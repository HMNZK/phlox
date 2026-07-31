import XCTest

/// 実行中セッションの入力バー（XCUITest）。
/// 何も打っていない間は停止ボタンだけを出し、打ち始めたら送信ボタンが現れて
/// 追加指示を送れること。`-UITesting -UIScenario=goldenPath` のモック環境で実行する。
final class SessionInputBarRunningUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UIScenario=goldenPath", "-UIViewAnimationsEnabled", "NO"]
        app.launch()
    }

    /// 実行中（Tulip）を開き、空入力→入力ありで右端のボタン構成が切り替わること。
    func testRunningRevealsSendButtonOnlyAfterTyping() throws {
        let list = app.descendants(matching: .any)["sessionList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "セッション一覧が表示されること")
        app.descendants(matching: .any)["sessionRow.sess-tulip"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["sessionDetail"].waitForExistence(timeout: 10),
            "詳細画面へ遷移すること"
        )

        let stop = app.buttons["停止"]
        let send = app.buttons["送信"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "実行中は停止ボタンが出ること")
        XCTAssertFalse(send.exists, "空入力の実行中は送信ボタンを出さないこと")

        let field = app.textViews["回答を入力…"].firstMatch
        let input = field.exists ? field : app.textFields["回答を入力…"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), "入力欄があること")
        input.tap()
        input.typeText("追加の指示")

        XCTAssertTrue(send.waitForExistence(timeout: 5), "入力すると送信ボタンが現れること")
        XCTAssertTrue(stop.exists, "送信ボタンが出ても停止ボタンは残ること")
        XCTAssertTrue(send.isEnabled, "入力があるので送信できること")
    }
}
