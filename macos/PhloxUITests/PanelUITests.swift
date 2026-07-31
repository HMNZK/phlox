import XCTest

final class PanelUITests: XCTestCase {
    func testTerminalPanelShortcutTogglesPanel() {
        let app = XCUIApplication()
        app.launch()

        app.typeKey("t", modifierFlags: [.command, .option])
        let terminalPanel = app.otherElements["user-terminal-panel"]
        XCTAssertTrue(terminalPanel.waitForExistence(timeout: 10))

        app.typeKey("t", modifierFlags: [.command, .option])
        XCTAssertFalse(terminalPanel.waitForExistence(timeout: 2))
    }

    func testEditorPanelShortcutShowsPanel() {
        let app = XCUIApplication()
        app.launch()

        app.typeKey("e", modifierFlags: [.command, .option])
        XCTAssertTrue(app.otherElements["editor-panel"].waitForExistence(timeout: 10))
    }
}
