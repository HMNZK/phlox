import AppKit
import DesignSystem
import SwiftUI

/// Git の操作を集約し、差分は「変更」の子タブへ渡す。
struct GitInspectorView: View {
    @Bindable var model: EditorPanelViewModel
    let workingDirectory: String
    var openChanges: (String?, WorkingTreeSource, Bool) -> Void
    var openFile: (String) -> Void
    var focusRequest = 0
    var runningSessionNames: [String] = []
    @AppStorage("phlox.inspector.git.changesExpanded") var changesExpanded = true
    @AppStorage("phlox.inspector.git.commitsExpanded") var commitsExpanded = false
    @AppStorage("phlox.inspector.git.branchesExpanded") var branchesExpanded = false
    @AppStorage("phlox.inspector.git.remotesExpanded") var remotesExpanded = false
    @AppStorage("phlox.inspector.git.stashesExpanded") var stashesExpanded = false
    @AppStorage("phlox.inspector.git.graphExpanded") var graphExpanded = false
    @State var historyMenu: GitHistoryRowID?
    @State var input: GitHistoryInput?
    @State var inputText = ""
    @State var pendingAction: GitRepositoryAction?
    @State var remoteExpansion: [String: Bool] = [:]
    @FocusState var historyInputFocused: Bool
    @State private var hovered: GitChangeSelection?
    enum FocusArea: Hashable { case list, header, historyHeader(GitHistorySection) }
    @FocusState var focusedArea: FocusArea?
    @State private var rowMenu: GitChangeSelection?
    @Environment(\.locale) var locale
    @Environment(\.localizationBundle) var bundle
    var snapshotHoveredSelection: GitChangeSelection? = nil
    private var selected: GitChangeSelection? { model.gitSelection }
    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }

    init(model: EditorPanelViewModel, workingDirectory: String,
         openChanges: @escaping (String?, WorkingTreeSource, Bool) -> Void,
         openFile: @escaping (String) -> Void, focusRequest: Int = 0,
         runningSessionNames: [String] = [], snapshotHoveredSelection: GitChangeSelection? = nil,
         defaults: UserDefaults? = nil) {
        self.model = model
        self.workingDirectory = workingDirectory
        self.openChanges = openChanges
        self.openFile = openFile
        self.focusRequest = focusRequest
        self.runningSessionNames = runningSessionNames
        self.snapshotHoveredSelection = snapshotHoveredSelection
        _changesExpanded = AppStorage(wrappedValue: true, "phlox.inspector.git.changesExpanded", store: defaults)
        _commitsExpanded = AppStorage(wrappedValue: false, "phlox.inspector.git.commitsExpanded", store: defaults)
        _branchesExpanded = AppStorage(wrappedValue: false, "phlox.inspector.git.branchesExpanded", store: defaults)
        _remotesExpanded = AppStorage(wrappedValue: false, "phlox.inspector.git.remotesExpanded", store: defaults)
        _stashesExpanded = AppStorage(wrappedValue: false, "phlox.inspector.git.stashesExpanded", store: defaults)
        _graphExpanded = AppStorage(wrappedValue: false, "phlox.inspector.git.graphExpanded", store: defaults)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.listState == .ready { GitCommitPanel(viewModel: model) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section { if changesExpanded { sectionContent } } header: { sectionHeader }
                        ForEach(GitHistorySection.allCases, id: \.self) { section in
                            Section { if expanded(section) { historyContent(section) } } header: { historyHeader(section) }
                                .id(section)
                        }
                    }
                }
                .focusable().focused($focusedArea, equals: .list).focusEffectDisabled()
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.space) {
                    guard focusedArea == .list, case .change(let selected) = model.activeGitRow,
                          model.visibleGitRows(changesExpanded: changesExpanded).contains(selected),
                          !model.isWorkflowBusy else { return .ignored }
                    toggleStage(selected); return .handled
                }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard focusedArea == .list, let row = model.activeGitRow, visibleRows.contains(row) else { return .ignored }
                    if press.modifiers == .control {
                        if case .change(let selected) = row { rowMenu = selected }
                        else { historyMenu = row }
                    }
                    else if press.modifiers.isEmpty { activateHistoryRow(row) }
                    else { return .ignored }
                    return .handled
                }
                .onChange(of: model.gitSelection) { _, current in if let current { proxy.scrollTo(rowID(current)) } }
                .onChange(of: model.activeGitRow) { _, row in if let row { proxy.scrollTo(row) } }
                .accessibilityIdentifier("git-inspector-list")
                .accessibilityLabel(Text("変更ファイル", bundle: bundle))
            }
        }
        .background(DSColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Git", bundle: bundle))
        .accessibilityIdentifier("inspector-git")
        .onChange(of: focusRequest, initial: true) { _, request in
            if request > 0 {
                focusedArea = changesExpanded ? .list : .header
            }
        }
        .onChange(of: changesExpanded) { _, expanded in
            if !expanded { rowMenu = nil; focusedArea = .header }
        }
        .task(id: ObjectIdentifier(model)) {
            for section in GitHistorySection.allCases { await model.setHistorySection(section, expanded: expanded(section)) }
        }
        .onChange(of: model.stashFocusToken) { _, _ in beginInput(.stash) }
        .onChange(of: model.isWorkflowBusy) { wasBusy, busy in
            if wasBusy && !busy && !model.workflowStatusIsError { input = nil }
        }
        .dsDialog(isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            if let action = pendingAction {
                GitActionConfirmation(action: action, runningSessions: action.changesWorkingTree ? runningSessionNames : [],
                    targetLabel: confirmationTarget(action),
                    changeCount: Set(model.stagedChanges.map(\.path) + model.unstagedChanges.map(\.path)).count,
                    untrackedCount: model.unstagedChanges.filter { $0.kind == .untracked }.count,
                    cancel: { pendingAction = nil }, perform: {
                        pendingAction = nil
                        Task { await model.performRepositoryAction(action) }
                    })
            }
        }

    }

    private var header: some View {
        HStack(spacing: DSSpacing.chip) {
            Image(systemName: "arrow.branch").accessibilityHidden(true)
            Text(verbatim: model.branchLabel).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(HoverableIconButtonStyle()).frame(width: DSSpacing.xl, height: DSSpacing.xl)
                .disabled(model.isRefreshing || model.isWorkflowBusy)
                .help(Text("更新", bundle: bundle)).accessibilityLabel(Text("変更を更新", bundle: bundle))
                .accessibilityIdentifier("git-inspector-refresh")
        }
        .font(DSFont.monoCaption).foregroundStyle(DSColor.textPrimary)
        .padding(.horizontal, DSSpacing.m).padding(.vertical, DSSpacing.xs)
    }

    private var sectionHeader: some View {
        HStack(spacing: DSSpacing.chip) {
            Button { changesExpanded.toggle() } label: {
                HStack(spacing: DSSpacing.chip) {
                    Image(systemName: changesExpanded ? "chevron.down" : "chevron.right")
                    Text("変更", bundle: bundle).font(DSFont.auxiliary.weight(.semibold))
                    Text(verbatim: "\(model.stagedChanges.count + model.unstagedChanges.count + model.conflictedPaths.count)").foregroundStyle(DSColor.textSecondary)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .focusable().focused($focusedArea, equals: .header).focusEffectDisabled()
                .accessibilityLabel(Text(changesExpanded ? "変更を折りたたむ" : "変更を展開", bundle: bundle))
                .accessibilityValue(Text(changesExpanded ? "展開中" : "折りたたみ中", bundle: bundle))
                .accessibilityIdentifier("git-section-changes-toggle")
            Button { Task { await model.stageAll() } } label: { Image(systemName: "plus") }
                .buttonStyle(HoverableIconButtonStyle()).frame(width: DSSpacing.xl, height: DSSpacing.xl)
                .disabled(model.unstagedChanges.isEmpty || model.isWorkflowBusy)
                .help(Text("すべてステージ", bundle: bundle)).accessibilityLabel(Text("すべてステージ", bundle: bundle))
                .accessibilityIdentifier("git-stage-all")
        }.font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.m).frame(height: DSLayout.gitRowHeight)
            .background(DSColor.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth) }
    }

    @ViewBuilder private var sectionContent: some View {
        if model.listState == .noProject { message("プロジェクトが選択されていません") }
        else if model.listState == .notARepository { message("Git 管理外のフォルダです") }
        else if let error = model.listErrorMessage {
            Text(verbatim: error).font(DSFont.meta).foregroundStyle(DSColor.attentionInk(.error)).padding(DSSpacing.m)
            Button { Task { await model.refresh() } } label: { Text("再試行", bundle: bundle) }
                .accessibilityLabel(Text("再試行", bundle: bundle)).accessibilityIdentifier("git-inspector-retry")
        } else if model.isRefreshing && model.changes.isEmpty {
            ProgressView().controlSize(.small).padding(DSSpacing.m)
        } else {
            if !model.conflictedPaths.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("競合", bundle: bundle).font(DSFont.auxiliary.weight(.semibold))
                    Text("競合をターミナルなどで解消してください", bundle: bundle).font(DSFont.meta)
                    ForEach(model.conflictedPaths, id: \.self) { path in
                        Text(verbatim: path).font(DSFont.monoCaption)
                            .accessibilityLabel(Text("競合", bundle: bundle) + Text(verbatim: ", " + path))
                            .accessibilityIdentifier("git-conflict-\(path)")
                    }
                }.foregroundStyle(DSColor.attentionInk(.error)).padding(DSSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            group(.staged); group(.worktree)
        }
    }

    private func changes(_ source: WorkingTreeSource) -> [WorkingTreeChange] {
        source == .staged ? model.stagedChanges : model.unstagedChanges
    }
    private func group(_ source: WorkingTreeSource) -> some View {
        let rows = changes(source)
        return VStack(spacing: 0) {
            HStack(spacing: DSSpacing.chip) {
                Text(source == .staged ? "ステージ済み" : "変更", bundle: bundle)
                Text(verbatim: "\(rows.count)").foregroundStyle(DSColor.textTertiary)
                Spacer(minLength: 0)
                Button { Task { if source == .staged { await model.unstageAll() } else { await model.stageAll() } } } label: {
                    Text(source == .staged ? "すべて外す" : "すべてステージ", bundle: bundle)
                }.buttonStyle(.plain).disabled(rows.isEmpty || model.isWorkflowBusy)
                    .accessibilityLabel(Text(source == .staged ? "すべて外す" : "すべてステージ", bundle: bundle))
                    .accessibilityIdentifier(source == .staged ? "git-unstage-all" : "git-changes-stage-all")
            }.font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.m).frame(height: DSLayout.gitRowHeight)
            if rows.isEmpty { message(source == .staged ? "ステージ済みの変更はありません" : "変更はありません") }
            ForEach(rows, id: \.path) { change in
                changeRow(change, source: source).id(rowID(.init(path: change.path, source: source)))
            }
        }
    }
    private func message(_ key: LocalizedStringKey) -> some View {
        Text(key, bundle: bundle).font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
            .padding(DSSpacing.m).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rowID(_ item: GitChangeSelection) -> String { "\(item.source)-\(item.path)" }

    private func changeRow(_ change: WorkingTreeChange, source: WorkingTreeSource) -> some View {
        let item = GitChangeSelection(path: change.path, source: source)
        let isSelected = model.activeGitRow == .change(item)
        let showAction = hovered == item || snapshotHoveredSelection == item || isSelected
        let counts = source == .staged ? model.stagedLineCounts[change.path] : model.unstagedLineCounts[change.path]
        let action: LocalizedStringKey = source == .staged ? "ステージを外す" : "ステージ"
        return HStack(spacing: DSSpacing.chip) {
            Text(verbatim: GitTabPolicy.letter(change.kind)).font(DSFont.monoCaption.weight(.bold))
                .foregroundStyle(editorChangeColor(for: change)).frame(width: DSLayout.gitKindSize)
            Text(verbatim: (change.path as NSString).lastPathComponent).font(DSFont.row)
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Text(verbatim: (change.path as NSString).deletingLastPathComponent)
                .font(DSFont.meta).foregroundStyle(DSColor.textSecondary).lineLimit(1).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showAction {
                Button { toggleStage(item) } label: { Image(systemName: source == .staged ? "minus" : "plus") }
                    .buttonStyle(.bordered).controlSize(.mini).frame(width: DSSpacing.xl, height: DSSpacing.xl)
                    .focusable(false)
                    .disabled(model.isWorkflowBusy)
                    .help(Text(action, bundle: bundle)).accessibilityLabel(Text(action, bundle: bundle))
                    .accessibilityIdentifier("git-\(source == .staged ? "unstage" : "stage")-\(change.path)")
            } else if let counts {
                if counts.added > 0 { Text(verbatim: "+\(counts.added)").foregroundStyle(DSColor.diffAdded).fixedSize() }
                if counts.deleted > 0 { Text(verbatim: "−\(counts.deleted)").foregroundStyle(DSColor.diffRemoved).fixedSize() }
            }
        }.font(DSFont.monoCaption).foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.s).frame(height: DSLayout.gitRowHeight)
            .background(isSelected ? DSColor.fillSelected : (hovered == item || snapshotHoveredSelection == item ? DSColor.fillSubtle : DSColor.clear), in: RoundedRectangle(cornerRadius: DSRadius.row))
            .contentShape(Rectangle()).onHover { hovered = $0 ? item : nil }
            .onTapGesture {
                model.markGitPathSeen(change.path); focusedArea = .list
                openChanges(change.path, source, false)
            }
            .contextMenu { rowActions(change, source: source) }
            .popover(isPresented: Binding(get: { rowMenu == item && changesExpanded },
                                          set: { if !$0 { rowMenu = nil } })) {
                VStack(alignment: .leading, spacing: DSSpacing.s) { rowActions(change, source: source) }
                    .buttonStyle(.plain).padding(DSSpacing.m)
                    .accessibilityLabel(Text("行のメニュー", bundle: bundle))
                    .accessibilityIdentifier("git-row-menu")
            }
            .help(Text(verbatim: change.path))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: rowLabel(change, source: source)))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: Text(action, bundle: bundle)) { toggleStage(item) }
            .accessibilityAction(named: Text("『変更』タブで開く", bundle: bundle)) { openChanges(change.path, source, false) }
            .accessibilityIdentifier("git-change-\(source)-\(change.path)")
    }

    @ViewBuilder private func rowActions(_ change: WorkingTreeChange, source: WorkingTreeSource) -> some View {
        let item = GitChangeSelection(path: change.path, source: source)
        let action: LocalizedStringKey = source == .staged ? "ステージを外す" : "ステージ"

        Button { toggleStage(item) } label: { Text(action, bundle: bundle) }
            .disabled(model.isWorkflowBusy)
            .accessibilityLabel(Text(action, bundle: bundle))
            .accessibilityIdentifier("git-row-toggle-stage")
        Button { rowMenu = nil; openChanges(change.path, source, false) } label: { Text("『変更』タブで開く", bundle: bundle) }
            .accessibilityIdentifier("git-row-changes")
        Button { rowMenu = nil; openFile(change.path) } label: { Text("ファイルを開く", bundle: bundle) }
            .disabled(change.kind == .deleted).accessibilityIdentifier("git-row-file")
        Divider()
        Button {
            if let file = fileURL(change.path) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        } label: { Text("Finder で表示", bundle: bundle) }
            .accessibilityIdentifier("git-row-finder")
        Button {
            if let file = fileURL(change.path) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        } label: { Text("パスをコピー", bundle: bundle) }
            .accessibilityIdentifier("git-row-copy-path")
    }

    private func fileURL(_ path: String) -> URL? {
        let root = model.changeScope.repositoryRoot ?? workingDirectory
        return try? WorkingTreeService.relativeURL(for: path, relativeTo: URL(fileURLWithPath: root))
    }

    private func rowLabel(_ change: WorkingTreeChange, source: WorkingTreeSource) -> String {
        var label = localized(GitTabPolicy.kindKey(change.kind)) + ", " + change.path
        if change.isBinary { label += ", " + localized("バイナリファイル") }
        let count = source == .staged ? model.stagedLineCounts[change.path] : model.unstagedLineCounts[change.path]
        if let count {
            label += ", " + String(format: localized("%lld 行追加、%lld 行削除"), count.added, count.deleted)
        }
        if model.freshPaths.contains(change.path) { label += ", " + localized("新しく出た") }
        return label
    }
    private func toggleStage(_ item: GitChangeSelection) {
        guard changesExpanded, !model.isWorkflowBusy else { return }
        rowMenu = nil
        Task {
            if item.source == .staged { await model.unstage(paths: [item.path]) }
            else { await model.stage(paths: [item.path]) }
            focusedArea = changesExpanded ? .list : .header
        }
    }

    private func move(_ offset: Int) {
        let rows = visibleRows
        guard !rows.isEmpty else { return }
        focusedArea = .list
        let index = model.activeGitRow.flatMap { rows.firstIndex(of: $0) } ?? (offset > 0 ? -1 : rows.count)
        let next = rows[min(max(index + offset, 0), rows.count - 1)]
        Task {
            if case .change(let item) = next { await model.select(item.path, source: item.source) }
            model.activeGitRow = next
        }
    }
}
