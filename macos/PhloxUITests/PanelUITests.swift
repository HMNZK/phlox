import XCTest

@MainActor
final class PanelUITests: XCTestCase {
    func testTerminalPanelShortcutTogglesPanel() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self, initialWidth: 700, expectedWidth: 700)
        let app: XCUIApplication = try isolated.application()

        app.typeKey("t", modifierFlags: [.command, .control])
        let terminalPanel = app.groups["user-terminal-panel"]
        XCTAssertTrue(terminalPanel.waitForExistence(timeout: 10))

        try isolated.assertExclusiveOwnership()
        app.typeKey("t", modifierFlags: [.command, .control])
        XCTAssertFalse(terminalPanel.waitForExistence(timeout: 2))
    }

    func testEditorPanelShortcutShowsPanel() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app: XCUIApplication = try isolated.application()

        app.typeKey("e", modifierFlags: [.command, .control])
        XCTAssertTrue(app.groups["editor-panel"].waitForExistence(timeout: 10))
    }
}
