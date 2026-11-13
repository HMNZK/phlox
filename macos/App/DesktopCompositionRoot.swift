import AgentDomain
import AppBootstrap
import DashboardFeature
import Foundation
import Observation
import SessionFeature
import TerminalUI

/// 接続先の実行サービス（世代）が計画的な更新で入れ替わっても、読み込み・コマンドの送り先を差し替えられるようにする入れ物。
@MainActor
final class RuntimeClientBox {
    var client: SessionRuntimeClient
    init(_ client: SessionRuntimeClient) { self.client = client }
}

@MainActor
@Observable
final class DesktopCompositionRoot {
    let dashboard: DashboardViewModel
    let router: AppRouter
    let usage: UsageMonitor
    let newChatDraftStore: NewChatDraftStore
    let mobileTokenViewModel: MobileTokenViewModel
    let pathEnvironment: String
    let claudeBinaryPath: String
    let hookDispatcherPath: String
    private(set) var connectionFailure: String?
    /// 実行サービスの更新を延期した・中止した理由など、利用者へ伝える案内。
    private(set) var updateNotice: String?
    @ObservationIgnored private let box: RuntimeClientBox
    @ObservationIgnored private var client: SessionRuntimeClient { box.client }
    @ObservationIgnored private let launcher: SessionRuntimeLauncher
    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let bundleURL: URL
    /// 延期された更新を、間隔を空けて有限回だけ再要求するTask（`HostUpdateRetry`。解放時にキャンセルする）。
    @ObservationIgnored private var updateRetryTask: Task<Void, Never>?
    /// 接続先の入れ替えのたびに増やす。古い接続から遅れて届いた結果を捨てるために使う。
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var preferenceTask: Task<Void, Never>?
    @ObservationIgnored private var contentRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var contentRefreshID: UUID?
    @ObservationIgnored private var usesOverview = false
    @ObservationIgnored private var lastPreferences: [String: SessionRuntimePreference]
    @ObservationIgnored private var lastModels: [AgentKind: [ControlModelOption]]

