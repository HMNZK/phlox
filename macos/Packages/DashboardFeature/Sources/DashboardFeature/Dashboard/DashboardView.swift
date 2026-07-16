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

    @State private var sidebarWidth: CGFloat = 280
    @State private var sidebarWidthAtDragStart: CGFloat = 280
    @State private var inspectorWidth: CGFloat = 300
    @State private var inspectorWidthAtDragStart: CGFloat = 300
    @State private var isCreating = false

    private static let sidebarMinWidth: CGFloat = 240
    private static let detailMinWidth: CGFloat = 400
    private static let inspectorMinWidth: CGFloat = 240
    @State private var spawnError: SpawnError?
    @State private var pendingDeletion: SelectedSessionNode?
    @State private var renamingSession: SelectedSessionNode?
    @State private var pendingWorkspaceChange: SessionViewModel?
    @State private var pendingProjectDeletion: Project?
    @State private var renamingProject: Project?
    @State private var draftName: String = ""
    @State private var expandedProjectIDs: Set<ProjectID> = []
    @State private var sessionTreeViewModel = SessionTreeViewModel()

    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(GridColumns.storageKey) private var gridColumnsRaw: String = GridColumns.auto.rawValue
    @State private var gridSessionPickerPresented = false
    @State private var measuredLeadingOverlayWidth: CGFloat = 0
    @State private var hasMeasuredLeadingOverlayWidth = false
    @State private var measuredTrailingOverlayHeight: CGFloat = 0

    public init(
        viewModel: DashboardViewModel,
        router: AppRouter,
        usageMonitor: UsageMonitor
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _router = Bindable(wrappedValue: router)
        _usageMonitor = Bindable(wrappedValue: usageMonitor)
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
            HStack(spacing: 0) {
                Group {
                    if router.sidebarVisible {
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
                            .frame(width: sidebarWidth, alignment: .leading)
                            .background(DSColor.background)
                            .transition(.move(edge: .leading))

                        Rectangle()
                            .fill(DSColor.separator)
                            .frame(width: 1)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: router.sidebarVisible)

                DashboardDetailView(
                    viewModel: viewModel,
                    router: router,
                    pendingDeletion: $pendingDeletion,
                    renamingSession: $renamingSession,
                    pendingWorkspaceChange: $pendingWorkspaceChange,
                    draftName: $draftName,
                    gridColumns: gridColumns,
                    onChooseProjectDirectory: chooseProjectDirectory,
                    isCreating: isCreating,
                    onSelectAgentKind: { kind, backend in
                        Task { await createSessionFromKind(kind, backend: backend) }
                    },
                    measuredTrailingOverlayHeight: measuredTrailingOverlayHeight
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.background)
                    .transaction { transaction in
                        if transaction.animation != nil {
                            transaction.animation = nil
                        }
                    }

                Group {
                    if router.inspectorVisible {
                        Rectangle()
                            .fill(DSColor.separator)
                            .frame(width: 1)
                        UsageSidebarView(monitor: usageMonitor, chatSession: selectedChatSession)
                            .frame(width: inspectorWidth)
                            .background(DSColor.background)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: router.inspectorVisible)
            }
            // サイドバー開閉トグルを三色ボタンの右隣に固定表示。GeometryReader の内側に置くことで
            // 下の .ignoresSafeArea(.top) と同じくウィンドウ最上部を基準に配置され、三色ボタンと
            // 同じ高さに揃う（外側に置くとセーフエリア分だけ下にずれる）。
            .overlay(alignment: .topLeading) {
                DashboardLeadingTopBarControls(
                    viewModel: viewModel,
                    router: router,
                    onOpenSettings: { openSettings() }
                )
                    .padding(.leading, 78)
                    // 三色ボタンの中心はウィンドウ上端から 16pt（実測: ボタン上端 8pt + 高さ 16pt の半分）。
                    // トグルは 28pt 枠で中心が top + 14 になるため、top = 2 で三色ボタンと中心が揃う。
                    .padding(.top, DSSpacing.xxs)
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    updateMeasuredLeadingOverlayWidth(geometry.size.width)
                                }
                                .onChange(of: geometry.size.width) { _, newWidth in
                                    updateMeasuredLeadingOverlayWidth(newWidth)
                                }
                        }
                    }
            }
            // 右側操作系もオーバーレイにする。VStack フローに置くと、単体表示時にターミナルの
            // AppKit ビュー(NSView)に前面を覆われて消えるため、左トグル同様オーバーレイで前面に出す。
            .overlay(alignment: .topTrailing) {
                DashboardTrailingTopBarControls(
                    viewModel: viewModel,
                    router: router,
                    usageMonitor: usageMonitor,
                    windowWidth: geometry.size.width,
                    // occupiedSidebarWidth には左サイドバーに加え、左側トップバーオーバーレイ
                    // （三色ボタン右のリーディングコントロール群）の占有幅も合算する。
                    // usageAvailableWidth の凍結シグネチャは変更せず、この合算で左衝突を防ぐ。
                    occupiedSidebarWidth: TrailingTopBarLayout.occupiedWidthForUsageLayout(
                        sidebarWidth: sidebarWidth,
                        sidebarVisible: router.sidebarVisible,
                        leadingOverlayWidth: effectiveLeadingOverlayWidth
                    ),
                    gridColumnsRaw: $gridColumnsRaw,
                    gridSessionPickerPresented: $gridSessionPickerPresented
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    updateMeasuredTrailingOverlayHeight(height)
                }
                .padding(.trailing, DSSpacing.m)
            }
            // リサイズ用の掴みしろもオーバーレイにする。HStack 内の区切り線へ overlay で
            // 当たり判定を広げる方式だと、ターミナル(AppKit NSView)側に張り出した分が
            // NSView に遮られてホバー・ドラッグを受け取れないため、ボタン群と同様に
            // 最前面のオーバーレイとして区切り線の真上に重ねる。
            .overlay(alignment: .topLeading) {
                if router.sidebarVisible {
                    ResizeGripView(
                        onChanged: { value in
                            let maxWidth = max(
                                Self.sidebarMinWidth,
                                geometry.size.width - Self.detailMinWidth
                            )
                            let proposed = sidebarWidthAtDragStart + value.translation.width
                            sidebarWidth = min(max(Self.sidebarMinWidth, proposed), maxWidth)
                        },
                        onEnded: { sidebarWidthAtDragStart = sidebarWidth }
                    )
                    .offset(x: sidebarWidth + 0.5 - ResizeGripView.gripWidth / 2)
                    .onAppear { sidebarWidthAtDragStart = sidebarWidth }
                }
            }
            .overlay(alignment: .topTrailing) {
                if router.inspectorVisible {
                    ResizeGripView(
                        onChanged: { value in
                            let maxWidth = max(
                                Self.inspectorMinWidth,
                                geometry.size.width - Self.detailMinWidth
                                    - (router.sidebarVisible ? sidebarWidth : 0)
                            )
                            let proposed = inspectorWidthAtDragStart - value.translation.width
                            inspectorWidth = min(max(Self.inspectorMinWidth, proposed), maxWidth)
                        },
                        onEnded: { inspectorWidthAtDragStart = inspectorWidth }
                    )
                    .offset(x: -(inspectorWidth + 0.5 - ResizeGripView.gripWidth / 2))
                    .onAppear { inspectorWidthAtDragStart = inspectorWidth }
                }
            }
        }
        // hiddenTitleBar でも SwiftUI は上部にタイトルバー分のセーフエリアを確保するため、
        // detail ヘッダーが押し下げられて不自然な隙間になる。上部セーフエリアを無視して
        // コンテンツを最上部まで詰め、トラフィックライト回避はサイドバー側の上余白に一任する。
        .ignoresSafeArea(.container, edges: .top)
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
            if let selectedID,
               let session = viewModel.sessionNode(id: selectedID),
               let projectID = session.projectID {
                expandedProjectIDs.insert(projectID)
            }
        }
        .onChange(of: viewModel.unseenCompletionCount) { _, _ in
            markCompletionSeen(for: router.selectedSession)
        }
        .onChange(of: router.inspectorVisible) { _, visible in
            guard visible else { return }
            Task { await usageMonitor.refresh() }
        }
    }

    /// 選択中の chat セッション（インスペクタの SessionInfoPanel 用）。
    private var selectedChatSession: ChatSessionViewModel? {
        guard let selectedID = router.selectedSession,
              let session = viewModel.sessionNode(id: selectedID),
              case .appServer(let chatSession) = session else { return nil }
        return chatSession
    }

    // MARK: - Header actions

    private var effectiveLeadingOverlayWidth: CGFloat {
        TrailingTopBarLayout.effectiveLeadingOverlayWidth(
            measured: measuredLeadingOverlayWidth,
            hasMeasured: hasMeasuredLeadingOverlayWidth
        )
    }

    private func updateMeasuredLeadingOverlayWidth(_ newWidth: CGFloat) {
        let updated = TrailingTopBarLayout.applyWidthMeasurement(
            newWidth: newWidth,
            currentMeasured: measuredLeadingOverlayWidth,
            hasMeasured: hasMeasuredLeadingOverlayWidth
        )
        measuredLeadingOverlayWidth = updated.measured
        hasMeasuredLeadingOverlayWidth = updated.hasMeasured
    }

    private func updateMeasuredTrailingOverlayHeight(_ newHeight: CGFloat) {
        guard newHeight != measuredTrailingOverlayHeight else { return }
        measuredTrailingOverlayHeight = newHeight
    }

    private var gridColumns: GridColumns {
        GridColumns(rawValue: gridColumnsRaw) ?? .auto
    }

    @ViewBuilder
    private func newSessionMenuItems(projectID: ProjectID?) -> some View {
        ForEach(viewModel.availableAgentDescriptors, id: \.ref) { descriptor in
            ForEach(AgentStartCardsModel.modes(for: descriptor), id: \.self) { mode in
                Button {
                    Task {
                        await createSession(
                            ref: descriptor.ref,
                            projectID: projectID,
                            backend: mode.backend
                        )
                    }
                } label: {
                    Label(
                        newSessionMenuTitle(descriptor: descriptor, mode: mode),
                        systemImage: newSessionMenuSymbol(mode: mode)
                    )
                }
            }
        }
    }

    private func newSessionMenuTitle(descriptor: AgentDescriptor, mode: AgentStartCardMode) -> String {
        "\(descriptor.displayName) — \(mode.label)"
    }

    private func newSessionMenuSymbol(mode: AgentStartCardMode) -> String {
        switch mode {
        case .chat: "bubble.left.and.bubble.right"
        case .terminal: "terminal"
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
              let session = viewModel.sessionNode(id: selectedID)?.pty else { return }
        session.markCompletionSeen()
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { spawnError != nil },
            set: { if !$0 { spawnError = nil } }
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
