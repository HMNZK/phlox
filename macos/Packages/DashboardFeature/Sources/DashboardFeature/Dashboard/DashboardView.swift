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
    @State private var renamingProject: Project?
    @State private var draftName: String = ""
    @State private var expandedProjectIDs: Set<ProjectID> = []
    @State private var sessionTreeViewModel = SessionTreeViewModel()

    @AppStorage(ThemeStore.themeKey, store: UserDefaults.phloxDefaults()) private var themeID = AppTheme.phlox.id
    @State private var gridSessionPickerPresented = false
    @AppStorage(PanelDrawerLayout.defaultsKey, store: UserDefaults.phloxDefaults()) private var storedDrawerWidth = PanelDrawerLayout.preferredWidth
    @AppStorage(PanelDrawerLayout.migrationDefaultsKey, store: UserDefaults.phloxDefaults()) private var hasMigratedDrawerWidth = false
    @State private var drawerWidthAtDragStart = PanelDrawerLayout.preferredWidth
    /// ゴースト境界だけを動かす一時値。本文 HStack の幅はドラッグ確定まで変えない。
    @State private var drawerDragTranslation: CGFloat = 0
    /// 今のジェスチャーで `drawerWidthAtDragStart` を既に採取したか。ドラッグ開始時の
    /// 表示幅（`storedDrawerWidth` の保存値ではなく実際にクランプ済みの幅）を一度だけ
    /// 採る起点として使う。
    @State private var isDraggingDrawer = false
    @State private var editorPanel = EditorPanelCoordinator()

    /// Claude Code 管理ウィンドウの識別子。App 側が Window シーンを持つときだけ渡す。
    private let agentConsoleWindowID: String?
    /// App が寿命を持つユーザー用シェル。nil は初期化中だけで、既存の Dashboard 利用者は無変更。
    private let terminalPanel: TerminalPanelSession?

    public init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        usageMonitor: UsageMonitor,
        agentConsoleWindowID: String? = nil,
        terminalPanel: TerminalPanelSession? = nil
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _router = Bindable(wrappedValue: router)
        _usageMonitor = Bindable(wrappedValue: usageMonitor)
        self.agentConsoleWindowID = agentConsoleWindowID
        self.terminalPanel = terminalPanel
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

    private func projectDeletionDialogMessage(for project: Project) -> String {
        let count = viewModel.projectDeletionDescendantCount(of: project.id)
        return ProjectDeletionDialogText.message(descendantCount: count)
    }

    public var body: some View {
        navigationShell
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
            } message: { _ in
                Text("ターミナルの内容と進行中の作業は失われます。")
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
                    Task { await viewModel.removeProject(projectID) }
                }
                Button("キャンセル", role: .cancel) { pendingProjectDeletion = nil }
            } message: { project in
                Text(projectDeletionDialogMessage(for: project))
            }
            .confirmationDialog(
                "プロジェクトを変更しますか?",
                isPresented: workspaceChangeDialogBinding,
                presenting: pendingWorkspaceChange
            ) { session in
                Button("フォルダを選択…") {
                    pendingWorkspaceChange = nil
                    chooseWorkspace(for: session)
                }
                Button("キャンセル", role: .cancel) { pendingWorkspaceChange = nil }
            } message: { _ in
                Text("このセッションは再起動され、ターミナルの内容と進行中の作業は失われます。")
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
            .renameProjectAlert(
                isPresented: renameProjectAlertBinding,
                project: renamingProject,
                draftName: $draftName,
                onCommit: { project, name in
                    viewModel.renameProject(project.id, to: name)
                    renamingProject = nil
                },
                onCancel: { renamingProject = nil }
            )
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

                        // パネルは本文と同じレイアウトフローに置く。TerminalView の AppKit NSView を
                        // overlay に置くと既存 PTY タイルとの前後関係で隠れるためである。
                        // 開閉・幅確定時だけ本文幅を変え、ドラッグ中は下のゴースト境界だけを動かす。
                        if drawerIsVisible,
                           drawerWidth(windowWidth: windowWidth, layout: layout) > 0 {
                            verticalSeparator
                            drawerContent
                                .frame(width: drawerWidth(windowWidth: windowWidth, layout: layout))
                                .background(DSColor.windowBackground)
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
                        // 右端のドロワー（P3 で子タブへ移す）を覆わないよう、その左に重ねる。
                        .padding(.trailing, DSSpacing.s + drawerSpan(windowWidth: windowWidth, layout: layout))
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
                                windowWidth: windowWidth - terminalDrawerReservation,
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
                                windowWidth: windowWidth - terminalDrawerReservation,
                                sidebarSpan: layout.showsSidebar ? layout.sidebar + PaneWidthPolicy.separatorWidth : 0
                            )
                        },
                        onEnded: { inspectorWidthAtDragStart = inspectorWidth }
                    )
                    .offset(x: -(drawerSpan(windowWidth: windowWidth, layout: layout) + layout.inspector + 0.5
                        - ResizeGripView.gripWidth / 2))
                    .onAppear { inspectorWidthAtDragStart = layout.inspector }
                }
            }
            // 分割線は AppKit の TerminalView より前面の最後の overlay に置く。ドラッグ中は
            // ゴースト線のみを移動し、onEnded でだけ HStack のドロワー幅を確定・永続化する。
            .overlay(alignment: .topTrailing) {
                if drawerIsVisible, drawerWidth(windowWidth: windowWidth, layout: layout) > 0 {
                    ResizeGripView(
                        onChanged: { value in
                            // 開始幅は「保存値」ではなく、掴んだ瞬間に実際に表示されている
                            // （available でクランプ済みの）幅から採る。保存値のまま採ると、
                            // ウィンドウ縮小等で表示幅が既にクランプされているケースで
                            // ドラッグ開始直後は無反応になる（クランプ後の値へ戻すまで
                            // translation が吸収されるため）。
                            if !isDraggingDrawer {
                                isDraggingDrawer = true
                                drawerWidthAtDragStart = drawerWidth(windowWidth: windowWidth, layout: layout)
                            }
                            drawerDragTranslation = value.translation.width
                        },
                        onEnded: {
                            storedDrawerWidth = proposedDrawerWidth(windowWidth: windowWidth, layout: layout)
                            isDraggingDrawer = false
                            drawerDragTranslation = 0
                        }
                    )
                    .offset(
                        x: -(drawerWidth(windowWidth: windowWidth, layout: layout) + 0.5
                            - ResizeGripView.gripWidth / 2)
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if drawerIsVisible, drawerDragTranslation != 0 {
                    Rectangle()
                        .fill(DSColor.accent)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .offset(x: -proposedDrawerWidth(windowWidth: windowWidth, layout: layout))
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: sidebarLacksRoom(windowWidth: windowWidth), initial: true) { _, lacksRoom in
                router.sidebarLacksRoom = lacksRoom
                if !lacksRoom {
                    router.sidebarPeeking = false
                }
            }
        }
        // hiddenTitleBar でも SwiftUI は上部にタイトルバー分のセーフエリアを確保するため、
        // 上部セーフエリアを無視してツールバーとサイドバーの上端をウィンドウ最上部に揃える。
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChromeConfigurator())
        .onAppear {
            migrateLegacyDrawerWidthIfNeeded()
        }
        .onAppear {
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
                draftName: $draftName,
                renamingProject: $renamingProject,
                pendingProjectDeletion: $pendingProjectDeletion,
                renamingSession: $renamingSession,
                pendingDeletion: $pendingDeletion,
                pendingWorkspaceChange: $pendingWorkspaceChange,
                sessionTreeViewModel: $sessionTreeViewModel,
                onChooseProjectDirectory: chooseProjectDirectory,
                onMoveSessionToProject: moveSessionToProject,
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

    private var sidebarFooter: some View {
        HStack(spacing: DSSpacing.xs) {
            Spacer(minLength: 0)
            if let agentConsoleWindowID {
                footerIconButton(
                    systemImage: "slider.horizontal.3",
                    label: String(localized: "エージェント管理（⇧⌘,）")
                ) {
                    openWindow(id: agentConsoleWindowID)
                }
            }
            footerIconButton(systemImage: "gearshape", label: String(localized: "設定（⌘,）")) {
                openSettings()
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .frame(height: 44)
        .overlay(alignment: .top) { horizontalSeparator }
    }

    private func footerIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(label)
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private var centerContent: some View {
        if router.viewMode == .grid, !viewModel.projects.isEmpty, gridScopeSummary.isEmpty {
            gridScopeEmptyState
        } else {
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

    /// ドロワー（P3 で子タブへ移す）が確定幅を取った残りで 3 ペインを決める。
    private func paneLayout(windowWidth: CGFloat) -> PaneLayout {
        PaneWidthPolicy.resolve(
            windowWidth: max(0, windowWidth - terminalDrawerReservation),
            sidebarVisible: router.sidebarVisible,
            inspectorVisible: router.inspectorVisible,
            sidebarWidth: sidebarWidth,
            inspectorWidth: inspectorWidth
        )
    }

    /// 開いているかに関係なく、サイドバーを横に並べる幅が無いか。
    private func sidebarLacksRoom(windowWidth: CGFloat) -> Bool {
        !PaneWidthPolicy.resolve(
            windowWidth: max(0, windowWidth - terminalDrawerReservation),
            sidebarVisible: true,
            inspectorVisible: router.inspectorVisible,
            sidebarWidth: sidebarWidth,
            inspectorWidth: inspectorWidth
        ).showsSidebar
    }

    private func inspectorSpan(_ layout: PaneLayout) -> CGFloat {
        router.inspectorVisible && !layout.inspectorIsOverlay ? layout.inspector + PaneWidthPolicy.separatorWidth : 0
    }

    private var drawerIsVisible: Bool {
        router.terminalPanelVisible || router.editorPanelVisible
    }

    /// ドロワー表示中も中央の最小幅を侵食しない。残余だけをドロワーへ渡す。
    private func drawerAvailableWidth(windowWidth: CGFloat, layout: PaneLayout) -> CGFloat {
        let sidebar = layout.showsSidebar ? layout.sidebar + PaneWidthPolicy.separatorWidth : 0
        return max(
            0,
            windowWidth - PaneWidthPolicy.centerMinWidth - sidebar - inspectorSpan(layout) - PaneWidthPolicy.separatorWidth
        )
    }

    private func drawerSpan(windowWidth: CGFloat, layout: PaneLayout) -> CGFloat {
        let width = drawerWidth(windowWidth: windowWidth, layout: layout)
        return width > 0 ? width + PaneWidthPolicy.separatorWidth : 0
    }

    private func drawerWidth(windowWidth: CGFloat, layout: PaneLayout) -> CGFloat {
        guard drawerIsVisible else { return 0 }
        return PanelDrawerLayout.clamped(
            width: storedDrawerWidth,
            availableWidth: drawerAvailableWidth(windowWidth: windowWidth, layout: layout)
        )
    }

    private func migrateLegacyDrawerWidthIfNeeded() {
        let savedWidth = (UserDefaults.phloxDefaults().object(forKey: PanelDrawerLayout.defaultsKey) as? NSNumber)
            .map { CGFloat($0.doubleValue) }
        if let migratedWidth = PanelDrawerLayout.migratedWidth(
            savedWidth: savedWidth,
            hasMigrated: hasMigratedDrawerWidth
        ) {
            storedDrawerWidth = migratedWidth
        }
        hasMigratedDrawerWidth = true
    }

    private func proposedDrawerWidth(windowWidth: CGFloat, layout: PaneLayout) -> CGFloat {
        PanelDrawerLayout.proposedWidth(
            startWidth: drawerWidthAtDragStart,
            translation: drawerDragTranslation,
            availableWidth: drawerAvailableWidth(windowWidth: windowWidth, layout: layout)
        )
    }

    /// ポリシーには最後に確定した幅だけを予約する。ドラッグ中のゴースト位置は
    /// ここへ反映しないため、グリッドタイルの再レイアウトが毎フレーム起きない。
    private var terminalDrawerReservation: CGFloat {
        drawerIsVisible ? max(0, storedDrawerWidth) + 1 : 0
    }

    /// ツールバーは上の行に並べたので、ドロワー内の上余白は要らない。
    private static let drawerTopInset: CGFloat = 0

    @ViewBuilder
    private var drawerContent: some View {
        if router.terminalPanelVisible, router.editorPanelVisible {
            VSplitView {
                terminalDrawerContent(topInset: Self.drawerTopInset)
                editorDrawerContent(topInset: 0)
            }
        } else if router.terminalPanelVisible {
            terminalDrawerContent(topInset: Self.drawerTopInset)
        } else {
            editorDrawerContent(topInset: Self.drawerTopInset)
        }
    }

    @ViewBuilder
    private func terminalDrawerContent(topInset: CGFloat) -> some View {
        if let terminalPanel {
            TerminalPanelView(panel: terminalPanel, topInset: topInset)
        } else {
            ContentUnavailableView("ターミナルを準備しています", systemImage: "terminal")
        }
    }

    private func editorDrawerContent(topInset: CGFloat) -> some View {
        EditorPanelView(viewModel: editorPanel.viewModel, topInset: topInset)
            .task(id: editorPanel.target) {
                await editorPanel.resolve(workspaces: editorPanelWorkspaces)
            }
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
    private func chooseWorkspace(for session: SessionViewModel) {
        let id = session.id
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "このフォルダで再起動")
            panel.message = String(localized: "選択するとこのセッションを再起動し、進行中の作業は失われます。")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            await viewModel.changeWorkspace(id, to: url)
        }
    }

    /// 登録済みワークスペースへセッションを移動し、移動先をサイドバーで展開する。選択中セッションは維持する。
    private func moveSessionToProject(_ sessionID: SessionID, projectID: ProjectID) async {
        await viewModel.moveSession(sessionID, to: projectID)
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

    private var workspaceChangeDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingWorkspaceChange != nil },
            set: { if !$0 { pendingWorkspaceChange = nil } }
        )
    }

    private var projectDeletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingProjectDeletion != nil },
            set: { if !$0 { pendingProjectDeletion = nil } }
        )
    }

    private var renameProjectAlertBinding: Binding<Bool> {
        Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } })
    }
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
    func renameProjectAlert(
        isPresented: Binding<Bool>,
        project: Project?,
        draftName: Binding<String>,
        onCommit: @escaping (Project, String) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("プロジェクト名を変更", isPresented: isPresented, presenting: project) { project in
            TextField("プロジェクト名", text: draftName)
            Button("変更") {
                let trimmed = draftName.wrappedValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onCommit(project, trimmed)
            }
            Button("キャンセル", role: .cancel, action: onCancel)
        } message: { _ in
            Text("サイドバーに表示する名前です。フォルダ名は変わりません。")
        }
    }

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
