import XCTest

/// 02 C：ドロワーを廃止し、ターミナル・変更はタブで開く。
@MainActor
final class PanelUITests: XCTestCase {
    /// セッション未選択の ⌃⌘T は上段右端の共通ターミナル（ホーム）を出す。もう一度押しても閉じない（前に出すだけ）。
    func testTerminalShortcutShowsCommonTerminal() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app: XCUIApplication = try isolated.application()

        app.typeKey("t", modifierFlags: [.command, .control])
        let terminalPanel = app.groups["user-terminal-panel"]
        XCTAssertTrue(terminalPanel.waitForExistence(timeout: 10))

        try isolated.assertExclusiveOwnership()
        app.typeKey("t", modifierFlags: [.command, .control])
        XCTAssertTrue(terminalPanel.waitForExistence(timeout: 2))
    }

    /// 変更タブはセッションに属する。セッション未選択の ⌃⌘E では何も開かない。
    func testChangesShortcutNeedsSession() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app: XCUIApplication = try isolated.application()

        app.typeKey("e", modifierFlags: [.command, .control])
        XCTAssertFalse(app.groups["editor-panel"].waitForExistence(timeout: 2))
    }
}
