import XCTest

/// 全 11 画面のスクリーンショットを取得し `doc/screenshots/actual/` に保存する。
/// 参照: `ios-design.html`（`doc/screenshots/reference/` に抽出）
final class PhloxMobileScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    private let outputDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("doc/screenshots/actual", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 11 screens

    func testScreenshot01ConnectionSettings() throws {
        try capture(.connectionSettings, waitFor: app.staticTexts["接続設定"])
    }

    func testScreenshot02SessionList() throws {
        launch(screen: .sessionList)
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 12), "② Projects 一覧が表示されること")
        XCTAssertTrue(
            app.staticTexts["あなたの番"].waitForExistence(timeout: 5),
            "「あなたの番」（注目）セクションが表示されること"
        )
        saveScreenshot(named: UITestingScreen.sessionList.fileName)
    }

    func testScreenshot03SessionDetailApproval() throws {
        launch(screen: .sessionDetail)
        XCTAssertTrue(
            app.descendants(matching: .any)[AccessibilityID.sessionDetail].waitForExistence(timeout: 12),
            "\(UITestingScreen.sessionDetail.designLabel) が表示されること"
        )
        XCTAssertTrue(app.staticTexts["Rose"].waitForExistence(timeout: 5))
        saveScreenshot(named: UITestingScreen.sessionDetail.fileName)
    }

    func testScreenshot05DeleteConfirmation() throws {
        try capture(.deleteConfirmation, waitFor: app.staticTexts["セッションを削除しますか？"])
    }

    func testScreenshot06LaunchGate() throws {
        try capture(.launchGate, waitFor: app.staticTexts["エージェントを止めないリモコン"])
    }

    func testScreenshot07ChatAnswer() throws {
        launch(screen: .chatAnswer)
        XCTAssertTrue(app.staticTexts["質問待ち"].waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "/approvals")).firstMatch
                .waitForExistence(timeout: 5)
        )
        saveScreenshot(named: UITestingScreen.chatAnswer.fileName)
    }

    func testScreenshot08CodexApprovalSheet() throws {
        launch(screen: .codexApproval)
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.sessionDetail].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Mint"].waitForExistence(timeout: 5))
        let approve = app.buttons[AccessibilityID.approvalAccept]
        if !approve.waitForExistence(timeout: 10) {
            XCTAssertTrue(app.buttons["承認"].waitForExistence(timeout: 5))
            app.buttons["承認"].tap()
        } else {
            approve.tap()
        }
        XCTAssertTrue(app.staticTexts["承認の応答を選択"].waitForExistence(timeout: 8))
        saveScreenshot(named: UITestingScreen.codexApproval.fileName)
    }

    func testScreenshot10Unreachable() throws {
        launch(screen: .unreachable)
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Mac に到達できません"].waitForExistence(timeout: 12))
        saveScreenshot(named: UITestingScreen.unreachable.fileName)
    }

    func testScreenshot11EmptyState() throws {
        try capture(.empty, waitFor: app.staticTexts["セッションがありません"])
    }

    // MARK: - Helpers

    private func capture(_ screen: UITestingScreen, waitFor element: XCUIElement) throws {
        launch(screen: screen)
        XCTAssertTrue(element.waitForExistence(timeout: 12), "\(screen.designLabel) が表示されること")
        saveScreenshot(named: screen.fileName)
    }

    private func launch(screen: UITestingScreen, preferredLanguage: String = "ja") {
        app.launchArguments = [
            "-UITesting",
            "-UIScreen=\(screen.rawValue)",
            "-UIViewAnimationsEnabled", "NO",
            "-AppleLanguages", "(\(preferredLanguage))",
            "-AppleLocale", preferredLanguage == "ja" ? "ja_JP" : "en_US",
        ]
        app.launchEnvironment = [
            "SIMULATOR_KEYBOARD_FORCE_ENABLED": "1",
        ]
        app.launch()
    }

    private func saveScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }
}

/// アプリ側 `UITestingSupport.Screen` と同じ rawValue（テストターゲットからは App を import できないため複製）
private enum UITestingScreen: String, CaseIterable {
    case connectionSettings
    case sessionList
    case sessionDetail
    case deleteConfirmation
    case launchGate
    case chatAnswer
    case codexApproval
    case unreachable
    case empty

    var fileName: String {
        switch self {
        case .connectionSettings: "01-connection-settings"
        case .sessionList: "02-session-list"
        case .sessionDetail: "03-session-detail-approval"
        case .deleteConfirmation: "05-delete-confirmation"
        case .launchGate: "06-launch-gate"
        case .chatAnswer: "07-chat-answer"
        case .codexApproval: "08-codex-approval-sheet"
        case .unreachable: "10-unreachable"
        case .empty: "11-empty-state"
        }
    }

    var designLabel: String {
        switch self {
        case .connectionSettings: "① 接続設定"
        case .sessionList: "② セッション一覧"
        case .sessionDetail: "③ セッション詳細・承認"
        case .deleteConfirmation: "⑤ 削除確認（カスケード）"
        case .launchGate: "⑥ 起動ゲート（Face ID）"
        case .chatAnswer: "⑦ 質問への回答（send）"
        case .codexApproval: "⑧ 承認の応答（Codex 4 択）"
        case .empty: "⑪ 空状態（初回）"
        case .unreachable: "⑩ 到達不可（Mac スリープ）"
        }
    }
}

private enum AccessibilityID {
    static let sessionDetail = "sessionDetail"
    static let approvalAccept = "approvalAccept"
}
