import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

public struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var usageMonitor: UsageMonitor
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var sidebarWidth: CGFloat = DSLayout.sidebarWidth.ideal
    @State private var sidebarWidthAtDragStart: CGFloat = DSLayout.sidebarWidth.ideal
    @State private var inspectorWidth: CGFloat = DSLayout.inspectorWidth.ideal
    @State private var inspectorWidthAtDragStart: CGFloat = DSLayout.inspectorWidth.ideal
    /// 01 E6: 幅はウィンドウごとに保存する。開閉は全ウィンドウで共有の `AppRouter` が持つため、ここでは保存しない。
    @SceneStorage("pane.sidebarWidth") private var savedSidebarWidth = Double(DSLayout.sidebarWidth.ideal)
    @SceneStorage("pane.inspectorWidth") private var savedInspectorWidth = Double(DSLayout.inspectorWidth.ideal)
    @State private var isCreating = false
    /// 起動中の種別（08 S5）と、worktree を作っているか（F2 の案内）。
    @State private var creatingRef: AgentRef?
    /// 起動前・起動失敗時の確認（08 F1・F4）。
    @State private var spawnGuard: SpawnGuard?
    /// 一度でもプロジェクトを追加したか（08 S1: 2 回目以降は案内を手順 1 だけにする）。
    @AppStorage("phlox.start.hasAddedProject", store: UserDefaults.phloxDefaults()) private var hasAddedProject = false
    @Environment(\.locale) private var locale

    @State private var spawnError: SpawnError?
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
    @State private var fileTabs = FileTabDocuments()
    /// 閉じる前に確認が要る子タブ（動いているシェル・未保存のファイル）。
    @State private var pendingChildClose: PendingChildClose?

    /// Claude Code 管理ウィンドウの識別子。App 側が Window シーンを持つときだけ渡す。
    private let agentConsoleWindowID: String?
    /// 上段右端の共通ターミナル（ホームで開く）。App が寿命を持つ。nil は初期化中だけ。
    private let commonTerminal: TerminalPanelSession?
    /// セッションごとのターミナルタブ（その worktree で開く）。App が寿命を持つ。
    private let sessionTerminals: SessionTerminalStore?

    public init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        usageMonitor: UsageMonitor,
        agentConsoleWindowID: String? = nil,
        commonTerminal: TerminalPanelSession? = nil,
        sessionTerminals: SessionTerminalStore? = nil
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _router = Bindable(wrappedValue: router)
        _usageMonitor = Bindable(wrappedValue: usageMonitor)
        self.agentConsoleWindowID = agentConsoleWindowID
        self.commonTerminal = commonTerminal
        self.sessionTerminals = sessionTerminals
    }

    private func deletionDialogTitle(for selection: SelectedSessionNode) -> String {
        SessionDeletionDialogText.title(
            sessionName: selection.node.displayName,
            childCount: viewModel.descendantCount(of: selection.id),
            locale: locale
        )
    }

    /// 巻き込まれる子セッション（名前と「Cx · 実行中」）。
    private func deletionDialogRows(for id: SessionID) -> [DSDialogList.Row] {
        SessionDeletionDialogText.rows(
            children: viewModel.descendantNodes(of: id).map {
                (name: $0.displayName, meta: "\($0.agentDescriptor.tabInitials) · \($0.gridDisplayState.localizedLabel(locale: locale))")
            },
            locale: locale
        )
    }

    /// 保存していないファイルタブ（子の分も）。
    private func deletionDirtyFiles(for id: SessionID) -> [String] {
        ([id] + viewModel.descendantNodes(of: id).map(\.id)).flatMap { fileTabs.dirtyFileNames(for: $0) }
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

    public var body: some View {
        shellWithTabDialogs
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
            .dsDialog(item: $spawnGuard) { item in
                SpawnGuardSheet(
                    spawnGuard: item,
                    sessionNode: { viewModel.sessionNode(id: $0) },
                    onCancel: { spawnGuard = nil },
                    onLaunch: { separates in
                        spawnGuard = nil
                        let request = switch item {
                        case .collision(let request, _, _), .worktreeFailed(let request, _, _, _): request
                        }
                        Task {
                            await createSession(
                                ref: request.ref,
                                projectID: request.projectID,
                                backend: request.backend,
                                isolationOverride: separates
                            )
                        }
                    },
                    onUseWorktree: { path in
                        spawnGuard = nil
                        guard case .worktreeFailed(let request, _, _, _) = item else { return }
                        Task {
                            await createSession(
                                ref: request.ref,
                                projectID: request.projectID,
                                backend: request.backend,
                                isolationOverride: false,
                                workingDirectoryOverride: path
                            )
                        }
                    }
                )
            }
            // サイドバーが出ていれば下端の「新規セッション」から、隠れていれば上端から開く。
            .popover(isPresented: newSessionTableBinding(fromSidebar: false), attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                newSessionTable(projectID: newSessionTableProjectID)
                    .environment(\.locale, locale)
            }
            .overlay(alignment: .bottom) {
                if let path = viewModel.worktreeCreationPath {
                    worktreeProgressToast(path: path)
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
                    note: ProjectDeletionDialogText.note(folderPath: (project.directoryPath as NSString).abbreviatingWithTildeInPath, locale: locale),
                    buttons: [
                        DSDialogButton("削除", role: .destructive) {
                            let projectID = project.id
                            pendingProjectDeletion = nil
                            expandedProjectIDs.remove(projectID)
                            if let selected = router.selectedSession,
                               viewModel.gridSessionNodes(in: projectID).contains(where: { $0.id == selected }) {
                                router.selectedSession = nil
                            }
                            router.tabs.forgetProject(projectID)
                            Task { await viewModel.removeProject(projectID) }
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
                            closeChildTab(pending.tab, of: pending.sessionID)
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
                if layout.showsSidebar {
                    sidebarColumn
                        .frame(width: layout.sidebar)
                        .transition(.move(edge: .leading))
                    verticalSeparator
                }

                VStack(spacing: 0) {
                    DashboardToolbar(
                        viewModel: viewModel,
                        router: router,
                        usageMonitor: usageMonitor,
                        density: ToolbarDensity.forWindowWidth(windowWidth),
                        showsSidebarToggle: !layout.showsSidebar
                    )
                    horizontalSeparator
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
                                .transaction { transaction in
                                    if transaction.animation != nil {
                                        transaction.animation = nil
                                    }
                                }
                        }

                        if router.inspectorVisible, !layout.inspectorIsOverlay {
                            verticalSeparator
                            inspectorContent
                                .frame(width: layout.inspector)
                                .background(DSColor.panelBackground)
                        }

                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: router.sidebarVisible)
            .animation(.easeInOut(duration: 0.18), value: router.inspectorVisible)
            // 幅が足りないときの重ね表示。SwiftUI の overlay は端末の NSView より前面に描ける。
            .overlay(alignment: .topTrailing) {
                if router.inspectorVisible, layout.inspectorIsOverlay {
                    inspectorContent
                        .frame(width: layout.inspector)
                        .frame(maxHeight: .infinity)
                        .background(DSColor.panelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.attention))
                        .overlay {
                            RoundedRectangle(cornerRadius: DSRadius.attention).strokeBorder(DSColor.separator)
                        }
                        .shadow(color: DSShadow.popover.color, radius: DSShadow.popover.radius, y: DSShadow.popover.y)
                        .padding(.top, DSLayout.toolbarHeight + DSSpacing.s)
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
                sidebarWidth = CGFloat(savedSidebarWidth)
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
            // 子タブ列の「変更 N」を出すため、変更タブを開いていなくても一覧を読む。
            .task(id: editorPanel.target) {
                await editorPanel.resolve(workspaces: editorPanelWorkspaces)
            }
        }
        // hiddenTitleBar でも SwiftUI は上部にタイトルバー分のセーフエリアを確保するため、
        // 上部セーフエリアを無視してツールバーとサイドバーの上端をウィンドウ最上部に揃える。
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChromeConfigurator())
        .onAppear {
            updateEditorPanel()
            revealSelectedSessionTab()
        }
        // 子タブを切り替えたら、隠れた区画（端末など）にキー入力が残らないようにする。
        .onChange(of: router.selectedSession.map { router.tabs.layout(for: $0).selected }) { _, _ in
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onChange(of: router.tabRequest) { _, request in
            guard let request else { return }
            router.tabRequest = nil
            handle(request)
        }
        .onChange(of: router.sidebarRequest) { _, request in
            guard let request else { return }
            router.sidebarRequest = nil
            handle(request)
        }
        .onChange(of: viewModel.sessionNodes.map(\.id)) { old, new in
            forgetRemovedSessions(old: old, new: new)
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
            withAnimation(.easeInOut(duration: 0.18)) {
                router.sidebarVisible = SidebarVisibilityPolicy.visibility(
                    afterSwitchingTo: newMode,
                    currentVisible: router.sidebarVisible,
                    hasGridFilter: router.gridFilterProjectID != nil
                )
            }
        }
        .onChange(of: router.gridFilterProjectID) { _, newValue in
            viewModel.gridSessionFilterProjectID = router.viewMode == .grid ? newValue : nil
            viewModel.normalizeGridSessionSelectionForFilterChange()
        }
        .onChange(of: viewModel.restoredSessionPresentation, initial: true) { _, presentation in
            applyRestoredSessionPresentation(presentation)
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
        .onChange(of: viewModel.projects.isEmpty, initial: true) { _, isEmpty in
            if !isEmpty { hasAddedProject = true }
        }
        .onChange(of: router.inspectorVisible) { _, visible in
            guard visible else { return }
            Task { await usageMonitor.refresh() }
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
    /// 表示するセッションが 0 件（06 S10）。見出し・理由・絞り込みの解除・新規セッション。
    private var gridScopeEmptyState: some View {
        let summary = gridScopeSummary
        let projectID = viewModel.gridSessionFilterProjectID
        let projectName = viewModel.projects.first { $0.id == projectID }?.name
        return VStack(spacing: 10) {
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
                NewSessionPopoverButton(table: { newSessionTable(projectID: projectID) }) {
                    HStack(spacing: 6) {
                        if let projectName {
                            Text("\(projectName) で新規セッション")
                        } else {
                            Text("新規セッション")
                        }
                        Text(verbatim: "⌘N").font(.system(size: 10.5)).opacity(0.85)
                    }
                    .font(DSFont.dense.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .fixedSize()
                .disabled(isCreating)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Columns

    /// 左列。上端に信号の余白とサイドバーを隠すボタン、下端に設定とエージェント管理（01 A1）。
    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SidebarToggleButton(router: router)
            }
            .padding(.horizontal, DSSpacing.m)
            .frame(height: DSLayout.toolbarHeight)
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
                onChooseProjectDirectory: chooseProjectDirectory,
                newSessionTable: { projectID in
                    newSessionTable(projectID: projectID ?? newSessionTableProjectID)
                }
            )
            sidebarFooter
        }
        .background(DSColor.sidebarBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("サイドバー"))
    }

    /// 下端の操作列（03）: 新規セッション・エージェント管理・設定。
    private var sidebarFooter: some View {
        HStack(spacing: 2) {
            Button {
                router.newSessionTablePresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: "＋")
                        .font(DSFont.row)
                    Text("新規セッション")
                        .font(DSFont.auxiliary.weight(.medium))
                    Text(verbatim: "⌘N")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DSColor.textTertiary)
                }
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                // PhloxSidebar.dc.html:169: --ctl の面、0.5pt の --ctlBorder、影 0 0.5 1。
                .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.row).strokeBorder(DSColor.controlBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            // プロジェクトが無いうちは作成先を選べないので押せない（メニューの ⌘N と同じ）。
            .disabled(isCreating || viewModel.projects.isEmpty)
            .popover(isPresented: newSessionTableBinding(fromSidebar: true), arrowEdge: .top) {
                newSessionTable(projectID: newSessionTableProjectID)
                    .environment(\.locale, locale)
            }
            .help(Text("新規セッション（⌘N）"))
            .accessibilityLabel(Text("新規セッション（⌘N）"))
            Spacer(minLength: 0)
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
        if router.viewMode == .grid, !viewModel.projects.isEmpty, gridScopeSummary.isEmpty {
            gridScopeEmptyState
        } else if router.viewMode == .single {
            // プロジェクトが無くても上段右端の共通ターミナルは開ける。
            SessionTabsContainer(
                viewModel: viewModel,
                router: router,
                terminals: sessionTerminals,
                commonTerminal: commonTerminal,
                editorPanel: editorPanel,
                files: fileTabs,
                agentConsoleWindowID: agentConsoleWindowID
            ) {
                detailView
            }
        } else {
            detailView
        }
    }

    private var detailView: some View {
        DashboardDetailView(
                viewModel: viewModel,
                router: router,
                pendingDeletion: $pendingDeletion,
                onRenameSession: beginSessionRename,
                pendingWorkspaceChange: $pendingWorkspaceChange,
                onChooseProjectDirectory: chooseProjectDirectory,
                isCreating: isCreating,
                onSelectAgentKind: { kind, backend in
                    Task { await createSessionFromKind(kind, backend: backend) }
                },
                onSelectAgent: { ref, backend in
                    Task { await createSession(ref: ref, projectID: router.selectedProjectID, backend: backend) }
                },
                creatingRef: creatingRef,
                showsAllOnboardingSteps: !hasAddedProject,
                tileTabs: gridTileTabs
            )
    }

    /// グリッドのタイルの子タブ。並びと選択は単体表示の子タブと同じ記録を使う（02 C3）。
    private var gridTileTabs: GridTileTabs {
        GridTileTabs(
            selected: { id in
                switch router.tabs.layout(for: id).selected {
                case .terminal: .terminal
                case .changes: .changes
                case .conversation, .file: .conversation
                }
            },
            select: { id, tab in
                router.tabs.updateLayout(for: id) { layout in
                    switch tab {
                    case .conversation: layout.select(.conversation)
                    case .terminal: layout.open(.terminal)
                    case .changes: layout.open(.changes)
                    }
                }
            },
            content: { id, tab in AnyView(gridTileTabContent(id, tab)) }
        )
    }

    @ViewBuilder
    private func gridTileTabContent(_ id: SessionID, _ tab: GridTileTab) -> some View {
        if let node = viewModel.sessionNode(id: id) {
            switch tab {
            case .conversation:
                EmptyView()
            case .terminal:
                if let sessionTerminals {
                    TerminalPanelView(panel: sessionTerminals.terminal(for: id, workingDirectory: node.rawWorkspacePath), showsHeader: false, showsFontSizeHUD: false, isInGridTile: true)
                        .id(id)
                } else {
                    ContentUnavailableView("ターミナルを準備しています", systemImage: "terminal")
                }
            case .changes:
                // 変更の一覧は選択中のセッションの worktree を読む。フォーカスしていないタイルでは中身を出さない。
                if router.selectedSession == id {
                    EditorPanelView(
                        viewModel: editorPanel.viewModel,
                        projectName: node.workspaceName,
                        workingDirectory: node.rawWorkspacePath,
                        isDirty: { fileTabs.existing(for: id, path: $0)?.isDirty ?? false }
                    ) { path in
                        router.tabs.updateLayout(for: id) { $0.open(.file(path)) }
                        router.openSingle(sessionID: id)
                    }
                } else {
                    Text("タイルを選ぶと変更を表示します")
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var inspectorContent: some View {
        InspectorView(
            router: router,
            monitor: usageMonitor,
            session: router.selectedSession.flatMap { viewModel.sessionNode(id: $0) }
        )
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
            selectedSessionID: router.selectedSession,
            workspaces: editorPanelWorkspaces
        )
    }

    private var editorPanelWorkspaces: [SessionWorkspace] {
        viewModel.workspaceSessionWorkspaces
    }

    private var sidebarShown: Bool {
        router.sidebarVisible && (!router.sidebarLacksRoom || router.sidebarPeeking)
    }

    private func newSessionTableBinding(fromSidebar: Bool) -> Binding<Bool> {
        Binding(
            get: { router.newSessionTablePresented && sidebarShown == fromSidebar },
            set: { router.newSessionTablePresented = $0 }
        )
    }

    /// 種別 × 開き方の表（⌘N・サイドバーの ＋・グリッドの空状態で共通）。
    /// 表の作成先の初期値: 選択中のプロジェクト → 選択中のセッションのプロジェクト → プロジェクトが 1 つならそれ。
    /// どれでもなければ未選択にし、表の見出しで選ばせる（先頭のプロジェクトへ黙って作らない）。
    private var newSessionTableProjectID: ProjectID? {
        if let selected = router.selectedProjectID { return selected }
        if let id = router.selectedSession, let projectID = viewModel.sessionNode(id: id)?.projectID { return projectID }
        return viewModel.projects.count == 1 ? viewModel.projects.first?.id : nil
    }

    private func newSessionTable(projectID: ProjectID?) -> NewSessionTable {
        let entries = viewModel.agentStartEntries(languageCode: locale.language.languageCode?.identifier ?? "ja")
        return NewSessionTable(
            projects: viewModel.projects,
            projectID: projectID,
            model: NewSessionMenuModel.make(
                projectName: viewModel.projects.first { $0.id == projectID }?.name,
                descriptors: entries.map(\.descriptor)
            ),
            defaultBackend: DefaultSessionBackendPreference.stored(),
            detectedRefIDs: Set(entries.filter(\.isDetected).map(\.id)),
            isCreating: isCreating,
            onStart: { ref, projectID, backend in
                Task { await createSession(ref: ref, projectID: projectID, backend: backend) }
            }
        )
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

    // MARK: - Tabs

    /// 選んだセッションを上段のタブ列に出す（サイドバー・⌘J・対応待ち一覧・復元のどこから選んでも）。
    private func revealSelectedSessionTab() {
        guard let id = router.selectedSession,
              let projectID = viewModel.sessionNode(id: id)?.projectID else { return }
        router.commonTerminalSelected = false
        router.tabs.reveal(id, in: projectID, candidates: viewModel.tabSessionNodes(in: projectID).map(\.id))
    }

    /// 削除されたセッションのタブ記録・シェル・ファイルの下書きを捨てる。
    private func forgetRemovedSessions(old: [SessionID], new: [SessionID]) {
        let remaining = Set(new)
        for id in old where !remaining.contains(id) {
            router.tabs.forget(id)
            fileTabs.removeAll(for: id)
            sessionTerminals?.close(id)
        }
    }

    private func handle(_ request: TabRequest) {
        switch request {
        case .confirmSessionDeletion(let id):
            if let node = viewModel.sessionNode(id: id) {
                pendingDeletion = SelectedSessionNode(node)
            }
        case .closeChild(let id, let tab):
            requestChildClose(tab, of: id)
        case .openFile(let id):
            chooseFileToOpen(in: id)
        case .removeFromGrid(let id):
            if let next = viewModel.removeFromGrid(id) { router.selectedSession = next }
        }
    }

    /// コマンドが動いているシェル・未保存のファイルは確認してから閉じる（02「実行中のプロセスがあれば確認」）。
    private func requestChildClose(_ tab: ChildTab, of sessionID: SessionID) {
        switch tab {
        case .conversation:
            return
        case .terminal where sessionTerminals?.isRunning(sessionID) == true:
            Task {
                guard await sessionTerminals?.hasRunningCommand(sessionID) == true else {
                    closeChildTab(tab, of: sessionID)
                    return
                }
                pendingChildClose = PendingChildClose(
                    sessionID: sessionID,
                    tab: tab,
                    title: AppLocalizedString.string("ターミナルを閉じますか?", locale: locale),
                    message: AppLocalizedString.string("シェルを終了します。実行中のコマンドも止まります。", locale: locale)
                )
            }
        case .file(let path) where fileTabs.existing(for: sessionID, path: path)?.isDirty == true:
            pendingChildClose = PendingChildClose(
                sessionID: sessionID,
                tab: tab,
                title: AppLocalizedString.string("保存していない変更を破棄しますか?", locale: locale),
                message: String(format: AppLocalizedString.string("%@ の変更は失われます。", locale: locale), (path as NSString).lastPathComponent)
            )
        default:
            closeChildTab(tab, of: sessionID)
        }
    }

    private func closeChildTab(_ tab: ChildTab, of sessionID: SessionID) {
        router.tabs.updateLayout(for: sessionID) { $0.close(tab) }
        switch tab {
        case .terminal:
            sessionTerminals?.close(sessionID)
        case .file(let path):
            fileTabs.remove(for: sessionID, path: path)
        case .conversation, .changes:
            break
        }
    }

    /// ⌘P：worktree のファイルを選んでファイルの子タブで開く。worktree の外は開かない。
    private func chooseFileToOpen(in sessionID: SessionID) {
        guard let node = viewModel.sessionNode(id: sessionID) else { return }
        let workingDirectory = node.rawWorkspacePath
        Task { @MainActor in
            let rootPath = await WorkingTreeService(
                repositoryRoot: URL(fileURLWithPath: workingDirectory, isDirectory: true)
            ).resolvedRepositoryRootPath() ?? workingDirectory
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            panel.prompt = String(localized: "開く")
            guard panel.runModal() == .OK, let url = panel.url,
                  let relative = Self.relativePath(of: url, under: rootPath) else { return }
            router.viewMode = .single
            router.tabs.updateLayout(for: sessionID) { $0.open(.file(relative)) }
        }
    }

    nonisolated static func relativePath(of url: URL, under rootPath: String) -> String? {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath().path
        let file = url.resolvingSymlinksInPath().path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard file.hasPrefix(prefix) else { return nil }
        return String(file.dropFirst(prefix.count))
    }


    // MARK: - Helpers

    private func defaultProjectIDForNewSession() -> ProjectID? {
        if let selectedProjectID = router.selectedProjectID {
            return selectedProjectID
        }
        if let selectedID = router.selectedSession,
           let session = viewModel.sessionNode(id: selectedID),
           let projectID = session.projectID {
            return projectID
        }
        return viewModel.projects.first?.id
    }

    private func createSessionFromKind(_ kind: AgentKind, backend: SessionBackend) async {
        let ref = AgentRegistry.descriptor(for: kind).ref
        await createSession(ref: ref, projectID: router.selectedProjectID, backend: backend)
    }

    /// - Parameter isolationOverride: 確認（08 F1・F4）で選んだ、この起動だけの worktree 隔離の有無。
    ///   nil は確認前で、プロジェクトの設定に従う。
    private func createSession(
        ref: AgentRef,
        projectID: ProjectID? = nil,
        backend: SessionBackend = .pty,
        isolationOverride: Bool? = nil,
        workingDirectoryOverride: String? = nil
    ) async {
        guard !isCreating else { return }
        let resolvedProjectID = projectID ?? defaultProjectIDForNewSession()
        guard let resolvedProjectID else {
            chooseProjectDirectory()
            return
        }
        let request = NewSessionRequest(ref: ref, projectID: resolvedProjectID, backend: backend)
        let project = viewModel.projects.first { $0.id == resolvedProjectID }
        // F1: 隔離オフのフォルダで動いているセッションがあれば、起動前にたずねる。
        if isolationOverride == nil, let project {
            let peers = NewSessionCollisionGate.peers(project: project, among: viewModel.workspaceSessionWorkspaces)
            if !peers.isEmpty {
                spawnGuard = .collision(request, directory: project.directoryPath, peers: peers)
                return
            }
        }
        isCreating = true
        creatingRef = ref
        defer {
            isCreating = false
            creatingRef = nil
        }
        do {
            let newID = try await DashboardViewModel.$reportsWorktreeCreation.withValue(true) {
                try await viewModel.spawnNewSession(
                    ref: ref,
                    projectID: resolvedProjectID,
                    backend: backend,
                    workingDirectoryOverride: workingDirectoryOverride,
                    isolationOverride: isolationOverride
                )
            }
            expandedProjectIDs.insert(resolvedProjectID)
            router.selectedSession = newID
        } catch {
            // F4: worktree を作れなかったときは、git の出力と次の手を出す。
            if let log = NewSessionCollisionGate.worktreeFailureLog(error) {
                let name = viewModel.availableAgentDescriptors.first { $0.ref == ref }?.displayName ?? ref.id
                let existing = if let project {
                    await NewSessionCollisionGate.existingWorktree(in: log, repository: project.directoryURL)
                } else {
                    String?.none
                }
                spawnGuard = .worktreeFailed(request, agentName: name, log: log, existingWorktree: existing)
                return
            }
            let raw = error.localizedDescription
            spawnError = SpawnError(
                agentName: SpawnFailureDialogText.agentName(for: ref),
                message: raw.isEmpty ? String(describing: error) : raw,
                opensAgentConsole: SpawnFailureDialogText.opensAgentConsole(for: error)
            )
        }
    }

    /// ワークスペース（Project）用のフォルダ選択。NSOpenPanel は次 runloop で提示する。
    private func chooseProjectDirectory() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = AppLocalizedString.string("追加", locale: locale)
            panel.message = AppLocalizedString.string("プロジェクトとして使うフォルダを選択してください。", locale: locale)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let name = url.lastPathComponent
            if let projectID = viewModel.addProject(name: name, directoryPath: url.path) {
                expandedProjectIDs.insert(projectID)
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

    /// 作業場所を変えて再起動する。変わったときだけ旧い場所のシェルとファイルの下書きを捨てる
    /// （確認文で「失われます」と伝えている。再起動の準備に失敗したら元のまま残す）。
    private func changeWorkspace(_ id: SessionID, to directory: URL) async {
        let before = viewModel.sessionNode(id: id)?.rawWorkspacePath
        await viewModel.changeWorkspace(id, to: directory)
        guard viewModel.sessionNode(id: id)?.rawWorkspacePath != before else { return }
        sessionTerminals?.close(id)
        fileTabs.removeAll(for: id)
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
    /// 移動できたときだけ旧い場所のシェルとファイルの下書きを捨てる（再起動の準備に失敗したら元のまま残す）。
    private func moveSessionToProject(_ sessionID: SessionID, projectID: ProjectID) async {
        await viewModel.moveSession(sessionID, to: projectID)
        guard viewModel.sessionNode(id: sessionID)?.projectID == projectID else { return }
        sessionTerminals?.close(sessionID)
        fileTabs.removeAll(for: sessionID)
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
        router.selectedSession = presentation.selectedSessionID
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
    let sessionID: SessionID
    let tab: ChildTab
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
