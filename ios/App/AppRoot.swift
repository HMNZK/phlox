import SwiftUI
import DesignSystemIOS
import Features
import OSLog
import PhloxCore
import PhloxReachability

/// ルート画面の分岐 + ナビゲーション統合（E4-10 / Phase 4 統合）。
/// AppModel.state に応じて起動ゲート / 接続設定 / 到達不可 / 一覧を切り替え、一覧配下の遷移を Router で管理する。
struct AppRoot: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: AppModel
    @State private var appSettings: AppSettings
    @State private var activeThemeID: String
    @State private var router = UITestingNavigator.initialRouter()
    @State private var setupRouter = NavigationRouter()
    @State private var settingsRouter = NavigationRouter()
    @State private var listVM: SessionListViewModel?
    @State private var usageViewModel: UsageViewModel?
    @State private var createdSession: Session?
    @State private var createdSessionRecovery: SessionDetailRecovery?
    @State private var selectedTab: AppTab? = .sessions
    @State private var scrollToTopRequest = 0
    @State private var qrScanInitialPayload: String?
    @State private var showsMissingSession = false
    @Binding private var pendingPairingURLString: String?
    private let configStore = UserDefaultsConnectionConfigStore()
    private let sharedSessionWriter = SharedSessionWriter()
    private let pushCoordinator: PushCoordinator
    private let pushRegistrationService: PushRegistrationService?

    init(
        pushCoordinator: PushCoordinator,
        pushRegistrationService: PushRegistrationService? = nil,
        pendingPairingURLString: Binding<String?> = .constant(nil)
    ) {
        self.pushCoordinator = pushCoordinator
        self.pushRegistrationService = pushRegistrationService
        _pendingPairingURLString = pendingPairingURLString
        _selectedTab = State(initialValue: UITestingSupport.screen == .sessionShellOffline ? .settings : .sessions)

        let settings = AppSettings(store: UserDefaultsAppSettingsStore())
        let initialModel = UITestingNavigator.initialModel()
        if !UITestingSupport.isEnabled {
            initialModel.authState = AppModel.initialAuthState(faceIDEnabled: settings.faceIDEnabled)
        }
        _appSettings = State(initialValue: settings)
        _model = State(initialValue: initialModel)
        _activeThemeID = State(
            initialValue: UserDefaults.standard.string(forKey: ThemeStore.themeKey) ?? AppTheme.phlox.id
        )
    }

    var body: some View {
        rootContent
            .environment(\.usageViewModel, usageViewModel)
            .overlay { connectingOverlay }
            .animation(.easeInOut(duration: 0.2), value: model.isConnecting)
            .id(activeThemeID)
            .preferredColorScheme(appSettings.appearance.preferredColorScheme)
            .onAppear {
                synchronizeTheme()
                if listVM == nil {
                    listVM = SessionListViewModel(
                        repository: environment.sessionRepository,
                        api: environment.apiClient
                    )
                }
                if usageViewModel == nil {
                    usageViewModel = UsageViewModel(api: environment.apiClient)
                }
                if UITestingSupport.isEnabled {
                    if let listVM {
                        Task { await listVM.observe(interval: .milliseconds(1)) }
                    }
                }
            }
            .onChange(of: pushCoordinator.pendingSessionID) { _, _ in
                handlePendingPushNavigation()
            }
            .onChange(of: model.state) { _, _ in handlePendingPushNavigation() }
            .onChange(of: model.reachability) { _, _ in handlePendingPushNavigation() }
            .onChange(of: listVM?.lastFetchedAt) { _, _ in handlePendingPushNavigation() }
            .onChange(of: listVM?.state) { _, _ in
                handlePendingPushNavigation()
                writeSharedSessionState()
            }
            .alert("このセッションは見つかりません", isPresented: $showsMissingSession) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text("Mac 側で削除されたか、終了して片付けられました。一覧に戻って、ほかのセッションを開いてください。")
            }
            .onChange(of: scenePhase) { _, phase in
                if AppModel.shouldRelock(
                    scenePhase: phase,
                    faceIDEnabled: appSettings.faceIDEnabled
                ) {
                    model.authState = .locked
                }
                if phase == .active, let pushRegistrationService {
                    Task { await pushRegistrationService.retryIfNeeded() }
                }
                if phase == .active, let usageViewModel {
                    Task { await usageViewModel.load() }
                }
            }
            .onChange(of: appSettings.faceIDEnabled) { _, enabled in
                if !enabled {
                    model.authState = .unlocked
                }
            }
            .onChange(of: appSettings.appearance) { _, _ in
                synchronizeTheme()
            }
            .onChange(of: colorScheme) { _, _ in
                guard appSettings.appearance == .system else { return }
                synchronizeTheme()
            }
            .onChange(of: pendingPairingURLString) { _, urlString in
                guard let urlString else { return }
                openQRScan(with: urlString)
                pendingPairingURLString = nil
            }
            .task {
                handlePendingPushNavigation()
                writeSharedSessionState()
                await bootstrap()
            }
    }

    @ViewBuilder
    private var connectingOverlay: some View {
        if model.isConnecting {
            ConnectingOverlayView(
                failure: model.connectFailure,
                onRetry: { Task { await connectAfterPairing() } },
                onDismiss: { model.isConnecting = false }
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch model.state {
        case .locked:
            LaunchGateView(viewModel: LaunchGateViewModel(authenticator: environment.authenticator)) {
                model.authState = .unlocked
            }
        case .setupRequired:
            setupRequiredStack
        case .sessions:
            sessionsStack
        }
    }

    // MARK: - setupRequired スタック

    @ViewBuilder
    private var setupRequiredStack: some View {
        @Bindable var setupRouter = setupRouter
        NavigationStack(path: $setupRouter.path) {
            connectionSettings(onQRScan: { openQRScan(using: setupRouter) })
            .navigationDestination(for: Route.self) { route in
                destination(for: route, router: setupRouter)
            }
        }
        .dsCampNavigationChrome()
    }

    // MARK: - sessions スタック

    @ViewBuilder
    private var sessionsStack: some View {
        if let listVM {
            AppShellView(
                selection: tabSelection,
                navigationState: navigationState(listVM: listVM),
                reachability: model.reachability,
                lastFetchedAt: UITestingSupport.screen == .sessionShellOffline
                    ? Date().addingTimeInterval(-180)
                    : listVM.lastFetchedAt,
                host: connectionHost,
                hidesTabBar: selectedTab == .sessions && !router.path.isEmpty,
                hidesAccessory: selectedTab == .sessions && !router.path.isEmpty,
                onOpenSession: openAttentionSession,
                onShowSessionList: showSessionList,
                onReconnect: { Task { await refreshReachability() } },
                sessions: { sessionsTab(listVM: listVM) },
                settings: { settingsTab }
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabSelection: Binding<AppTab?> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard let tab else {
                    openNewChat()
                    return
                }
                guard selectedTab == tab else {
                    selectedTab = tab
                    return
                }
                switch tab {
                case .sessions:
                    router.popToRoot()
                    scrollToTopRequest += 1
                case .settings:
                    settingsRouter.popToRoot()
                }
            }
        )
    }

    private func navigationState(listVM: SessionListViewModel) -> SessionNavigationState {
        SessionNavigationState.resolve(
            listState: listVM.state,
            lastKnownSessions: listVM.lastKnownSessions,
            reachability: model.reachability
        )
    }

    private func openNewChat() {
        router.popToRoot()
        selectedTab = .sessions
        router.push(.newChat(SessionComposeDraft(project: "")))
    }

    private func openAttentionSession(_ id: String) {
        selectedTab = .sessions
        router.popToRoot()
        router.push(.sessionDetail(id: id))
    }

    private func showSessionList() {
        selectedTab = .sessions
        router.popToRoot()
    }

    @ViewBuilder
    private func sessionsTab(listVM: SessionListViewModel) -> some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            SessionListView(
                viewModel: listVM,
                reachability: model.reachability,
                endpoint: listVM.connectionEndpoint,
                onSelectDetail: { router.push(.sessionDetail(id: $0)) },
                onAddSession: { onAddSession(draft: $0) },
                onReconnect: { await refreshReachability() },
                onQRScan: { openQRScan() },
                scrollToTopRequest: scrollToTopRequest
            )
            .navigationStackHomeBackButton()
            .navigationDestination(for: Route.self) { route in
                destination(for: route, router: router)
            }
        }
        .dsCampNavigationChrome()
        .overlay { deleteConfirmationOverlay(for: router) }
    }

    /// 一覧のプロジェクト見出しから初期プロジェクトを渡して新規チャットを開く。
    private func onAddSession(draft: SessionComposeDraft) {
        router.push(.newChat(draft))
    }

    private var settingsTab: some View {
        @Bindable var settingsRouter = settingsRouter
        return NavigationStack(path: $settingsRouter.path) {
            settingsView(onQRScan: { openQRScan(using: settingsRouter) })
                .navigationDestination(for: Route.self) { route in
                    destination(for: route, router: settingsRouter)
                }
        }
        .dsCampNavigationChrome()
    }

    @ViewBuilder
    private func deleteConfirmationOverlay(for router: NavigationRouter) -> some View {
        if case .deleteConfirmation(let id, let count) = router.presented {
            DeleteConfirmationView(
                viewModel: DeleteConfirmationViewModel(
                    sessionID: id,
                    sessionName: listVM?.session(id: id)?.name
                        ?? (createdSession?.id == id ? createdSession?.name : nil)
                        ?? "セッション",
                    cascadeCount: count,
                    api: environment.apiClient,
                    onDeleted: { router.dismiss(); router.popToRoot() }
                ),
                onCancel: { router.dismiss() }
            )
        }
    }

    @ViewBuilder
    private func destination(for route: Route, router: NavigationRouter) -> some View {
        switch route {
        case .sessionDetail(let id):
            // 直近取得分も含めて解決（再購読中の一時的 .loading/.offline で詳細を消さない）。
            let session = listVM?.session(id: id) ?? (createdSession?.id == id ? createdSession : nil)
            if let session {
                SessionDetailDestination(
                    session: session,
                    api: environment.apiClient,
                    recovery: createdSession?.id == id ? createdSessionRecovery : nil,
                    isNewSession: createdSession?.id == id,
                    onDelete: {
                        let count = DeleteConfirmationViewModel.descendantCount(
                            sessionID: session.id,
                            sessions: listVM?.lastKnownSessions ?? []
                        )
                        router.present(.deleteConfirmation(id: session.id, cascadeCount: count))
                    }
                )
                .toolbar(.hidden, for: .tabBar)
            } else {
                Text("セッションが見つかりません")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.surface)
                    .toolbar(.hidden, for: .tabBar)
            }
        case .newChat(let draft):
            NewChatDestination(
                draft: draft,
                api: environment.apiClient,
                onCreated: { session, recovery in
                    createdSession = session
                    createdSessionRecovery = recovery
                    Task { @MainActor in
                        router.pop()
                        await Task.yield()
                        router.push(.sessionDetail(id: session.id))
                    }
                }
            )
            .toolbar(.hidden, for: .tabBar)
        case .settings:
            settingsView(onQRScan: { openQRScan(using: router) })
        case .qrScan:
            QRScanDestination(
                makeApplyViewModel: makePairingApplyViewModel,
                initialScannedString: qrScanInitialPayload,
                onApplied: qrScanOnApplied(using: router)
            )
            .onAppear { qrScanInitialPayload = nil }
        case .deleteConfirmation:
            EmptyView() // sheet で処理
        }
    }

    // MARK: - 接続設定

    @ViewBuilder
    private func connectionSettings(
        onQRScan: @escaping () -> Void
    ) -> some View {
        ConnectionSettingsView(
            viewModel: makeConnectionSettingsViewModel(),
            onQRScan: onQRScan
        )
    }

    @ViewBuilder
    private func settingsView(
        onQRScan: @escaping () -> Void
    ) -> some View {
        SettingsView(
            viewModel: SettingsViewModel(settings: appSettings),
            connectionViewModel: makeConnectionSettingsViewModel(),
            onQRScan: onQRScan
        )
    }

    private func makeConnectionSettingsViewModel() -> ConnectionSettingsViewModel {
        ConnectionSettingsViewModel(
            tokenStore: environment.tokenStore,
            configStore: configStore,
            // 疎通テストは QR で保存済みの host/port/token で GET /sessions を叩く。
            probe: AppEnvironment.pairingProbe
        )
    }

    private func makePairingApplyViewModel() -> PairingApplyViewModel {
        PairingApplyViewModel(
            tokenStore: environment.tokenStore,
            configStore: configStore,
            probe: AppEnvironment.pairingProbe
        )
    }

    private func openQRScan(with payloadString: String? = nil) {
        if model.hasConnectionConfig {
            selectedTab = .settings
            openQRScan(with: payloadString, using: settingsRouter)
        } else {
            openQRScan(with: payloadString, using: setupRouter)
        }
    }

    private func openQRScan(
        with payloadString: String? = nil,
        using router: NavigationRouter
    ) {
        qrScanInitialPayload = payloadString
        router.push(.qrScan)
    }

    /// 初回セットアップ（`setupRequired`）で QR 適用成功後にセッション一覧へ進める。
    private func qrScanOnApplied(using router: NavigationRouter) -> (() -> Void)? {
        guard case .setupRequired = model.state else { return nil }
        return {
            model.hasConnectionConfig = true
            router.popToRoot()
            Task { await connectAfterPairing() }
        }
    }

    /// QR ペアリング直後の接続待ち。Mac / Tailscale の起き上がりには数秒かかるため、
    /// セッション一覧が読めるかタイムアウト（約20秒）まで「接続中…」を出したまま再判定を繰り返す。
    /// 到達性だけ先に online になると一覧が未ロードのままオーバーレイが閉じ、一瞬オフライン画面が出る（＝当初の症状）。
    /// タイムアウトしても閉じずに、原因（`ConnectFailure`）を同じオーバーレイに表示して再試行/閉じるを促す。
    private func connectAfterPairing() async {
        model.isConnecting = true
        model.connectFailure = nil
        let start = Date()
        let timeout: TimeInterval = 20
        while true {
            await environment.reachability.refresh()
            model.reachability = await environment.reachability.current
            await listVM?.refresh()
            let elapsed = Date().timeIntervalSince(start)
            let state = listVM?.state ?? .loading
            if !PairingConnectGate.shouldContinueConnecting(
                listState: state,
                elapsed: elapsed,
                timeout: timeout
            ) {
                if PairingConnectGate.isConnected(listState: state) {
                    model.isConnecting = false            // 一覧が読めた → 接続完了・オーバーレイを閉じる
                } else {
                    model.connectFailure = makeConnectFailure(listState: state)  // タイムアウト → 原因表示
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

    /// 接続失敗時に画面へ出す原因。一覧のエラーがあれば優先し、無ければ到達性ベースの文言（オフライン画面と同一コピー）。
    private func makeConnectFailure(listState: SessionsState) -> ConnectFailure {
        if case .error(let error) = listState {
            return ConnectFailure(
                title: "接続できませんでした",
                message: error.presentation.message,
                detail: nil
            )
        }
        let unreachable = UnreachableViewModel(
            reachability: model.reachability,
            endpoint: connectionEndpoint,
            onRetry: {}
        )
        return ConnectFailure(
            title: unreachable.cardTitle,
            message: unreachable.cardMessage,
            detail: unreachable.technicalDetail
        )
    }

    // MARK: - push navigation

    private func handlePendingPushNavigation() {
        guard let listVM,
              let destination = pushCoordinator.openPendingSession(
                canNavigate: model.state == .sessions && model.reachability == .online,
                listState: listVM.state, fetchedAt: listVM.lastFetchedAt, router: router
              ) else { return }
        selectedTab = .sessions
        showsMissingSession = destination == .notFound
    }

    // MARK: - bootstrap

    private func bootstrap() async {
        if UITestingSupport.isEnabled {
            if UITestingSupport.screen == nil {
                model.hasConnectionConfig = true
                model.reachability = .online
            }
        } else {
            model.hasConnectionConfig = configStore.load() != nil
        }
        await observeReachability()
    }

    private func observeReachability() async {
        for await reachability in environment.reachability.stream() {
            model.reachability = reachability
        }
    }

    private func refreshReachability() async {
        await environment.reachability.refresh()
        model.reachability = await environment.reachability.current
    }

    private var connectionHost: String? {
        configStore.load()?.host
    }

    private var connectionEndpoint: String {
        let config = configStore.load()
        let host = config?.host ?? SessionListViewModel.uiTestFallbackHost
        return "\(host):\(config?.port ?? 8765)"
    }

    private func synchronizeTheme() {
        let themeID = appSettings.appearance.themeID(systemColorScheme: colorScheme)
        UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
        activeThemeID = themeID
    }

    private func writeSharedSessionState() {
        // 未取得・通信失敗では保持し、取得成功の0件だけは空へ更新する。
        guard let listVM else { return }
        let confirmed: [Session]
        switch listVM.state {
        case .loaded(let values): confirmed = values
        case .empty: confirmed = []
        case .loading, .offline, .error: return
        }
        do {
            try sharedSessionWriter.write(sessions: confirmed)
        } catch {
            Logger(subsystem: "com.phlox.mobile.PhloxMobile", category: "Widget")
                .error("Failed to update shared widget state: \(String(describing: error), privacy: .public)")
        }
    }
}

/// 新規チャット画面の ViewModel をナビゲーション push 単位で保持する。
private struct NewChatDestination: View {
    let draft: SessionComposeDraft
    let api: PhloxAPI
    let onCreated: (Session, SessionDetailRecovery?) -> Void
    @State private var viewModel: NewChatViewModel

    init(
        draft: SessionComposeDraft,
        api: PhloxAPI,
        onCreated: @escaping (Session, SessionDetailRecovery?) -> Void
    ) {
        self.draft = draft
        self.api = api
        self.onCreated = onCreated
        _viewModel = State(initialValue: NewChatViewModel(api: api, entryProject: draft))
    }

    var body: some View {
        NewChatView(viewModel: viewModel, onCreated: onCreated)
            .toolbar(.hidden, for: .tabBar)
    }
}

/// QR ペアリング直後の全画面オーバーレイ。接続待ちの間はリッチな中央アニメーション＋「接続中…」を出し、
/// タイムアウト時は原因（`ConnectFailure`）と再試行/閉じるを同じ画面に表示する（背面のちらつきを隠す）。
private struct ConnectingOverlayView: View {
    let failure: ConnectFailure?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            if let failure {
                failedContent(failure)
            } else {
                connectingContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: failure)
    }

    private var connectingContent: some View {
        VStack(spacing: DSSpacing.l) {
            DSConnectingIndicator(size: 132)
            Text("接続中…")
                .font(DSFont.title2)
                .foregroundStyle(DSColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("接続中"))
    }

    private func failedContent(_ failure: ConnectFailure) -> some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "wifi.exclamationmark")
                .font(DSFont.iconConnectionFailure)
                .foregroundStyle(IOSColor.status.error)
                .padding(.bottom, DSSpacing.xs)
            Text(failure.title)
                .font(DSFont.title2)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(failure.message)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
            if let detail = failure.detail {
                Text(detail)
                    .font(DSFont.campMono)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, DSSpacing.xxs)
            }
            VStack(spacing: DSSpacing.s) {
                DSButton("再試行", variant: .primary, action: onRetry)
                DSButton("閉じる", variant: .secondary, action: onDismiss)
            }
            .padding(.top, DSSpacing.m)
        }
        .padding(.horizontal, DSSpacing.xl)
        .frame(maxWidth: 420)
    }
}

/// QR スキャン画面の ViewModel 寿命をナビゲーション push 単位で固定する。
private struct QRScanDestination: View {
    @State private var applyViewModel: PairingApplyViewModel
    let initialScannedString: String?
    let onApplied: (() -> Void)?

    init(
        makeApplyViewModel: @escaping () -> PairingApplyViewModel,
        initialScannedString: String?,
        onApplied: (() -> Void)? = nil
    ) {
        _applyViewModel = State(initialValue: makeApplyViewModel())
        self.initialScannedString = initialScannedString
        self.onApplied = onApplied
    }

    var body: some View {
        QRScanScreen(
            applyViewModel: applyViewModel,
            initialScannedString: initialScannedString,
            onApplied: onApplied
        )
    }
}
