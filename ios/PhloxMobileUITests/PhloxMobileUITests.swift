import XCTest

/// 画面表示付き E2E（XCUITest）。`-UITesting` 起動引数でモック環境に差し替える。
/// シミュレーターを開いた状態で `xcodebuild test` または Xcode ⌘U を実行すると操作が目視できる。
final class PhloxMobileUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(scenario: String) {
        app.launchArguments = ["-UITesting", "-UIScenario=\(scenario)", "-UIViewAnimationsEnabled", "NO"]
        app.launch()
    }

    private func waitForSessionList(timeout: TimeInterval = 10) -> XCUIElement {
        let list = app.descendants(matching: .any)[AccessibilityID.sessionList]
        XCTAssertTrue(list.waitForExistence(timeout: timeout))
        return list
    }

    // MARK: - UC-03 一覧表示

    func testGoldenPathShowsSessionList() throws {
        launch(scenario: "goldenPath")
        _ = waitForSessionList()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Rose"].exists)
        XCTAssertTrue(app.staticTexts["あなたの番"].exists)
    }

    // MARK: - UC-04 承認フロー（詳細 + 承認バー）

    func testTapAttentionRowOpensDetailWithApproval() throws {
        launch(scenario: "goldenPath")
        _ = waitForSessionList()

        app.descendants(matching: .any)[AccessibilityID.attentionRow("sess-rose")].tap()

        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.sessionDetail].waitForExistence(timeout: 10),
                      "承認待ち行タップ後に詳細画面へ遷移すること")
        XCTAssertTrue(app.staticTexts["Rose"].waitForExistence(timeout: 3))

        var approve = app.buttons[AccessibilityID.approvalAccept]
        if !approve.waitForExistence(timeout: 15) {
            approve = app.buttons["承認"]
        }
        XCTAssertTrue(approve.waitForExistence(timeout: 2), "承認ボタンが表示されること")
        approve.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '応答を送信'")).firstMatch
                .waitForExistence(timeout: 10)
        )
    }

    // MARK: - UC-01 起動ゲート

    func testLaunchGateShowsWhenScenarioRequiresAuth() throws {
        launch(scenario: "launchGate")

        let gate = app.descendants(matching: .any)[AccessibilityID.launchGateUnlock]
        XCTAssertTrue(gate.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["エージェントを止めないリモコン"].waitForExistence(timeout: 3))
    }

    // MARK: - UC-03 空状態

    func testEmptyStateShowsCreatePrompt() throws {
        launch(scenario: "empty")
        _ = waitForSessionList()

        XCTAssertTrue(app.staticTexts["セッションがありません"].waitForExistence(timeout: 8))
    }
}

/// UI テスト用 identifier（アプリ側 `AccessibilityID` と一致させる）
private enum AccessibilityID {
    static let sessionList = "sessionList"
    static let launchGateUnlock = "launchGateUnlock"
    static let sessionDetail = "sessionDetail"
    static let approvalAccept = "approvalAccept"

    static func attentionRow(_ id: String) -> String { "attentionRow.\(id)" }
}
