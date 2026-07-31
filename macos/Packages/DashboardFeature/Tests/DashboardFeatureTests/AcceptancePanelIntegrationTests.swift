// task-5 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-5.md — 両パネルの統合仕上げ（容器確定・プロトタイプ撤去・
// エディタホットキー・アプリ終了時の後始末・XCUITest 追加）。
// ソーススキャン形式。UI の実挙動はフェーズ4（統合検証）の XCUITest 実走が担う。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing

@Suite("Panel integration acceptance (task-5)")
struct AcceptancePanelIntegrationTests {

    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }

    private func source(_ relativePath: String) throws -> String {
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path)
    }

    @Test("⌘⌥E のホットキーが Commands に登録され、router のトグルへ配線されている")
    func editorHotkeyIsRegistered() throws {
        let app = try source("macos/App/PhloxApp.swift")
        #expect(app.contains(#"keyboardShortcut("e", modifiers: [.command, .option])"#))
        #expect(app.contains("toggleEditorPanel()"))
    }

    @Test("容器プロトタイプが撤去されている")
    func prototypeIsRemoved() {
        #expect(
            !exists("macos/Packages/DashboardFeature/Sources/DashboardFeature/UserTerminal/PanelContainerPrototype.swift"),
            "ゲート②で敗れた方式のプロトタイプコードは task-5 で撤去する契約")
    }

    @Test("アプリ終了経路でユーザーターミナルの shutdown が配線されている")
    func shutdownIsWiredToAppTermination() throws {
        let delegate = try source("macos/App/AppDelegate.swift")
        #expect(delegate.contains("shutdown"))
        #expect(delegate.lowercased().contains("userterminal"))
    }

    @Test("エディタパネルの View に XCUITest 用の accessibilityIdentifier がある")
    func editorPanelHasAccessibilityIdentifier() throws {
        let panel = try source(
            "macos/Packages/DashboardFeature/Sources/DashboardFeature/Editor/EditorPanelView.swift")
        #expect(panel.contains(#"accessibilityIdentifier("editor-panel")"#))
    }

    @Test("XCUITest がパネル出現を identifier で検査している")
    func uiTestExistsAndChecksPanels() throws {
        let uiTest = try source("macos/PhloxUITests/PanelUITests.swift")
        #expect(uiTest.contains("XCUIApplication"))
        #expect(uiTest.contains("user-terminal-panel"))
        #expect(uiTest.contains("editor-panel"))
    }
}
