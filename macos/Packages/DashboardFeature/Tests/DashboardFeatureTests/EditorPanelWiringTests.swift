import Foundation
import Testing

@Suite("Editor panel wiring (task-3)")
struct EditorPanelWiringTests {
    /// #filePath: <root>/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/本ファイル
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }

    private func dashboardSource() throws -> String {
        let url = repoRoot.appendingPathComponent(
            "macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("解決トリガーは target 全体（peerCount を含む）である")
    func resolveTriggerUsesWholeTarget() throws {
        let text = try dashboardSource()

        #expect(text.contains(".task(id: editorPanel.target)"))
        #expect(!text.contains(".task(id: editorPanel.target."))
        #expect(
            text.contains(
                ".task(id: editorPanel.target) {\n                await editorPanel.resolve(workspaces: editorPanelWorkspaces)"
            )
        )
    }

    @Test("選択・作業ツリー変化・初期表示・解決の4経路がcoordinatorへ転送されている")
    func allEventsAreForwarded() throws {
        let text = try dashboardSource()

        #expect(text.contains(".onAppear {\n            updateEditorPanel()"))
        #expect(text.contains(".onChange(of: router.selectedSession)"))
        #expect(text.contains(".onChange(of: editorPanelWorkspaces)"))
        #expect(
            text.contains(
                ".onChange(of: editorPanelWorkspaces) { _, _ in\n            updateEditorPanel()"
            )
        )
        #expect(text.components(separatedBy: "updateEditorPanel()").count - 1 == 4)
    }
}
