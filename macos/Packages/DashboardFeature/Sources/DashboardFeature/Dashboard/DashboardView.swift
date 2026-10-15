import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

public struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var usageMonitor: UsageMonitor
    @Bindable var newChatDraftStore: NewChatDraftStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.localizationBundle) private var localizationBundle

    @State private var sidebarWidth: CGFloat = DSLayout.sidebarWidth.ideal
    @State private var sidebarWidthAtDragStart: CGFloat = DSLayout.sidebarWidth.ideal
    @State private var inspectorWidth: CGFloat = DSLayout.inspectorWidth.ideal
    @State private var inspectorWidthAtDragStart: CGFloat = DSLayout.inspectorWidth.ideal
    /// 01 E6: 幅はウィンドウごとに保存する。開閉は全ウィンドウで共有の `AppRouter` が持つため、ここでは保存しない。
    @SceneStorage("pane.sidebarWidth") private var savedSidebarWidth = Double(DSLayout.sidebarWidth.ideal)
    @SceneStorage("pane.inspectorWidth") private var savedInspectorWidth = Double(DSLayout.inspectorWidth.ideal)
    @Environment(\.locale) private var locale

    @State private var spawnError: SpawnError?
    @State private var discardedSessionCountNotice: Int?
    @State private var pendingDeletion: SelectedSessionNode?
    @State private var pendingWorkspaceChange: SessionViewModel?
    @State private var pendingProjectDeletion: Project?
    /// 移動・割り当ての再起動確認（03 F9）。
    @State private var pendingMove: PendingSessionMove?
    /// フォルダを選んだ後の再起動確認（03 F9。選んだ行き先を示してから再起動する）。
    @State private var pendingFolderChange: PendingFolderChange?
    /// メニューバーの「名前を変更…」をサイドバーの行の中の編集へ渡す。
    @State private var sidebarRenameRequest: SessionID?
    @State private var expandedProjectIDs: Set<ProjectID> = []
    @State private var sessionTreeViewModel = SessionTreeViewModel()

    @AppStorage(ThemeStore.themeKey, store: UserDefaults.phloxDefaults()) private var themeID = AppTheme.phlox.id
    /// 設定画面で変えたターミナルの文字サイズを、開いているセッションの端末にも当てる。
    @AppStorage(TerminalFontSettings.fontSizeKey) private var terminalFontSize = Double(NSFont.systemFontSize)
    @State private var gridSessionPickerPresented = false
    @State private var editorPanel = EditorPanelCoordinator()
    @State private var bottomPanel: BottomPanelState
    @State private var fileTabs = FileTabDocuments()
    @State private var fileTreeModels: [String: FileTreeModel] = [:]
    /// 閉じる前に確認が要る子タブ（動いているシェル・未保存のファイル）。
    @State private var pendingChildClose: PendingChildClose?

    /// Claude Code 管理ウィンドウの識別子。App 側が Window シーンを持つときだけ渡す。
    private let agentConsoleWindowID: String?
    /// プロジェクトごとのターミナルタブ。App が寿命を持つ。
    private let sessionTerminals: ProjectTerminalStore?
    private let simulatorHub: SimulatorHub?
    private let initialSidebarWidth: CGFloat?

    public init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        usageMonitor: UsageMonitor,
        newChatDraftStore: NewChatDraftStore = NewChatDraftStore(),
        agentConsoleWindowID: String? = nil,
        sessionTerminals: ProjectTerminalStore? = nil,
        simulatorHub: SimulatorHub? = nil,
        initialSidebarWidth: CGFloat? = nil,
        initiallyExpandedProjectIDs: Set<ProjectID> = [],
        bottomPanel: BottomPanelState? = nil
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _router = Bindable(wrappedValue: router)
        _usageMonitor = Bindable(wrappedValue: usageMonitor)
        _newChatDraftStore = Bindable(wrappedValue: newChatDraftStore)
        self.agentConsoleWindowID = agentConsoleWindowID
        self.sessionTerminals = sessionTerminals
        _bottomPanel = State(initialValue: bottomPanel ?? BottomPanelState())
        self.simulatorHub = simulatorHub
        self.initialSidebarWidth = initialSidebarWidth
        _expandedProjectIDs = State(initialValue: initiallyExpandedProjectIDs)
    }

    private func deletionDialogTitle(for selection: SelectedSessionNode) -> String {
        SessionDeletionDialogText.title(
            sessionName: selection.node.displayName,
            childCount: viewModel.descendantCount(of: selection.id),
            locale: locale
        )
    }

    /// 巻き込まれる子セッション（名前と状態）。
    private func deletionDialogRows(for id: SessionID) -> [DSDialogList.Row] {
        SessionDeletionDialogText.rows(
            children: viewModel.descendantNodes(of: id).map {
                (name: $0.displayName, meta: $0.gridDisplayState.localizedLabel(locale: locale))
            },
            locale: locale
        )
    }

    /// 保存していないファイルタブ（子の分も）。
    private func deletionDirtyFiles(for id: SessionID) -> [String] {
        []
    }

    private func affectedSessionIDs(for id: SessionID) -> Set<SessionID> {
        Set([id] + viewModel.descendantNodes(of: id).map(\.id))
    }

    private func projectDirtySummary(for projectID: ProjectID) -> String {
        return FileTabDocumentRegistry.shared.dirtySummary(for: [projectID])
    }

    private func projectDeletionDialogMessage(for project: Project) -> String {
        // 削除と同じ範囲（サイドバーに出ない内部セッションも含む）で数える。
        let nodes = viewModel.gridSessionNodes(in: project.id)
        return ProjectDeletionDialogText.message(
            sessionCount: nodes.count,
            childCount: nodes.filter { $0.controllable.parentSessionID != nil }.count,
            otherProjectChildCount: viewModel.projectDeletionDescendantCount(of: project.id),
            locale: locale
        )
    }

    private var windowContent: some View {
        shellWithTabDialogs
            .toolbar { DashboardToolbar(viewModel: viewModel, router: router, changeCount: editorPanel.viewModel.changes.count, bottomPanel: bottomPanel) }
            .focusedSceneValue(\.bottomPanelState, bottomPanel)
            .focusedSceneValue(\.gitWorkflowModel,
                router.inspectorVisible && router.inspectorTab == .git && router.selectedProjectID != nil
                    ? editorPanel.viewModel : nil)
    }

    public var body: some View {
        windowContent
            .toolbarBackground(DSColor.toolbarBackground, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .environment(\.adjustTerminalFontSize) { [viewModel] delta in
                viewModel.adjustFontSize(by: delta, target: .terminal)
            }
            .onChange(of: themeID) { _, _ in
                viewModel.reapplyTheme()
            }
            .onChange(of: terminalFontSize) { _, size in
                viewModel.applyTerminalFontSize(TerminalFontSettings.adjusted(from: CGFloat(size), by: 0))
            }
            .onChange(of: router.viewMode, initial: true) { _, mode in
                viewModel.setTerminalGridLayout(mode == .grid)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if let count = discardedSessionCountNotice {
                        discardedSessionsToast(count: count)
                    }
                    if let path = viewModel.worktreeCreationPath {
                        worktreeProgressToast(path: path)
                    }
                }
            }
            .dsDialog(item: $spawnError) { err in
                // 09 D1: 原因の文はそのまま等幅で。実行ファイルが無いときだけ次の手を 2 つ目のボタンに置く。
                DSDialog(
                    .notice,
                    title: SpawnFailureDialogText.title(agentName: err.agentName, locale: locale),
                    buttons: spawnErrorButtons(err),
                    onCancel: { spawnError = nil }
                ) {
                    DSDialogLog(err.message)
                }
            }
            .dsDialog(isPresented: workspaceCleanupWarningBinding) {
                if let warning = viewModel.workspaceCleanupWarning {
                    DSDialog(
                        .notice,
                        title: CleanupWarningDialogText.title(warning, locale: locale),
                        message: CleanupWarningDialogText.message(warning, locale: locale),
                        buttons: cleanupWarningButtons(warning),
                        onCancel: { viewModel.clearWorkspaceCleanupWarning() }
                    ) {
                        DSDialogLog(CleanupWarningDialogText.detail(warning, reason: viewModel.workspaceCleanupFailureReason))
                    }
                }
            }
            .dsDialog(item: $pendingDeletion) { selection in
                let rows = deletionDialogRows(for: selection.id)
                DSDialog(
                    .irreversible,
                    title: deletionDialogTitle(for: selection),
                    message: SessionDeletionDialogText.message(locale: locale),
                    note: SessionDeletionDialogText.note(dirtyFiles: deletionDirtyFiles(for: selection.id), locale: locale),
                    buttons: [
                        DSDialogButton("削除", role: .destructive) {
                            let id = selection.id
                            if router.selectedSession == id {
                                router.selectedSession = nil
                            }
                            pendingDeletion = nil
                            Task { await viewModel.removeSession(id) }
                        },
                        DSDialogButton("キャンセル", role: .primary) { pendingDeletion = nil },
                    ],
                    onCancel: { pendingDeletion = nil }
                ) {
                    if !rows.isEmpty {
                        DSDialogList(rows: rows)
                    }
                }
            }
            .dsDialog(item: $pendingProjectDeletion) { project in
                DSDialog(
                    .irreversible,
                    title: ProjectDeletionDialogText.title(projectName: project.name, locale: locale),
                    message: projectDeletionDialogMessage(for: project),
                    note: [ProjectDeletionDialogText.note(folderPath: (project.directoryPath as NSString).abbreviatingWithTildeInPath, locale: locale), projectDirtySummary(for: project.id)]
                        .filter { !$0.isEmpty }.joined(separator: "\n"),
                    buttons: [
                        DSDialogButton("削除", role: .destructive) {
                            let projectID = project.id
                            pendingProjectDeletion = nil
                            expandedProjectIDs.remove(projectID)
                            if let selected = router.selectedSession,
                               viewModel.gridSessionNodes(in: projectID).contains(where: { $0.id == selected }) {
                                router.selectedSession = nil
                            }
                            Task {
                                await router.forgetProject(projectID, terminals: sessionTerminals, simulatorHub: simulatorHub)
                                await viewModel.removeProject(projectID)
                            }
                        },
                        DSDialogButton("キャンセル", role: .primary) { pendingProjectDeletion = nil },
                    ],
                    onCancel: { pendingProjectDeletion = nil }
                )
            }
            .onChange(of: pendingWorkspaceChange?.id) { _, id in
                guard id != nil, let session = pendingWorkspaceChange else { return }
                pendingWorkspaceChange = nil
                chooseWorkspace(for: session)
            }
    }

    private func spawnErrorButtons(_ err: SpawnError) -> [DSDialogButton] {
        var buttons: [DSDialogButton] = []
        if err.opensAgentConsole, let agentConsoleWindowID {
            buttons.append(DSDialogButton("エージェント管理を開く") {
                spawnError = nil
                openWindow(id: agentConsoleWindowID)
            })
        }
        buttons.append(DSDialogButton("OK", role: .primary) { spawnError = nil })
        return buttons
    }

    private func cleanupWarningButtons(_ warning: WorkspaceCleanupWarning) -> [DSDialogButton] {
        var buttons: [DSDialogButton] = []
        if let path = CleanupWarningDialogText.revealPath(warning) {
            buttons.append(DSDialogButton("Finder で表示") {
                viewModel.clearWorkspaceCleanupWarning()
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }
        buttons.append(DSDialogButton("OK", role: .primary) { viewModel.clearWorkspaceCleanupWarning() })
        return buttons
    }

    /// 名前の変更はどの入口からもサイドバーの行の中で行う（09 D6）。サイドバーを隠していれば出してから。
    private func beginSessionRename(_ id: SessionID) {
        if !sidebarShown { router.toggleSidebar() }
        sidebarRenameRequest = id
    }

    /// 子タブを閉じる前の確認（動いているシェル・未保存のファイル）。本体の修飾子の連なりを短くするため分ける。
    private var shellWithTabDialogs: some View {
        navigationShell
            .dsDialog(item: $pendingChildClose) { pending in
                DSDialog(
                    .irreversible,
                    title: pending.title,
                    message: pending.message,
                    buttons: [
                        DSDialogButton("閉じる", role: .destructive) {
                            pendingChildClose = nil
                            closeChildTab(pending.tab, of: pending.projectID)
                        },
                        DSDialogButton("キャンセル", role: .primary) { pendingChildClose = nil },
                    ],
                    onCancel: { pendingChildClose = nil }
                )
            }
            .dsDialog(item: $pendingFolderChange) { change in
                DSDialog(
                    .irreversible,
                    title: String(
                        format: AppLocalizedString.string("「%@」を %@ で再起動しますか?", locale: locale),
                        change.sessionTitle, (change.directory.path as NSString).abbreviatingWithTildeInPath
                    ),
                    message: AppLocalizedString.string("ターミナルの内容と進行中の作業は失われ、元に戻せません。", locale: locale),
                    note: "",
                    buttons: [
                        DSDialogButton("再起動", role: .destructive) {
                            pendingFolderChange = nil
                            Task { await changeWorkspace(change.sessionID, to: change.directory) }
                        },
                        DSDialogButton("キャンセル", role: .primary) { pendingFolderChange = nil },
                    ],
                    onCancel: { pendingFolderChange = nil }
                )
            }
            .dsDialog(item: $pendingMove) { move in
                let path = (move.project.directoryPath as NSString).abbreviatingWithTildeInPath
                DSDialog(
                    .irreversible,
                    title: String(format: AppLocalizedString.string("「%@」を %@ へ移動しますか?", locale: locale), move.sessionTitle, move.project.name),
                    message: String(format: AppLocalizedString.string("セッションは %@ で再起動されます。ターミナルの内容と進行中の作業は失われます。", locale: locale), path),
                    note: "",
                    buttons: [
                        DSDialogButton("移動して再起動", role: .destructive) {
                            pendingMove = nil
                            Task { await moveSessionToProject(move.sessionID, projectID: move.project.id) }
                        },
                        DSDialogButton("キャンセル", role: .primary) { pendingMove = nil },
                    ],
                    onCancel: { pendingMove = nil }
                )
            }
    }



    private var navigationShell: some View {
        GeometryReader { geometry in
            let windowWidth = geometry.size.width
            let layout = paneLayout(windowWidth: windowWidth)
            HStack(spacing: 0) {
                DSSidePane(edge: .leading, isOpen: layout.showsSidebar, width: layout.sidebar) {
                    sidebarColumn
                }

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // 表示範囲バーは中央の列の上端だけに置き、インスペクタの上には掛けない（06 PhloxGrid）。
                        VStack(spacing: 0) {
                            if router.viewMode == .grid, !viewModel.projects.isEmpty {
                                GridModeBar(
                                    viewModel: viewModel,
                                    router: router,
                                    sessionPickerPresented: $gridSessionPickerPresented
                                )
                                horizontalSeparator
                            }
                            centerContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(router.viewMode == .grid ? DSColor.gridAreaBackground : DSColor.windowBackground)
                        }

                        DSSidePane(edge: .trailing, isOpen: router.inspectorVisible && !layout.inspectorIsOverlay,
                                   width: layout.inspector, unloadsWhenClosed: true) {
                            inspectorContent
                                .background(DSColor.panelBackground)
                        }
                    }
                }
            }
            .dsPaneAnimation(value: router.inspectorVisible)
            // 幅が足りないときの重ね表示。SwiftUI の overlay は端末の NSView より前面に描ける。
            .overlay(alignment: .topTrailing) {
                if router.inspectorVisible, layout.inspectorIsOverlay {
                    inspectorContent(isOverlay: true)
                        .frame(width: layout.inspector)
                        .frame(maxHeight: .infinity)
                        .background(DSColor.popoverBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.attention))
                        .overlay {
                            RoundedRectangle(cornerRadius: DSRadius.attention).strokeBorder(DSColor.separator)
                        }
                        .shadow(color: DSShadow.popover.color, radius: DSShadow.popover.radius, y: DSShadow.popover.y)
                        .padding(.top, DSSpacing.s)
                        .padding(.bottom, DSSpacing.s)
                        .padding(.trailing, DSSpacing.s)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if !layout.showsSidebar, router.sidebarPeeking {
                    HStack(spacing: 0) {
                        sidebarColumn
                            .frame(width: layout.sidebar)
                        verticalSeparator
                    }
                    .shadow(color: DSShadow.popover.color, radius: DSShadow.popover.radius, y: DSShadow.popover.y)
                    .transition(.move(edge: .leading))
                }
            }
            .dsPaneAnimation(value: layout.showsSidebar)
            .dsPaneAnimation(value: router.sidebarPeeking)
            // リサイズ用の掴みしろもオーバーレイにする。HStack 内の区切り線へ overlay で
            // 当たり判定を広げる方式だと、ターミナル(AppKit NSView)側に張り出した分が
            // NSView に遮られてホバー・ドラッグを受け取れないため、最前面のオーバーレイとして
            // 区切り線の真上に重ねる。
            .overlay(alignment: .topLeading) {
                if layout.showsSidebar {
                    ResizeGripView(
                        onChanged: { translation in
                            sidebarWidth = PaneWidthPolicy.draggedSidebarWidth(
                                start: sidebarWidthAtDragStart,
                                translation: translation,
                                windowWidth: windowWidth,
                                inspectorSpan: inspectorSpan(layout)
                            )
                        },
                        onEnded: { sidebarWidthAtDragStart = sidebarWidth },
                        onDoubleClick: {
                            sidebarWidth = DSLayout.sidebarWidth.ideal
                            sidebarWidthAtDragStart = sidebarWidth
                        }
                    )
                    .offset(x: layout.sidebar + 0.5 - ResizeGripView.gripWidth / 2)
                    .onAppear { sidebarWidthAtDragStart = layout.sidebar }
                }
            }
            .overlay(alignment: .topTrailing) {
                if router.inspectorVisible, !layout.inspectorIsOverlay {
                    ResizeGripView(
                        onChanged: { translation in
                            inspectorWidth = PaneWidthPolicy.draggedInspectorWidth(
                                start: inspectorWidthAtDragStart,
                                translation: translation,
                                windowWidth: windowWidth,
                                sidebarSpan: layout.showsSidebar ? layout.sidebar + PaneWidthPolicy.separatorWidth : 0
                            )
                        },
                        onEnded: { inspectorWidthAtDragStart = inspectorWidth },
                        onDoubleClick: {
                            inspectorWidth = DSLayout.inspectorWidth.ideal
                            inspectorWidthAtDragStart = inspectorWidth
                        }
                    )
                    .offset(x: -(layout.inspector + 0.5 - ResizeGripView.gripWidth / 2))
                    .onAppear { inspectorWidthAtDragStart = layout.inspector }
                }
            }
            .onAppear {
                sidebarWidth = initialSidebarWidth ?? CGFloat(savedSidebarWidth)
                sidebarWidthAtDragStart = sidebarWidth
                inspectorWidth = CGFloat(savedInspectorWidth)
                inspectorWidthAtDragStart = inspectorWidth
            }
            .onChange(of: sidebarWidth) { _, width in savedSidebarWidth = Double(width) }
            .onChange(of: inspectorWidth) { _, width in savedInspectorWidth = Double(width) }
            .onChange(of: sidebarLacksRoom(windowWidth: windowWidth), initial: true) { _, lacksRoom in
                router.sidebarLacksRoom = lacksRoom
                if !lacksRoom {
                    router.sidebarPeeking = false
                }
            }
            // Git タブと共有する一覧を、変更タブを開いていなくても読む。
            .task(id: editorPanel.target) {
                await editorPanel.resolve(workspaces: editorPanelWorkspaces)
            }
        }
        .background(WindowChromeConfigurator(files: fileTabs, router: router, fileContext: { [weak viewModel] id in
            return UnsavedFileContext(project: viewModel?.projects.first { $0.id == id }?.name ?? "")
        }, projectName: { [weak viewModel, weak router] in
            guard let viewModel, let router else { return "" }
            return viewModel.projects.first { $0.id == router.selectedProjectID }?.name ?? ""
        }))
        .onReceive(NotificationCenter.default.publisher(for: .fileTreeFileSaved)) { notification in
            guard let root = notification.userInfo?["root"] as? String,
                  let path = notification.userInfo?["path"] as? String else { return }
            Task { if let model = fileTreeModels[root] { await model.fileSaved(root: root, relativePath: path) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshGit(for: .foreground)
        }
        .onChange(of: projectTurnCompletions) { old, new in
            let model = editorPanel.viewModel
            Task {
                await GitTabPolicy.refreshAfterTurnCompletions(old: old, new: new, model: model)
            }
        }
        .onAppear {
            migrateProjectTabs()
            revealSelectedSessionTab()
            updateEditorPanel()
        }
        // 子タブを切り替えたら、隠れた区画（端末など）にキー入力が残らないようにする。
        .onChange(of: router.selectedProjectID.flatMap { router.tabs.layout(for: $0).selected }) { _, _ in
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onChange(of: router.tabRequest) { _, request in
            guard let request, router.tabRequest == request,
                  FileTabDocumentRegistry.shared.ownsKeyWindow(fileTabs) else { return }
            router.tabRequest = nil
            handle(request)
        }
        .onChange(of: router.sidebarRequest) { _, request in
            guard let request, router.sidebarRequest == request,
                  FileTabDocumentRegistry.shared.ownsKeyWindow(fileTabs) else { return }
            router.sidebarRequest = nil
            handle(request)
        }
        .onChange(of: projectChats) { old, new in
            forgetRemovedSessions(old: old, new: new)
        }
        .onChange(of: viewModel.projects.map(\.id)) { old, new in
            for id in old where !new.contains(id) {
                Task { await router.forgetProject(id, terminals: sessionTerminals, simulatorHub: simulatorHub) }
            }
        }
        .onChange(of: router.selectedProjectID) { _, _ in
            ensureProjectSelection()
            updateEditorPanel()
        }
        // 画面が無いあいだに押された ⌘O も、表示された時点で受ける。
        .onChange(of: router.addProjectRequested, initial: true) { _, requested in
            guard requested else { return }
            router.addProjectRequested = false
            chooseProjectDirectory()
        }
        .onChange(of: router.viewMode, initial: true) { _, newMode in
            if newMode != .grid {
                router.clearGridFilter()
            }
            viewModel.gridSessionFilterProjectID = newMode == .grid ? router.gridFilterProjectID : nil
            // 動きは dsPaneAnimation で付く（動きを減らす設定も見る）。
            router.sidebarVisible = SidebarVisibilityPolicy.visibility(
                afterSwitchingTo: newMode,
                currentVisible: router.sidebarVisible,
                hasGridFilter: router.gridFilterProjectID != nil
            )
        }
        .onChange(of: router.gridFilterProjectID) { _, newValue in
            viewModel.gridSessionFilterProjectID = router.viewMode == .grid ? newValue : nil
            viewModel.normalizeGridSessionSelectionForFilterChange()
        }
        .onChange(of: viewModel.restoredSessionPresentation, initial: true) { _, presentation in
            if presentation != nil { migrateProjectTabs() }
            applyRestoredSessionPresentation(presentation)
        }
        .onChange(of: viewModel.discardedSessionCountNotice, initial: true) { _, _ in
            discardedSessionCountNotice = viewModel.takeDiscardedSessionCountNotice()
        }
        .onChange(of: router.selectedSession) { _, selectedID in
            markCompletionSeen(for: selectedID)
            updateEditorPanel()
            revealSelectedSessionTab()
            if let selectedID,
               let session = viewModel.sessionNode(id: selectedID),
               let projectID = session.projectID {
                expandedProjectIDs.insert(projectID)
            }
        }
        .onChange(of: editorPanelWorkspaces) { _, _ in
            updateEditorPanel()
        }
        .onChange(of: viewModel.unseenCompletionCount) { _, _ in
            markCompletionSeen(for: router.selectedSession)
        }
        // 既定の間隔（システムの値）を空けると、サイドバーと下端のバーの間に隙間ができる。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UsageBottomBarView(monitor: usageMonitor)
        }
    }

    private var gridScopeSummary: GridScopeSummary {
        GridScopeSummary.make(
            projects: viewModel.projects,
            filterProjectID: viewModel.gridSessionFilterProjectID,
            visibleCount: viewModel.filteredGridSessionNodes(projectID: viewModel.gridSessionFilterProjectID).count,
            hasSessionSelection: viewModel.gridSessionSelection != nil,
            locale: locale
        )
    }

    @ViewBuilder
    /// 表示するセッションが 0 件（06 S10）。
    private var gridScopeEmptyState: some View {
        let summary = gridScopeSummary
        let projectID = viewModel.gridSessionFilterProjectID
        VStack(spacing: 10) {
            Text("表示するセッションがありません")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
            if let emptyMessage = summary.emptyMessage {
                Text(verbatim: emptyMessage)
                    .font(DSFont.dense)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: 8) {
                if !summary.clearActions.isEmpty {
                    Button {
                        router.clearGridFilter()
                        viewModel.clearGridSessionSelection()
                    } label: {
                        Text("絞り込みを解除")
                            .font(DSFont.dense)
                            .foregroundStyle(DSColor.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DSColor.controlBorder, lineWidth: 0.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    NewChatEntryActions(router: router, dashboard: viewModel).gridEmptyState(projectID: projectID)
                } label: {
                    HStack(spacing: 6) {
                        Text("新規チャット", bundle: localizationBundle)
                    }
                    .font(DSFont.dense.weight(.semibold))
                    .foregroundStyle(DSColor.accentOnFill)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Columns

    /// 左列。下端に設定とエージェント管理。
    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            DashboardSidebarView(
                viewModel: viewModel,
                router: router,
                expandedProjectIDs: $expandedProjectIDs,
                pendingProjectDeletion: $pendingProjectDeletion,
                pendingDeletion: $pendingDeletion,
                pendingWorkspaceChange: $pendingWorkspaceChange,
                pendingMove: $pendingMove,
                renameRequest: $sidebarRenameRequest,
                sessionTreeViewModel: $sessionTreeViewModel,
                onChooseProjectDirectory: chooseProjectDirectory
            )
            sidebarFooter
        }
        .background(DSColor.sidebarBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("サイドバー"))
    }

    /// 下端の操作列: 新規チャット・エージェント管理・設定。
    private var sidebarFooter: some View {
        HStack(spacing: 2) {
            Button {
                NewChatEntryActions(router: router, dashboard: viewModel).sidebarFooter()
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: "＋")
                        .font(DSFont.row)
                    Text("新規チャット", bundle: localizationBundle)
                        .font(DSFont.auxiliary.weight(.medium))
                    Spacer(minLength: 0)
                    Text(verbatim: "⌘N")
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textTertiary)
                }
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help(Text("新規チャット", bundle: localizationBundle) + Text(verbatim: "（⌘N）"))
            .accessibilityLabel(Text("新規チャット", bundle: localizationBundle) + Text(verbatim: "（⌘N）"))
            if let agentConsoleWindowID {
                footerIconButton(systemImage: "slider.horizontal.3", label: "エージェント管理（⇧⌘,）") {
                    openWindow(id: agentConsoleWindowID)
                }
            }
            footerIconButton(systemImage: "gearshape", label: "設定（⌘,）") {
                openSettings()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .overlay(alignment: .top) { horizontalSeparator }
    }

    private func footerIconButton(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private var centerContent: some View {
        SessionTabsContainer(
            viewModel: viewModel,
            router: router,
            terminals: sessionTerminals,
            simulatorHub: simulatorHub,
            editorPanel: editorPanel,
            files: fileTabs,
            bottomPanel: bottomPanel
        ) { tab in
            if router.viewMode == .grid, !viewModel.projects.isEmpty, gridScopeSummary.isEmpty {
                gridScopeEmptyState
            } else {
                detailView(displayTab: tab)
            }
        }
    }


    private var detailView: some View { detailView(displayTab: nil) }

    private func detailView(displayTab: ProjectTab?) -> some View {
        DashboardDetailView(
                viewModel: viewModel,
                router: router,
                newChatDraftStore: newChatDraftStore,
                pendingDeletion: $pendingDeletion,
                onRenameSession: beginSessionRename,
                pendingWorkspaceChange: $pendingWorkspaceChange,
                onNewChatLaunchFailure: { ref, error in
                    let raw = error.localizedDescription
                    spawnError = SpawnError(
                        agentName: SpawnFailureDialogText.agentName(for: ref),
                        message: raw.isEmpty ? String(describing: error) : raw,
                        opensAgentConsole: SpawnFailureDialogText.opensAgentConsole(for: error)
                    )
                },
                displayTab: displayTab
            )
    }

    private var inspectorContent: some View {
        inspectorContent(isOverlay: false)
    }

    private func inspectorContent(isOverlay: Bool) -> some View {
        InspectorView(
            router: router,
            project: viewModel.projects.first { $0.id == router.selectedProjectID },
            fileTreeModels: $fileTreeModels,
            files: fileTabs,
            editorPanel: editorPanel,
            runningSessionNames: GitTabPolicy.runningSessionNames(sessions: viewModel.sessionNodes,
                project: viewModel.projects.first { $0.id == router.selectedProjectID }),
            isOverlay: isOverlay
        )
    }

    private var projectTurnCompletions: [SessionID: Date] {
        GitTabPolicy.turnCompletions(sessions: viewModel.sessionNodes, projectID: router.selectedProjectID)
    }

    private func refreshGit(for event: GitTabPolicy.RefreshEvent) {
        guard GitTabPolicy.shouldRefresh(event, projectRoot: editorPanel.target.workingDirectory) else { return }
        let model = editorPanel.viewModel
        Task { await model.refresh() }
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(DSColor.separator)
            .frame(width: PaneWidthPolicy.separatorWidth)
    }

    private var horizontalSeparator: some View {
        Rectangle()
            .fill(DSColor.separator)
            .frame(height: 1)
    }

    // MARK: - Widths

    private func paneLayout(windowWidth: CGFloat) -> PaneLayout {
        PaneWidthPolicy.resolve(
            windowWidth: windowWidth,
            sidebarVisible: router.sidebarVisible,
            inspectorVisible: router.inspectorVisible,
            sidebarWidth: sidebarWidth,
            inspectorWidth: inspectorWidth
        )
    }

    /// 開いているかに関係なく、サイドバーを横に並べる幅が無いか。
    private func sidebarLacksRoom(windowWidth: CGFloat) -> Bool {
        !PaneWidthPolicy.resolve(
            windowWidth: windowWidth,
            sidebarVisible: true,
            inspectorVisible: router.inspectorVisible,
            sidebarWidth: sidebarWidth,
            inspectorWidth: inspectorWidth
        ).showsSidebar
    }

    private func inspectorSpan(_ layout: PaneLayout) -> CGFloat {
        router.inspectorVisible && !layout.inspectorIsOverlay ? layout.inspector + PaneWidthPolicy.separatorWidth : 0
    }

    private func updateEditorPanel() {
        editorPanel.update(
            project: viewModel.projects.first { $0.id == router.selectedProjectID },
            workspaces: editorPanelWorkspaces
        )
    }

    private var editorPanelWorkspaces: [SessionWorkspace] {
        viewModel.workspaceSessionWorkspaces
    }

    private var sidebarShown: Bool {
        router.sidebarVisible && (!router.sidebarLacksRoom || router.sidebarPeeking)
    }

    /// worktree を作っている間の案内（08 F2・S5）。画面から起動した作業ツリー自体のパスを出す。
    private func worktreeProgressToast(path: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("worktree を作成しています")
                .font(DSFont.dense)
                .foregroundStyle(DSColor.textPrimary)
            Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(DSColor.popoverBackground, in: Capsule())
        .dsShadow(DSShadow.popover)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private func discardedSessionsToast(count: Int) -> some View {
        HStack(spacing: 10) {
            Text("以前のカスタムエージェントのセッションを \(count) 件読み込まずに破棄しました。")
                .font(DSFont.dense)
                .foregroundStyle(DSColor.textPrimary)
            Button("閉じる") { discardedSessionCountNotice = nil }
                .buttonStyle(.plain)
                .font(DSFont.dense.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(DSColor.popoverBackground, in: Capsule())
        .dsShadow(DSShadow.popover)
        .padding(.bottom, 20)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Tabs

    private func migrateProjectTabs() {
        guard viewModel.restoredSessionPresentation != nil else { return }
        let sessionProjects = Dictionary(uniqueKeysWithValues: viewModel.sessionNodes.compactMap { node in
            node.projectID.map { (node.id, $0) }
        })
        router.tabs.migrateLegacy(sessionProjects: sessionProjects, projects: viewModel.projects)
    }

    private func ensureProjectSelection() {
        guard let id = router.selectedProjectID else { return }
        router.ensureProjectSelection(chatTabs: viewModel.chatTabs(in: id))
    }

    private func revealSelectedSessionTab() {
        guard let id = router.selectedSession, let projectID = viewModel.sessionNode(id: id)?.projectID else { return }
        router.selectTab(.chat(id), in: projectID)
    }

    private var projectChats: [ProjectID: [ProjectTab]] {
        Dictionary(uniqueKeysWithValues: viewModel.projects.map { ($0.id, viewModel.chatTabs(in: $0.id)) })
    }

    private func forgetRemovedSessions(old: [ProjectID: [ProjectTab]], new: [ProjectID: [ProjectTab]]) {
        for projectID in router.tabs.snapshot.projects.keys {
            router.tabs.updateLayout(for: projectID) {
                $0.reconcileChats(previous: old[projectID] ?? [], current: new[projectID] ?? [])
            }
        }
        ensureProjectSelection()
    }

    private func handle(_ request: TabRequest) {
        switch request {
        case .confirmSessionDeletion(let id):
            if let node = viewModel.sessionNode(id: id) { pendingDeletion = SelectedSessionNode(node) }
        case .confirmProjectDeletion(let id): pendingProjectDeletion = viewModel.projects.first { $0.id == id }
        case .closeChild(let id, let tab): requestChildClose(tab, of: id)
        case .openFile(let id): chooseFileToOpen(in: id)
        case .removeFromGrid(let id):
            if let next = viewModel.removeFromGrid(id) { router.selectedSession = next }
        }
    }

    private func requestChildClose(_ tab: ProjectTab, of projectID: ProjectID) {
        switch tab {
        case .chat(let id): handle(.confirmSessionDeletion(id))
        case .terminal(let id) where sessionTerminals?.isRunning(id) == true:
            Task {
                guard await sessionTerminals?.hasRunningCommand(id) == true else {
                    closeChildTab(tab, of: projectID)
                    return
                }
                pendingChildClose = PendingChildClose(
                    projectID: projectID, tab: tab,
                    title: AppLocalizedString.string("ターミナルを閉じますか?", locale: locale),
                    message: AppLocalizedString.string("シェルを終了します。実行中のコマンドも止まります。", locale: locale))
            }
        case .file(let path) where FileTabDocumentRegistry.shared.closeDecision(for: projectID, path: path) == .confirm:
            pendingChildClose = PendingChildClose(
                projectID: projectID, tab: tab,
                title: AppLocalizedString.string("保存していない変更を破棄しますか?", locale: locale),
                message: String(format: AppLocalizedString.string("%@ の変更は失われます。", locale: locale), (path as NSString).lastPathComponent)
                    + "\n" + FileTabDocumentRegistry.shared.dirtySummary(for: projectID, path: path))
        default: closeChildTab(tab, of: projectID)
        }
    }

    private func closeChildTab(_ tab: ProjectTab, of projectID: ProjectID) {
        Task { @MainActor in
            if case .file(let path) = tab { await FileTabDocumentRegistry.shared.remove(for: projectID, path: path) }
            guard viewModel.projects.contains(where: { $0.id == projectID }) else { return }
            router.tabs.updateLayout(for: projectID) { $0.close(tab, chats: viewModel.chatTabs(in: projectID)) }
            if let selected = router.tabs.layout(for: projectID).selected { router.selectTab(selected, in: projectID) }
            if tab == .browser { router.closeBrowser(for: projectID) }
            if tab == .simulator { simulatorHub?.removeProject(projectID) }
            if case .terminal(let id) = tab { sessionTerminals?.close(id) }
        }
    }

    private func chooseFileToOpen(in projectID: ProjectID) {
        guard let project = viewModel.projects.first(where: { $0.id == projectID }) else { return }
        let workingDirectory = project.directoryPath
        Task { @MainActor in
            let rootPath = await FileTabOpening.root(for: workingDirectory)
            guard viewModel.projects.first(where: { $0.id == projectID })?.directoryPath == workingDirectory else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            panel.prompt = String(localized: "開く")
            guard panel.runModal() == .OK, let url = panel.url,
                  let relative = Self.relativePath(of: url, under: rootPath) else { return }
            fileTabs.openFileTab(projectID: projectID, root: rootPath, relativePath: relative, router: router,
                requestedWorkingDirectory: workingDirectory,
                currentWorkingDirectory: viewModel.projects.first { $0.id == projectID }?.directoryPath)
        }
    }

    nonisolated static func relativePath(of url: URL, under rootPath: String) -> String? {
        FileTabOpening.relativePath(of: url, under: rootPath)
    }


    // MARK: - Helpers

    /// ワークスペース（Project）用のフォルダ選択。NSOpenPanel は次 runloop で提示する。
    private func chooseProjectDirectory() {
        Task { @MainActor in
            guard let url = ProjectFolderPanel.choose(locale: locale) else { return }
            let name = url.lastPathComponent
            if let projectID = viewModel.addProject(name: name, directoryPath: url.path) {
                expandedProjectIDs.insert(projectID)
                // 送信先の無い新規チャット画面から追加したら、そのまま送信先にする（要件 FR-3）。
                if router.viewMode == .single, router.selectedProjectID == nil, router.selectedSession == nil {
                    router.showNewChat(projectID: projectID)
                }
            }
        }
    }

    /// ディレクトリ選択パネルを表示し、選んだフォルダで対象セッションを再起動する。
    /// App Sandbox 無効のため security-scoped bookmark は不要で URL に直接アクセスできる。
    ///
    /// runModal() はメインランループをブロックする同期モーダルなので、confirmationDialog の
    /// ボタンクロージャ（pendingWorkspaceChange = nil でダイアログを閉じる）と同一 runloop で
    /// 呼ぶと、ダイアログの dismiss アニメーション完了前に NSOpenPanel を提示することになり、
    /// パネルが前面に出ない・キーウィンドウを奪えないケースがある。次の runloop に逃がして
    /// ダイアログ解除完了後に提示する。
    /// 選んだ後に、行き先を示した再起動の確認（`pendingFolderChange`）を出す。
    private func chooseWorkspace(for session: SessionViewModel) {
        let id = session.id
        let title = viewModel.sessionNode(id: id)?.displayName ?? SessionViewModel.shortID(for: id)
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "選択")
            panel.message = String(localized: "セッションを再起動するフォルダを選択してください。")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            pendingFolderChange = PendingFolderChange(sessionID: id, sessionTitle: title, directory: url)
        }
    }

    /// 作業場所を変えて再起動する。プロジェクトのタブは維持する。
    private func changeWorkspace(_ id: SessionID, to directory: URL) async {
        await viewModel.changeWorkspace(id, to: directory)
    }

    /// メニューバーの「セッション」メニューから来た、サイドバーの行の操作。
    private func handle(_ request: SidebarRequest) {
        switch request {
        case .renameSession(let id):
            guard viewModel.sessionNode(id: id) != nil else { return }
            beginSessionRename(id)
        case .moveSession(let id, let projectID):
            guard let node = viewModel.sessionNode(id: id),
                  let project = viewModel.projects.first(where: { $0.id == projectID }) else { return }
            if case .appServer = node {
                // チャット型は再起動しないので確認を挟まない（会話と作業フォルダはそのまま）。
                Task {
                    await viewModel.moveSession(id, to: projectID)
                    expandedProjectIDs.insert(projectID)
                }
                return
            }
            pendingMove = PendingSessionMove(sessionID: id, sessionTitle: node.displayName, project: project)
        case .changeFolder(let id):
            pendingWorkspaceChange = viewModel.sessionNode(id: id)?.pty
        }
    }

    /// 登録済みワークスペースへセッションを移動し、移動先をサイドバーで展開する。選択中セッションは維持する。
    /// 移動元プロジェクトのタブは維持する。
    private func moveSessionToProject(_ sessionID: SessionID, projectID: ProjectID) async {
        await viewModel.moveSession(sessionID, to: projectID)
        guard viewModel.sessionNode(id: sessionID)?.projectID == projectID else { return }
        expandedProjectIDs.insert(projectID)
    }

    private func applyRestoredSessionPresentation(_ presentation: RestoredSessionPresentation?) {
        guard let presentation else { return }
        expandedProjectIDs.formUnion(presentation.expandedProjectIDs)

        if let selected = router.selectedSession,
           viewModel.sessionNode(id: selected) != nil {
            markCompletionSeen(for: selected)
            return
        }
        let id = presentation.selectedSessionID
        if let projectID = viewModel.sessionNode(id: id)?.projectID,
           let selected = router.tabs.layout(for: projectID).selected, !selected.isChat {
            router.selectedProjectID = projectID
            ensureProjectSelection()
        } else {
            router.selectedSession = presentation.selectedSessionID
        }
    }

    private func markCompletionSeen(for selectedID: SessionID?) {
        guard let selectedID,
              let node = viewModel.sessionNode(id: selectedID) else { return }
        node.markCompletionSeen()
    }


    private var workspaceCleanupWarningBinding: Binding<Bool> {
        Binding(
            get: { viewModel.workspaceCleanupWarning != nil },
            set: { if !$0 { viewModel.clearWorkspaceCleanupWarning() } }
        )
    }




}

private struct PendingChildClose: Identifiable {
    let id = UUID()
    let projectID: ProjectID
    let tab: ProjectTab
    let title: String
    let message: String
}

private struct PendingFolderChange: Identifiable {
    let id = UUID()
    let sessionID: SessionID
    let sessionTitle: String
    let directory: URL
}

private struct SpawnError: Identifiable {
    let id = UUID()
    let agentName: String
    let message: String
    let opensAgentConsole: Bool
}

@MainActor
struct SelectedSessionNode: Identifiable {
    let id: SessionID
    let node: SessionNode

    init(_ node: SessionNode) {
        self.id = node.id
        self.node = node
    }
}