    init() async throws {
        if ProcessInfo.processInfo.environment["PHLOX_DATA_DIR"]?.isEmpty != false {
            let outcome = CompositionRoot.migrateAppSupportIfNeeded()
            if let reason = outcome.startupFailureReason {
                throw CompositionRoot.CompositionError.migrationFailed(reason: reason)
            }
        }
        let storeURL = try SessionRuntimeLease.resolvedStoreURL()
        let bundleURL = try await Task.detached {
            try SessionRuntimeBundleStore.prepare(storeURL: storeURL)
        }.value
        let launcher = SessionRuntimeLauncher(runtimeBundleURL: bundleURL, storeURL: storeURL)
        var endpoint = try await launcher.connect()
        // 実行サービスが古い版なら、動いている作業を止めずに新版へ切り替える。未対応・延期は互換接続のまま続ける。
        let update = await Self.requestHostUpdate(endpoint: endpoint, bundleURL: bundleURL, storeURL: storeURL, launcher: launcher)
        endpoint = update.endpoint
        try TerminalCoordinator.configureRuntimeImageStore(
            directory: storeURL.appendingPathComponent("session-runtime/images-\(endpoint.generation.uuidString)", isDirectory: true),
            writable: false
        )
        let client = SessionRuntimeClient(endpoint: endpoint)
        try await client.handshake()
        let application = try JSONDecoder().decode(SessionRuntimeApplicationSnapshot.self, from: await client.applicationSnapshot())
        AgentModelCatalog.configure(provider: SessionRuntimeModelProvider(models: application.models))
        await AgentModelCatalog.refresh()
        let usesOverview = client.supportsOverview && client.supportsSessionContent
        let initialOverview = usesOverview ? try await client.overview() : nil
        let initialSnapshot = usesOverview ? nil : try await client.snapshot()
        guard let usageSnapshot = initialOverview?.usage ?? initialSnapshot?.usage else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        let box = RuntimeClientBox(client)
        self.box = box
        self.launcher = launcher
        self.storeURL = storeURL
        self.bundleURL = bundleURL
        self.updateNotice = update.notice
        self.usesOverview = usesOverview
        self.pathEnvironment = application.pathEnvironment
        self.claudeBinaryPath = application.claudeBinaryPath
        self.hookDispatcherPath = application.hookDispatcherPath
        let paneLayoutStore = PaneLayoutStore(userDefaults: .phloxDefaults())
        if let initialOverview {
            self.dashboard = try DashboardViewModel(overview: initialOverview,
                paneLayoutStore: paneLayoutStore, commandHandler: { try await box.client.command($0) })
        } else if let initialSnapshot {
            self.dashboard = try DashboardViewModel(projection: initialSnapshot,
                paneLayoutStore: paneLayoutStore, commandHandler: { try await box.client.command($0) })
        } else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        self.router = AppRouter(tabs: ProjectTabStore(defaults: .phloxDefaults()))
        self.usage = UsageMonitor(projection: usageSnapshot) { command in
            _ = try await box.client.command(.usage(command))
        }
        self.newChatDraftStore = NewChatDraftStore()
        self.mobileTokenViewModel = MobileTokenViewModel(snapshot: application.mobile) { command in
            let payload = try JSONEncoder().encode(SessionRuntimeApplicationCommand.mobile(command))
            let reply = try JSONDecoder().decode(SessionRuntimeApplicationReply.self, from: await box.client.applicationCommand(payload))
            guard case .mobile(let result) = reply else { throw SessionRuntimeConnectionError.incompatibleProtocol }
            return result
        }
        self.lastPreferences = SessionRuntimePreferences.snapshot()
        self.lastModels = application.models
        installCommandCallbacks()
        dashboard.runtimeSupportsChatReadModel = client.supportsChatReadModel
        dashboard.runtimeContentLoader = { try await box.client.content($0) }
        dashboard.onRuntimeSessionsViewed = { [weak self] _ in self?.scheduleContentRefresh() }
        scheduleContentRefresh()
        try await sendPreferences()
        startPolling()
        if update.deferred { startUpdateRetry(generation: endpoint.generation) }
        settingsTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification).map({ _ in true }) {
                if Task.isCancelled { break }
                self?.preferencesChanged()
            }
        }
        router.tabs.migrateLegacy(
            sessionProjects: Dictionary(uniqueKeysWithValues: dashboard.sessionNodes.compactMap { node in
                node.projectID.map { (node.id, $0) }
            }), projects: dashboard.projects
        )
    }

    /// コマンドの返答で届く最新状態を、今の接続先のものだけ反映する。
    private func installCommandCallbacks() {
        let current = epoch
        client.onCommandSnapshot = { [weak self] snapshot in
            guard let self, self.epoch == current else { return }
            try await self.applyLatest(snapshot)
        }
        if usesOverview {
            client.onCommandOverview = { [weak self] overview in
                guard let self, self.epoch == current else { return }
                try await self.applyLatest(overview)
            }
        } else { client.onCommandOverview = nil }
    }

    /// 計画的な更新などで実行サービスが入れ替わっていたら、最新の世代へ接続し直して差し替える。
    private func connectToNewestService() async throws {
        var lastError: Error = SessionRuntimeConnectionError.runtimeUnavailable("実行サービスに接続できません。")
        let deadline = ContinuousClock.now + .seconds(45)
        while ContinuousClock.now < deadline {
            do {
                let endpoint = try await launcher.connect()
                guard endpoint.generation != client.endpoint.generation else { return }
                let next = SessionRuntimeClient(endpoint: endpoint)
                try await next.handshake()
                try TerminalCoordinator.configureRuntimeImageStore(
                    directory: storeURL.appendingPathComponent("session-runtime/images-\(endpoint.generation.uuidString)", isDirectory: true),
                    writable: false
                )
                epoch += 1
                let old = box.client
                old.disconnect()
                old.onCommandSnapshot = nil
                old.onCommandOverview = nil
                box.client = next
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as SessionRuntimeConnectionError {
                // 新しい実行サービスの起動待ち（終了処理中・起動準備中・別の画面が接続中）だけ待つ。互換性・認可の失敗は即座に返す。
                guard case .runtimeUnavailable = error else { throw error }
                lastError = error
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw lastError
    }

    func reconnect() async {
        do {
            try await connectToNewestService()
            try await client.handshake()
            usesOverview = client.supportsOverview && client.supportsSessionContent
            dashboard.runtimeSupportsChatReadModel = client.supportsChatReadModel
            installCommandCallbacks()
            contentRefreshTask?.cancel()
            contentRefreshTask = nil
            contentRefreshID = nil
            if usesOverview { try await applyLatest(await client.overview()) }
            else { try await applyLatest(await client.snapshot()) }
            try await applyApplicationSnapshot()
            try await sendPreferences()
            connectionFailure = nil
            // 更新の案内は、入れ替え前の実行サービスについてのもの。つなぎ直したら消す。
            updateNotice = nil
            startPolling()
        } catch { connectionFailure = error.localizedDescription }
    }

    /// 接続が切れたら自動で最新の実行サービスへつなぎ直す（更新による入れ替えは利用者の操作を要さない）。
    private func scheduleAutoReconnect(_ error: Error) {
        connectionFailure = error.localizedDescription
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            await self?.reconnect()
            self?.reconnectTask = nil
        }
    }

    /// 起動時: 実行サービスが自分より古い版（`HostBuildOrder`。自分が古い・同じ・比べられない版なら要求しない）で、
    /// 更新に対応していれば、止めずに新版へ切り替える。
    /// 結果は新しい接続先と利用者向けの案内。対応外・失敗は元の接続先のまま（既存の実行には触れない）。
    private static func requestHostUpdate(
        endpoint: SessionRuntimeEndpoint, bundleURL: URL, storeURL: URL, launcher: SessionRuntimeLauncher
    ) async -> (endpoint: SessionRuntimeEndpoint, notice: String?, deferred: Bool) {
        let ownBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let discovery = try? SessionRuntimeLease.readDiscovery(storeURL: storeURL),
              discovery.generation == endpoint.generation, discovery.supportsHandover == true,
              let hostBuild = discovery.runtimeBuild, let ownBuild,
              HostBuildOrder.isNewer(ownBuild, than: hostBuild) else { return (endpoint, nil, false) }
        do {
            let probe = SessionRuntimeClient(endpoint: endpoint)
            try await probe.handshake()
            let payload = try JSONEncoder().encode(SessionRuntimeApplicationCommand.handover(bundlePath: bundleURL.path))
            let reply = try JSONDecoder().decode(SessionRuntimeApplicationReply.self, from: await probe.applicationCommand(payload))
            switch reply {
            case .handoverDeferred(let reasons):
                return (endpoint, "実行サービスの更新を延期しました（\(reasons.joined(separator: "、"))）。動いている作業が終わると、しばらくの間は自動で再試行して切り替えます（画面を開き直しても切り替わります）。", true)
            case .handoverStarted:
                let deadline = ContinuousClock.now + .seconds(60)
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(300))
                    if let current = try? await launcher.connect(), current.generation != endpoint.generation { return (current, nil, false) }
                    if let latest = try? SessionRuntimeLease.readDiscovery(storeURL: storeURL),
                       latest.generation == endpoint.generation, latest.state == .ready, let status = latest.updateStatus {
                        return (endpoint, status, false)
                    }
                }
                return (endpoint, "実行サービスの切り替えが完了しませんでした。既存の作業は止めていません。", false)
            default:
                return (endpoint, nil, false)
            }
        } catch is CancellationError {
            return (endpoint, nil, false)
        } catch {
            // 更新に対応していると宣言した実行サービス（`supportsHandover`）への要求の失敗は、旧版の非対応ではない。
            // 黙って旧版扱いにせず、利用者へ伝える（互換接続のまま、既存の実行には触れない）。
            return (endpoint, "実行サービスの更新を要求できませんでした（\(error.localizedDescription)）。既存の作業は止めていません。", false)
        }
    }

    /// 延期された更新を、間隔を空けて有限回だけ再要求する（間隔の下限と回数の上限は`HostUpdateRetry`）。
    /// 延期でなくなった・接続先の世代が変わった・解放されたら止まる。
    private func startUpdateRetry(generation: UUID) {
        guard updateRetryTask == nil else { return }
        // 弱参照は、Sendableなクロージャの中ではなく、ここ（self が let の場所）で束ねる。
        let step: @Sendable () async -> Bool = { [weak self] in
            guard let self else { return false }
            return await self.retryHostUpdate(generation: generation)
        }
        updateRetryTask = Task { await HostUpdateRetry.run(attempt: step) }
    }

    /// 戻り値は、まだ延期が続いているか（続くなら再試行を続ける）。
    private func retryHostUpdate(generation: UUID) async -> Bool {
        guard client.endpoint.generation == generation else { return false }
        let update = await Self.requestHostUpdate(
            endpoint: client.endpoint, bundleURL: bundleURL, storeURL: storeURL, launcher: launcher)
        // 切り替えが始まった場合の再接続は、接続が切れたときの自動再接続が行う。
        updateNotice = update.notice
        return update.deferred
    }

    private func apply(_ snapshot: DashboardRuntimeSnapshot) throws {
        try dashboard.applyRuntimeSnapshot(snapshot)
        if let snapshot = snapshot.usage { usage.applyRuntimeSnapshot(snapshot) }
    }

    private func applyLatest(_ snapshot: DashboardRuntimeSnapshot) async throws {
        do {
            try apply(snapshot)
        } catch let error as TerminalRuntimeImageError {
            guard case .staleReference = error else { throw error }
            try apply(await client.snapshot())
        }
    }

    private func applyLatest(_ overview: DashboardRuntimeOverview) async throws {
        try dashboard.applyRuntimeOverview(overview)
        if let usageSnapshot = overview.usage { usage.applyRuntimeSnapshot(usageSnapshot) }
        scheduleContentRefresh()
    }

    private func startPolling() {
        let pollingEpoch = epoch
        if usesOverview {
            client.startOverviewPolling(onOverview: { [weak self] overview in
                guard let self else { return }
                guard self.epoch == pollingEpoch else { return }
                try await self.applyLatest(overview)
                try await self.applyApplicationSnapshot()
                self.connectionFailure = nil
            }, onFailure: { [weak self] error in self?.scheduleAutoReconnect(error) })
            return
        }
        client.startPolling(onSnapshot: { [weak self] snapshot in
            guard let self else { return }
            guard self.epoch == pollingEpoch else { return }
            try await self.applyLatest(snapshot)
            try await self.applyApplicationSnapshot()
            self.connectionFailure = nil
        }, onFailure: { [weak self] error in self?.scheduleAutoReconnect(error) })
    }

    private func scheduleContentRefresh() {
        guard usesOverview, contentRefreshTask == nil else { return }
        let refreshID = UUID()
        contentRefreshID = refreshID
        contentRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.contentRefreshID == refreshID {
                    self.contentRefreshTask = nil
                    self.contentRefreshID = nil
                }
            }
            do {
                try await self.refreshViewedRuntimeContent(refreshID: refreshID)
            }
            catch is CancellationError { }
            catch { self.connectionFailure = error.localizedDescription }
        }
    }

    private func refreshViewedRuntimeContent(refreshID: UUID) async throws {
        for id in dashboard.viewedRuntimeSessionIDs {
            try Task.checkCancellation()
            guard contentRefreshID == refreshID else { throw CancellationError() }
            guard let node = dashboard.sessionNode(id: id) else { continue }
            let executionAtStart = node.pty?.executionID
            do {
                switch node {
                case .appServer(let chat):
                    try await chat.refreshRuntimeContent()
                case .pty(let pty):
                    let executionID = pty.executionID
                    guard let overview = dashboard.runtimeOverviewSession(id: id),
                          case .pty(let state) = overview.kind else { continue }
                    let displayRevision = state.displayRevision
                    if let displayed = pty.runtimeDisplayedRevision, displayed >= displayRevision { continue }
                    let request = SessionRuntimeContentRequest(sessionID: id, executionID: executionID,
                        target: .ptySnapshot(displayRevision: displayRevision))
                    guard case .ptySnapshot(let snapshot, let capturedRevision) = try await client.content(request) else {
                        throw SessionRuntimeConnectionError.incompatibleProtocol
                    }
                    try Task.checkCancellation()
                    guard contentRefreshID == refreshID else { throw CancellationError() }
                    guard dashboard.sessionNode(id: id)?.pty === pty, pty.executionID == executionID,
                          capturedRevision >= displayRevision else { continue }
                    try pty.applyRuntimeContent(snapshot, displayRevision: capturedRevision)
                }
            } catch SessionRuntimeContentError.staleContent { continue }
            catch is CancellationError { throw CancellationError() }
            catch {
                if let executionAtStart, let pty = node.pty, pty.executionID == executionAtStart {
                    pty.reportRuntimeContentFailure(error)
                }
            }
        }
    }

    private func applyApplicationSnapshot() async throws {
        let snapshot = try JSONDecoder().decode(SessionRuntimeApplicationSnapshot.self, from: await client.applicationSnapshot())
        mobileTokenViewModel.applyRuntimeSnapshot(snapshot.mobile)
        if snapshot.models != lastModels {
            AgentModelCatalog.configure(provider: SessionRuntimeModelProvider(models: snapshot.models))
            await AgentModelCatalog.refresh()
            lastModels = snapshot.models
        }
    }

    private func preferencesChanged() {
        guard SessionRuntimePreferences.snapshot() != lastPreferences else { return }
        preferenceTask?.cancel()
        preferenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                try await self?.sendPreferences()
            } catch is CancellationError {
            } catch { self?.connectionFailure = error.localizedDescription }
        }
    }

    private func sendPreferences() async throws {
        let preferences = SessionRuntimePreferences.snapshot()
        let data = try JSONEncoder().encode(SessionRuntimeApplicationCommand.preferences(preferences))
        let reply = try JSONDecoder().decode(SessionRuntimeApplicationReply.self, from: await client.applicationCommand(data))
        guard case .preferencesApplied = reply else { throw SessionRuntimeConnectionError.incompatibleProtocol }
        lastPreferences = preferences
    }

    deinit {
        settingsTask?.cancel()
        preferenceTask?.cancel()
        contentRefreshTask?.cancel()
        reconnectTask?.cancel()
        updateRetryTask?.cancel()
        Task { @MainActor [box] in box.client.disconnect() }
    }
}
