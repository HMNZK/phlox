import XCTest

/// プロジェクトタブの追加口と、プロジェクト単位の変更タブを確認する。
@MainActor
final class PanelUITests: XCTestCase {
    func testProjectTabAddButtonIsAvailableWithoutASelectedProject() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app: XCUIApplication = try isolated.application()

        XCTAssertTrue(app.buttons["tabs.project.add"].waitForExistence(timeout: 10))
        try isolated.assertExclusiveOwnership()
    }

    /// 変更タブはプロジェクトに属する。プロジェクト未選択の ⌃⌘E では何も開かない。
    func testChangesShortcutNeedsProject() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app: XCUIApplication = try isolated.application()

        app.typeKey("e", modifierFlags: [.command, .control])
        XCTAssertFalse(app.groups["editor-panel"].waitForExistence(timeout: 2))
    }
}
