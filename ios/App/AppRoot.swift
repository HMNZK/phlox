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
    @State private var usageRouter = NavigationRouter()
    @State private var listVM: SessionListViewModel?
    @State private var appShell: AppShellViewModel?
    @State private var usageVM: UsageViewModel?
    @State private var qrScanInitialPayload: String?
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
            .overlay { connectingOverlay }
            .animation(.easeInOut(duration: 0.2), value: model.isConnecting)
            .id(activeThemeID)
            .preferredColorScheme(appSettings.appearance.preferredColorScheme)
            .onAppear {
                synchronizeTheme()
                if listVM == nil {
                    listVM = SessionListViewModel(repository: environment.sessionRepository)
                }
                if appShell == nil {
                    appShell = AppShellViewModel(
                        overview: SessionsOverviewViewModel(repository: environment.sessionRepository)
                    )
                }
                if usageVM == nil {
                    usageVM = UsageViewModel(api: environment.apiClient)
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
            .onChange(of: listVM?.lastKnownSessions) { _, sessions in
                guard let sessions else { return }
                writeSharedSessionState(sessions)
            }
            .task {
                handlePendingPushNavigation()
                writeSharedSessionState(listVM?.lastKnownSessions ?? [])
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
        if let listVM, let appShell, let usageVM {
            VStack(spacing: 0) {
                selectedTabContent(listVM: listVM, appShell: appShell, usageVM: usageVM)
                if !tabBarHidden(appShell: appShell) {
                    appTabBar(appShell: appShell)
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// チャット/詳細画面（sessions タブでスタックに push 中）ではタブバーを隠し、
    /// 入力欄を画面下端（入力時はキーボード直上）へ収める。リスト最上位では表示する。
    private func tabBarHidden(appShell: AppShellViewModel) -> Bool {
        appShell.selectedTab == .sessions && !router.path.isEmpty
    }

    @ViewBuilder
    private func selectedTabContent(
        listVM: SessionListViewModel,
        appShell: AppShellViewModel,
        usageVM: UsageViewModel
    ) -> some View {
        switch appShell.selectedTab {
        case .sessions:
            sessionsTab(listVM: listVM)
        case .settings:
            settingsTab
        case .usage:
            usageTab(usageVM: usageVM)
        }
    }

    private func appTabBar(appShell: AppShellViewModel) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                appTabButton(
                    tab: .sessions,
                    title: "セッション",
                    systemImage: "list.bullet",
                    appShell: appShell
                )
                appTabButton(
                    tab: .settings,
                    title: "設定",
                    systemImage: "gearshape",
                    appShell: appShell
                )
                appTabButton(
                    tab: .usage,
                    title: "Usage",
                    systemImage: "chart.bar",
                    appShell: appShell
                )
            }
            .padding(.top, 4)
        }
        .background(DSColor.surface.ignoresSafeArea(edges: .bottom))
    }

    private func appTabButton(
        tab: AppTab,
        title: String,
        systemImage: String,
        appShell: AppShellViewModel
    ) -> some View {
        let isSelected = appShell.selectedTab == tab
        return Button {
            appShell.handleTabTap(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? DSColor.campAccentBright : DSColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: DSTouch.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sessionsTab(listVM: SessionListViewModel) -> some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            SessionListView(
                viewModel: listVM,
                reachability: model.reachability,
                host: connectionHost ?? SessionListViewModel.uiTestFallbackHost,
                onSelectDetail: { router.push(.sessionDetail(id: $0)) },
                onAnswerQuestion: { router.push(.chatAnswer(sessionID: $0)) },
                onAddSession: { onAddSession(project: $0) },
                onReconnect: { await refreshReachability() }
            )
            .navigationDestination(for: Route.self) { route in
                destination(for: route, router: router)
            }
        }
        .dsCampNavigationChrome()
        .overlay { deleteConfirmationOverlay(for: router) }
    }

    /// task-2 の `onAddSession(project:)` seam。未 spawn の compose 詳細へ遷移する。
    private func onAddSession(project: String) {
        router.push(.sessionComposeDraft(project: project))
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

    private func usageTab(usageVM: UsageViewModel) -> some View {
        @Bindable var usageRouter = usageRouter
        return NavigationStack(path: $usageRouter.path) {
            UsageView(model: usageVM)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route, router: usageRouter)
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
            let session = listVM?.session(id: id)
            if let session {
                SessionDetailDestination(
                    session: session,
                    api: environment.apiClient,
                    onDelete: { router.present(.deleteConfirmation(id: session.id, cascadeCount: 0)) }
                )
            } else if UITestingSupport.isEnabled, id == "sess-spawned" {
                // UI テスト: spawn 直後は一覧に未反映のためスタブ詳細を表示
                let spawned = Session(
                    id: id, name: "UITest Spawn", agent: .claudeCode,
                    status: .running, subtitle: "ui-test-proj", updatedAt: Date()
                )
                SessionDetailView(
                    viewModel: SessionDetailViewModel(session: spawned, api: environment.apiClient),
                    approvalViewModel: nil,
                    onDelete: { router.present(.deleteConfirmation(id: id, cascadeCount: 0)) }
                )
            } else {
                Text("セッションが見つかりません")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.surface)
            }
        case .sessionComposeDraft(let project):
            DraftSessionComposeDestination(
                draft: SessionComposeDraft(project: project),
                api: environment.apiClient
            )
        case .chatAnswer(let sessionID):
            chatAnswerDestination(sessionID: sessionID)
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

    @ViewBuilder
    private func chatAnswerDestination(sessionID: String) -> some View {
        let session = listVM?.session(id: sessionID)
        if let session {
            ChatAnswerDestination(session: session, api: environment.apiClient)
        } else if UITestingSupport.isEnabled, sessionID == "sess-tulip" {
            let stub = Session(
                id: sessionID,
                name: "Tulip",
                agent: .codex,
                status: .awaitingApproval(
                    prompt: "`/approvals` のレスポンス契約は v2 (id・session・kind・prompt を含む) で進めますか？最小の id だけにしますか？"
                ),
                subtitle: "回答待ち: 「v2 契約で進めますか？」",
                updatedAt: Date()
            )
            ChatAnswerDestination(session: stub, api: environment.apiClient)
        } else {
            Text("セッションが見つかりません")
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DSColor.surface)
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
            appShell?.selectTab(.settings)
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
            host: connectionHost,
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
        guard let sessionID = pushCoordinator.pendingSessionID else { return }
        appShell?.selectTab(.sessions)
        router.push(.sessionDetail(id: sessionID))
        _ = pushCoordinator.consumePendingSessionID()
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

    private func synchronizeTheme() {
        let themeID = appSettings.appearance.themeID(systemColorScheme: colorScheme)
        UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
        activeThemeID = themeID
    }

    private func writeSharedSessionState(_ sessions: [Session]) {
        // 起動直後は listVM が新規生成され lastKnownSessions が空（未ロード）のため、
        // 空配列で共有ストアを上書きするとウィジェットが「NO SESSIONS」に潰れる。
        // 未ロード/一時的な空での上書きを避け、直近の非空状態を保持する
        // （全セッション削除で空になるケースは前状態が残るが、status ウィジェットとして許容）。
        guard !sessions.isEmpty else { return }
        do {
            try sharedSessionWriter.write(sessions: sessions)
        } catch {
            Logger(subsystem: "com.phlox.mobile.PhloxMobile", category: "Widget")
                .error("Failed to update shared widget state: \(String(describing: error), privacy: .public)")
        }
    }
}

/// ドラフト compose 詳細の入口（task-4 が compose UI・spawn を実装）。
private struct DraftSessionComposeDestination: View {
    let draft: SessionComposeDraft
    let api: PhloxAPI

    var body: some View {
        let placeholder = Session(
            id: Self.placeholderSessionID,
            name: draft.project.isEmpty ? "新規セッション" : draft.project,
            agent: .claudeCode,
            status: .running,
            subtitle: draft.project,
            updatedAt: Date()
        )
        SessionDetailView(
            viewModel: SessionDetailViewModel(session: placeholder, api: api),
            approvalViewModel: nil,
            onDelete: {}
        )
        .environment(\.sessionComposeDraft, draft)
    }

    private static let placeholderSessionID = "draft-compose"
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
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(DSColor.statusError)
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

/// 回答画面の ViewModel 寿命をナビゲーション push 単位で固定する。
private struct ChatAnswerDestination: View {
    let session: Session
    let api: PhloxAPI

    @State private var viewModel: ChatAnswerViewModel

    init(session: Session, api: PhloxAPI) {
        self.session = session
        self.api = api
        _viewModel = State(initialValue: ChatAnswerViewModel(session: session, api: api))
    }

    var body: some View {
        ChatAnswerView(viewModel: viewModel)
    }
}
