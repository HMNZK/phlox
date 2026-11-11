import AgentDomain
import AppBootstrap
import DashboardFeature
import Foundation
import Observation
import SessionFeature
import TerminalUI

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
    @ObservationIgnored private let client: SessionRuntimeClient
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
        let endpoint = try await SessionRuntimeLauncher(runtimeBundleURL: bundleURL, storeURL: storeURL).connect()
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
        self.client = client
        self.usesOverview = usesOverview
        self.pathEnvironment = application.pathEnvironment
        self.claudeBinaryPath = application.claudeBinaryPath
        self.hookDispatcherPath = application.hookDispatcherPath
        let paneLayoutStore = PaneLayoutStore(userDefaults: .phloxDefaults())
        if let initialOverview {
            self.dashboard = try DashboardViewModel(overview: initialOverview,
                paneLayoutStore: paneLayoutStore, commandHandler: { try await client.command($0) })
        } else if let initialSnapshot {
            self.dashboard = try DashboardViewModel(projection: initialSnapshot,
                paneLayoutStore: paneLayoutStore, commandHandler: { try await client.command($0) })
        } else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        self.router = AppRouter(tabs: ProjectTabStore(defaults: .phloxDefaults()))
        self.usage = UsageMonitor(projection: usageSnapshot) { command in
            _ = try await client.command(.usage(command))
        }
        self.newChatDraftStore = NewChatDraftStore()
        self.mobileTokenViewModel = MobileTokenViewModel(snapshot: application.mobile) { command in
            let payload = try JSONEncoder().encode(SessionRuntimeApplicationCommand.mobile(command))
            let reply = try JSONDecoder().decode(SessionRuntimeApplicationReply.self, from: await client.applicationCommand(payload))
            guard case .mobile(let result) = reply else { throw SessionRuntimeConnectionError.incompatibleProtocol }
            return result
        }
        self.lastPreferences = SessionRuntimePreferences.snapshot()
        self.lastModels = application.models
        client.onCommandSnapshot = { [weak self] snapshot in
            try await self?.applyLatest(snapshot)
        }
        if usesOverview {
            client.onCommandOverview = { [weak self] overview in
                try await self?.applyLatest(overview)
            }
        }
        dashboard.runtimeSupportsChatReadModel = client.supportsChatReadModel
        dashboard.runtimeContentLoader = { try await client.content($0) }
        dashboard.onRuntimeSessionsViewed = { [weak self] _ in self?.scheduleContentRefresh() }
        scheduleContentRefresh()
        try await sendPreferences()
        startPolling()
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

    func reconnect() async {
        do {
            try await client.handshake()
            usesOverview = client.supportsOverview && client.supportsSessionContent
            dashboard.runtimeSupportsChatReadModel = client.supportsChatReadModel
            if usesOverview {
                client.onCommandOverview = { [weak self] overview in
                    try await self?.applyLatest(overview)
                }
            } else { client.onCommandOverview = nil }
            contentRefreshTask?.cancel()
            contentRefreshTask = nil
            contentRefreshID = nil
            if usesOverview { try await applyLatest(await client.overview()) }
            else { try await applyLatest(await client.snapshot()) }
            try await applyApplicationSnapshot()
            try await sendPreferences()
            connectionFailure = nil
            startPolling()
        } catch { connectionFailure = error.localizedDescription }
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
        if usesOverview {
            client.startOverviewPolling(onOverview: { [weak self] overview in
                guard let self else { return }
                try await self.applyLatest(overview)
                try await self.applyApplicationSnapshot()
                self.connectionFailure = nil
            }, onFailure: { [weak self] error in self?.connectionFailure = error.localizedDescription })
            return
        }
        client.startPolling(onSnapshot: { [weak self] snapshot in
            guard let self else { return }
            try await self.applyLatest(snapshot)
            try await self.applyApplicationSnapshot()
            self.connectionFailure = nil
        }, onFailure: { [weak self] error in self?.connectionFailure = error.localizedDescription })
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
        Task { @MainActor [client] in client.disconnect() }
    }
}
