import Foundation
import Testing

@Suite struct Wave3SessionDetailChromeWhiteboxTests {
    @Test func detailUsesCustomChromeAndRoutesEveryMenuAction() throws {
        let source = try sourceText("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(source.contains("@Environment(\\.dismiss)"))
        #expect(source.contains(".toolbar(.hidden, for: .navigationBar)"))
        #expect(source.contains("private var topBar"))
        #expect(source.contains("Text(viewModel.displayName)"))
        #expect(source.contains("Menu {"))
        #expect(source.contains("Button(\"モデル変更\")"))
        #expect(source.contains("viewModel.isModelSheetPresented = true"))
        #expect(source.contains("Button(\"名前変更\")"))
        #expect(source.contains("viewModel.beginRename()"))
        #expect(source.contains("Button(\"削除\", role: .destructive, action: onDelete)"))
    }

    @Test func renameAlertCommitsBoundDraft() throws {
        let source = try sourceText("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(source.contains(".alert(\"名前変更\", isPresented: $viewModel.isRenamePresented)"))
        #expect(source.contains("TextField(\"セッション名\", text: $viewModel.renameDraft)"))
        #expect(source.contains("Task { await viewModel.commitRename() }"))
    }

    @Test func inputBarDrawsModelSelectorChipAndScrollDismissesKeyboard() throws {
        // wave-4 task-4: 入力欄内モデルチップ復活＋スクロールでキーボード収納。
        let source = try sourceText("Sources/Features/SessionDetail/SessionDetailView.swift")

        #expect(source.contains("providesModelSelectorChip = true"))
        #expect(source.contains("private func modelSelectorChip"))
        #expect(source.contains(".scrollDismissesKeyboard"))
    }

    @Test func tabBarIsASiblingThatReducesAvailableContentHeight() throws {
        let source = try appRootSourceText()

        #expect(!source.contains("selectedTabContent(listVM: listVM, appShell: appShell, usageVM: usageVM)\n                .safeAreaInset"))
        #expect(source.contains("VStack(spacing: 0) {\n                selectedTabContent"))
        #expect(source.contains("appTabBar(appShell: appShell)"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func appRootSourceText() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iosRoot = packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: iosRoot.appendingPathComponent("App/AppRoot.swift"), encoding: .utf8)
    }
}
