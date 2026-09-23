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
    @State private var isCreating = false

    @State private var spawnError: SpawnError?
    @State private var pendingDeletion: SelectedSessionNode?
    @State private var renamingSession: SelectedSessionNode?
    @State private var pendingWorkspaceChange: SessionViewModel?
    @State private var pendingProjectDeletion: Project?
    @State private var draftName: String = ""
    /// 移動・割り当ての再起動確認（03 F9）。
    @State private var pendingMove: PendingSessionMove?
    /// フォルダを選んだ後の再起動確認（03 F9。選んだ行き先を示してから再起動する）。
    @State private var pendingFolderChange: PendingFolderChange?
    /// メニューバーの「名前を変更…」をサイドバーの行の中の編集へ渡す。
    @State private var sidebarRenameRequest: SessionID?
    @State private var expandedProjectIDs: Set<ProjectID> = []
    @State private var sessionTreeViewModel = SessionTreeViewModel()

    @AppStorage(ThemeStore.themeKey, store: UserDefaults.phloxDefaults()) private var themeID = AppTheme.phlox.id
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

    private var deletionDialogTitle: String {
        guard let id = pendingDeletion?.id else {
            return "このセッションを削除しますか?"
        }
        let count = viewModel.descendantCount(of: id)
        if count > 0 {
            return "このセッションと子孫\(count)件を削除しますか?"
        }
        return "このセッションを削除しますか?"
    }

    private var projectDeletionDialogTitle: String {
        guard let project = pendingProjectDeletion else {
            return ProjectDeletionDialogText.title(descendantCount: 0)
        }
        let count = viewModel.projectDeletionDescendantCount(of: project.id)
        return ProjectDeletionDialogText.title(descendantCount: count)
    }

    private var childCloseDialogTitle: Text {
        pendingChildClose?.title ?? Text(verbatim: "")
    }

    /// 削除するセッションに未保存のファイルタブがあれば、その名前も伝える。
    private func deletionDialogMessage(for id: SessionID) -> Text {
        let dirty = fileTabs.dirtyFileNames(for: id)
        guard !dirty.isEmpty else { return Text("ターミナルの内容と進行中の作業は失われます。") }
        return Text("ターミナルの内容と進行中の作業は失われます。保存していないファイル（\(dirty.joined(separator: "、"))）の変更も失われます。")
    }

    private func projectDeletionDialogMessage(for project: Project) -> String {
        let count = viewModel.projectDeletionDescendantCount(of: project.id)
        return ProjectDeletionDialogText.message(descendantCount: count)
    }

    public var body: some View {
        shellWithTabDialogs
            .onChange(of: themeID) { _, _ in
                viewModel.reapplyTheme()
            }
            .alert(
                "セッションの起動に失敗しました",
                isPresented: errorAlertBinding,
                presenting: spawnError
            ) { _ in
                Button("OK", role: .cancel) { spawnError = nil }
            } message: { err in
                Text(err.message)
            }
            .alert(
                viewModel.workspaceCleanupWarning?.title ?? "セッションの後始末に失敗しました",
                isPresented: workspaceCleanupWarningBinding
            ) {
                Button("OK", role: .cancel) {
                    viewModel.clearWorkspaceCleanupWarning()
                }
            } message: {
                Text(viewModel.workspaceCleanupWarning?.message ?? "セッションの後始末に失敗しました。")
            }
            .confirmationDialog(
                deletionDialogTitle,
                isPresented: deletionDialogBinding,
                presenting: pendingDeletion
            ) { selection in
                Button("削除", role: .destructive) {
                    let id = selection.id
                    if router.selectedSession == id {
                        router.selectedSession = nil
                    }
                    pendingDeletion = nil
                    Task { await viewModel.removeSession(id) }
                }
                Button("キャンセル", role: .cancel) { pendingDeletion = nil }
                    .keyboardShortcut(.defaultAction)
            } message: { selection in
                deletionDialogMessage(for: selection.id)
            }
            .confirmationDialog(
                projectDeletionDialogTitle,
                isPresented: projectDeletionDialogBinding,
                presenting: pendingProjectDeletion
            ) { project in
                Button("削除", role: .destructive) {
                    let projectID = project.id
                    pendingProjectDeletion = nil
                    expandedProjectIDs.remove(projectID)
                    if let selected = router.selectedSession,
                       viewModel.sessionNodes(in: projectID).contains(where: { $0.id == selected }) {
                        router.selectedSession = nil
                    }
                    router.tabs.forgetProject(projectID)
                    Task { await viewModel.removeProject(projectID) }
                }
                Button("キャンセル", role: .cancel) { pendingProjectDeletion = nil }
            } message: { project in
                Text(projectDeletionDialogMessage(for: project))
            }
            .onChange(of: pendingWorkspaceChange?.id) { _, id in
                guard id != nil, let session = pendingWorkspaceChange else { return }
                pendingWorkspaceChange = nil
                chooseWorkspace(for: session)
            }
            .renameSessionAlert(
                isPresented: renameAlertBinding,
                session: renamingSession,
                draftName: $draftName,
                onCommit: { selection, name in
                    viewModel.renameSession(selection.id, to: name)
                    renamingSession = nil
                },
                onCancel: { renamingSession = nil }
            )
    }

    /// 子タブを閉じる前の確認（動いているシェル・未保存のファイル）。本体の修飾子の連なりを短くするため分ける。
    private var shellWithTabDialogs: some View {
        navigationShell
            .confirmationDialog(
                childCloseDialogTitle,
                isPresented: childCloseDialogBinding,
                presenting: pendingChildClose
            ) { pending in
                Button("閉じる", role: .destructive) {
                    pendingChildClose = nil
                    closeChildTab(pending.tab, of: pending.sessionID)
                }
                Button("キャンセル", role: .cancel) { pendingChildClose = nil }
                    .keyboardShortcut(.defaultAction)
            } message: { pending in
                pending.message
            }
            .confirmationDialog(
                folderChangeDialogTitle,
                isPresented: folderChangeDialogBinding,
                presenting: pendingFolderChange
            ) { change in
                Button("再起動", role: .destructive) {
                    pendingFolderChange = nil
                    Task { await changeWorkspace(change.sessionID, to: change.directory) }
                }
                Button("キャンセル", role: .cancel) { pendingFolderChange = nil }
                    .keyboardShortcut(.defaultAction)
            } message: { _ in
                Text("ターミナルの内容と進行中の作業は失われます。")
            }
            .confirmationDialog(
                moveDialogTitle,
                isPresented: moveDialogBinding,
                presenting: pendingMove
            ) { move in
                Button("移動して再起動", role: .destructive) {
                    pendingMove = nil
                    Task { await moveSessionToProject(move.sessionID, projectID: move.project.id) }
                }
                Button("キャンセル", role: .cancel) { pendingMove = nil }
                    .keyboardShortcut(.defaultAction)
            } message: { move in
                Text("セッションは \((move.project.directoryPath as NSString).abbreviatingWithTildeInPath) で再起動されます。ターミナルの内容と進行中の作業は失われます。")
            }
    }

    private var moveDialogTitle: Text {
        guard let pendingMove else { return Text(verbatim: "") }
        return Text("「\(pendingMove.sessionTitle)」を \(pendingMove.project.name) へ移動しますか?")
    }

    private var folderChangeDialogTitle: Text {
        guard let pendingFolderChange else { return Text(verbatim: "") }
        let path = (pendingFolderChange.directory.path as NSString).abbreviatingWithTildeInPath
        return Text("「\(pendingFolderChange.sessionTitle)」を \(path) で再起動しますか?")
    }

    private var folderChangeDialogBinding: Binding<Bool> {
        Binding(get: { pendingFolderChange != nil }, set: { if !$0 { pendingFolderChange = nil } })
    }

    private var moveDialogBinding: Binding<Bool> {
        Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })
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
                    if router.viewMode == .grid, !viewModel.projects.isEmpty {
                        GridModeBar(
                            viewModel: viewModel,
                            router: router,
                            sessionPickerPresented: $gridSessionPickerPresented
                        )
                        horizontalSeparator
                    }
                    HStack(spacing: 0) {
                        centerContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(DSColor.windowBackground)
                            .transaction { transaction in
                                if transaction.animation != nil {
                                    transaction.animation = nil
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
                        .padding(.top, DSLayout.toolbarHeight + DSSpacing.xs)
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
                        onChanged: { value in
                            sidebarWidth = PaneWidthPolicy.draggedSidebarWidth(
                                start: sidebarWidthAtDragStart,
                                translation: value.translation.width,
                                windowWidth: windowWidth,
                                inspectorSpan: inspectorSpan(layout)
                            )
                        },
                        onEnded: { sidebarWidthAtDragStart = sidebarWidth }
                    )
                    .offset(x: layout.sidebar + 0.5 - ResizeGripView.gripWidth / 2)
                    .onAppear { sidebarWidthAtDragStart = layout.sidebar }
                }
            }
            .overlay(alignment: .topTrailing) {
                if router.inspectorVisible, !layout.inspectorIsOverlay {
                    ResizeGripView(
                        onChanged: { value in
                            inspectorWidth = PaneWidthPolicy.draggedInspectorWidth(
                                start: inspectorWidthAtDragStart,
                                translation: value.translation.width,
                                windowWidth: windowWidth,
                                sidebarSpan: layout.showsSidebar ? layout.sidebar + PaneWidthPolicy.separatorWidth : 0
                            )
                        },
                        onEnded: { inspectorWidthAtDragStart = inspectorWidth }
                    )
                    .offset(x: -(layout.inspector + 0.5 - ResizeGripView.gripWidth / 2))
                    .onAppear { inspectorWidthAtDragStart = layout.inspector }
                }
            }
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
            hasSessionSelection: viewModel.gridSessionSelection != nil
        )
    }

    @ViewBuilder
    private var gridScopeEmptyState: some View {
        let summary = gridScopeSummary
        VStack(spacing: DSSpacing.l) {
            if let emptyMessage = summary.emptyMessage {
                Text(emptyMessage)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            ForEach(summary.clearActions, id: \.self) { action in
                Button(action.label) {
                    switch action {
                    case .projectFilter:
                        router.clearGridFilter()
                    case .sessionSelection:
                        viewModel.clearGridSessionSelection()
                    }
                }
                .font(DSFont.body)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .buttonStyle(HoverableSoftButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.l)
    }

    /// 選択中の chat セッション（インスペクタの SessionInfoPanel 用）。
    private var selectedChatSession: ChatSessionViewModel? {
        guard let selectedID = router.selectedSession,
              let session = viewModel.sessionNode(id: selectedID),
              case .appServer(let chatSession) = session else { return nil }
        return chatSession
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
                newSessionMenuItems: { projectID in
                    newSessionMenuItems(projectID: projectID)
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
            Menu {
                newSessionMenuItems(projectID: router.selectedProjectID)
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: "＋")
                        .font(.system(size: 13))
                    Text("新規セッション")
                        .font(DSFont.auxiliary.weight(.medium))
                    Text(verbatim: "⌘N")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DSColor.textTertiary)
                }
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(DSColor.cardBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.row).strokeBorder(DSColor.separator, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isCreating)
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
                .frame(width: 28, height: 28)
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
                renamingSession: $renamingSession,
                pendingWorkspaceChange: $pendingWorkspaceChange,
                draftName: $draftName,
                onChooseProjectDirectory: chooseProjectDirectory,
                isCreating: isCreating,
                onSelectAgentKind: { kind, backend in
                    Task { await createSessionFromKind(kind, backend: backend) }
                }
            )
    }

    private var inspectorContent: some View {
        UsageSidebarView(monitor: usageMonitor, chatSession: selectedChatSession)
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

    @ViewBuilder
    private func newSessionMenuItems(projectID: ProjectID?) -> some View {
        let model = NewSessionMenuModel.make(
            projectName: viewModel.projects.first { $0.id == projectID }?.name,
            descriptors: viewModel.availableAgentDescriptors
        )
        Text(model.destinationText)
        if let primary = model.primary {
            Button {
                Task {
                    await createSession(ref: primary.ref, projectID: projectID, backend: primary.backend)
                }
            } label: {
                Label(primary.title, systemImage: primary.systemImage)
            }
        }
        ForEach(model.sections, id: \.title) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    Button {
                        Task {
                            await createSession(ref: item.ref, projectID: projectID, backend: item.backend)
                        }
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            }
        }
    }

    // MARK: - Tabs

    /// 選んだセッションを上段のタブ列に出す（サイドバー・⌘J・対応待ち一覧・復元のどこから選んでも）。
    private func revealSelectedSessionTab() {
        guard let id = router.selectedSession,
              let projectID = viewModel.sessionNode(id: id)?.projectID else { return }
        router.commonTerminalSelected = false
        router.tabs.reveal(id, in: projectID, candidates: viewModel.sessionNodes(in: projectID).map(\.id))
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
        }
    }

    /// 動いているシェル・未保存のファイルは確認してから閉じる。
    private func requestChildClose(_ tab: ChildTab, of sessionID: SessionID) {
        switch tab {
        case .conversation:
            return
        case .terminal where sessionTerminals?.isRunning(sessionID) == true:
            pendingChildClose = PendingChildClose(
                sessionID: sessionID,
                tab: tab,
                title: Text("ターミナルを閉じますか?"),
                message: Text("シェルを終了します。実行中のコマンドも止まります。")
            )
        case .file(let path) where fileTabs.existing(for: sessionID, path: path)?.isDirty == true:
            pendingChildClose = PendingChildClose(
                sessionID: sessionID,
                tab: tab,
                title: Text("保存していない変更を破棄しますか?"),
                message: Text("\((path as NSString).lastPathComponent) の変更は失われます。")
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

    private var childCloseDialogBinding: Binding<Bool> {
        Binding(get: { pendingChildClose != nil }, set: { if !$0 { pendingChildClose = nil } })
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

    private func createSession(ref: AgentRef, projectID: ProjectID? = nil, backend: SessionBackend = .pty) async {
        guard !isCreating else { return }
        let resolvedProjectID = projectID ?? defaultProjectIDForNewSession()
        guard let resolvedProjectID else {
            chooseProjectDirectory()
            return
        }
        isCreating = true
        defer { isCreating = false }
        do {
            let newID = try await viewModel.spawnNewSession(ref: ref, projectID: resolvedProjectID, backend: backend)
            expandedProjectIDs.insert(resolvedProjectID)
            router.selectedSession = newID
        } catch {
            let raw = error.localizedDescription
            spawnError = SpawnError(message: raw.isEmpty ? String(describing: error) : raw)
        }
    }

    /// ワークスペース（Project）用のフォルダ選択。NSOpenPanel は次 runloop で提示する。
    private func chooseProjectDirectory() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "追加")
            panel.message = String(localized: "プロジェクトとして使うフォルダを選択してください。")
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
            guard let node = viewModel.sessionNode(id: id) else { return }
            if router.sidebarVisible, !router.sidebarLacksRoom || router.sidebarPeeking {
                sidebarRenameRequest = id
            } else {
                renamingSession = SelectedSessionNode(node)
                draftName = node.name
            }
        case .moveSession(let id, let projectID):
            guard let node = viewModel.sessionNode(id: id),
                  let project = viewModel.projects.first(where: { $0.id == projectID }) else { return }
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

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { spawnError != nil },
            set: { if !$0 { spawnError = nil } }
        )
    }

    private var workspaceCleanupWarningBinding: Binding<Bool> {
        Binding(
            get: { viewModel.workspaceCleanupWarning != nil },
            set: { if !$0 { viewModel.clearWorkspaceCleanupWarning() } }
        )
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renamingSession != nil }, set: { if !$0 { renamingSession = nil } })
    }


    private var projectDeletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingProjectDeletion != nil },
            set: { if !$0 { pendingProjectDeletion = nil } }
        )
    }
}

private struct PendingChildClose: Identifiable {
    let id = UUID()
    let sessionID: SessionID
    let tab: ChildTab
    let title: Text
    let message: Text
}

private struct PendingFolderChange: Identifiable {
    let id = UUID()
    let sessionID: SessionID
    let sessionTitle: String
    let directory: URL
}

private struct SpawnError: Identifiable {
    let id = UUID()
    let message: String
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

private extension View {
    func renameSessionAlert(
        isPresented: Binding<Bool>,
        session: SelectedSessionNode?,
        draftName: Binding<String>,
        onCommit: @escaping (SelectedSessionNode, String) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("セッション名を変更", isPresented: isPresented, presenting: session) { selection in
            TextField(selection.node.workspaceName.isEmpty ? "セッション名" : selection.node.workspaceName, text: draftName)
            Button("変更") {
                onCommit(selection, draftName.wrappedValue.trimmingCharacters(in: .whitespaces))
            }
            Button("キャンセル", role: .cancel, action: onCancel)
        } message: { _ in
            Text("空欄にすると短縮ID表示に戻ります。")
        }
    }
}
