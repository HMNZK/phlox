import SwiftUI
import AgentDomain
import DesignSystem

/// 右端のファイル / Git（ADR 0195）。変更一覧は中央と共有する。
struct InspectorView: View {
    @Environment(\.localizationBundle) private var bundle
    @Bindable var router: AppRouter
    let project: Project?
    @Binding var fileTreeModels: [String: FileTreeModel]
    let files: FileTabDocuments
    let editorPanel: EditorPanelCoordinator
    var runningSessionNames: [String] = []
    var isOverlay = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(spacing: 0) {
            InspectorTabPicker(selection: $router.inspectorTab)
            if router.inspectorTab == .files {
                FileTreeInspectorView(router: router, project: project, models: $fileTreeModels, files: files, isOverlay: isOverlay)
            } else {
                GitInspectorView(model: editorPanel.viewModel, workingDirectory: project?.directoryPath ?? "",
                    openChanges: openChanges, openFile: openFile, focusRequest: router.inspectorFocusToken,
                    runningSessionNames: runningSessionNames)
                    .id(project?.id)
            }
        }
            .background(isOverlay ? DSColor.popoverBackground : DSColor.surface)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("インスペクタ", bundle: bundle))
            .task(id: router.inspectorTab) {
                if router.inspectorTab == .git, editorPanel.viewModel.listState != .noProject {
                    await editorPanel.viewModel.refresh()
                }
            }
    }

    private func openChanges(_ path: String?, _ source: WorkingTreeSource, _ commit: Bool) {
        guard let project else { return }
        router.selectedProjectID = project.id
        router.openChildTab(.changes)
        if isOverlay { router.inspectorVisible = false }
        let model = editorPanel.viewModel
        if commit { model.requestCommitFocus() }
        if let path { Task { await model.select(path, source: source) } }
    }

    private func openFile(_ path: String) {
        guard let project else { return }
        Task {
            guard let relative = await FileTabOpening.projectRelativeChangePath(path, workingDirectory: project.directoryPath) else { return }
            let root = await FileTabOpening.root(for: project.directoryPath)
            guard router.selectedProjectID == project.id,
                  editorPanel.target.workingDirectory == project.directoryPath else { return }
            files.openFileTab(projectID: project.id, root: root, relativePath: relative, router: router,
                requestedWorkingDirectory: project.directoryPath, currentWorkingDirectory: editorPanel.target.workingDirectory)
            if isOverlay { router.inspectorVisible = false }
        }
    }
}

struct InspectorTabPicker: View {
    @Environment(\.localizationBundle) private var bundle
    @Binding var selection: InspectorTab
    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            segment(.files, title: "ファイル", shortcut: "⌃⌘B")
            segment(.git, title: "Git", shortcut: "⇧⌃⌘G")
        }
        .padding(DSSpacing.xxs)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: DSLayout.inspectorSegmentRadius))
        .padding(.horizontal, DSSpacing.m).padding(.top, DSSpacing.s + DSSpacing.xxs).padding(.bottom, DSSpacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("右サイドバーの表示", bundle: bundle))
    }

    private func segment(_ tab: InspectorTab, title: LocalizedStringKey, shortcut: String) -> some View {
        Button { selection = tab } label: {
            Text(title, bundle: bundle).font(DSFont.auxiliary.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: DSLayout.fileTreeInputHeight)
                .foregroundStyle(selection == tab ? DSColor.textPrimary : DSColor.textSecondary)
                .background(selection == tab ? DSColor.controlBackground : DSColor.clear,
                            in: RoundedRectangle(cornerRadius: DSLayout.fileTreeInputRadius))
                .overlay(RoundedRectangle(cornerRadius: DSLayout.fileTreeInputRadius)
                    .strokeBorder(selection == tab ? DSColor.controlBorder : DSColor.clear, lineWidth: DSLayout.controlBorderWidth))
        }.buttonStyle(.plain)
        .help(Text(title, bundle: bundle) + Text(verbatim: " " + shortcut))
        .accessibilityLabel(Text(title, bundle: bundle))
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
        .accessibilityIdentifier("inspector-tab-\(tab.rawValue)")
    }
}
