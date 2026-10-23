import AgentDomain
import AppBootstrap
import DashboardFeature
import Foundation
import Observation
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
        let application = try JSONDecoder().decode(SessionRuntimeApplicationSnapshot.self, from: await client.applicationSnapshot())
        AgentModelCatalog.configure(provider: SessionRuntimeModelProvider(models: application.models))
        await AgentModelCatalog.refresh()
        let snapshot = try await client.snapshot()
        guard let usageSnapshot = snapshot.usage else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        self.client = client
        self.pathEnvironment = application.pathEnvironment
        self.claudeBinaryPath = application.claudeBinaryPath
        self.hookDispatcherPath = application.hookDispatcherPath
        self.dashboard = try DashboardViewModel(
            projection: snapshot,
            paneLayoutStore: PaneLayoutStore(userDefaults: .phloxDefaults()),
            commandHandler: { try await client.command($0) }
        )
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
            try await applyLatest(await client.snapshot())
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

    private func startPolling() {
        client.startPolling(onSnapshot: { [weak self] snapshot in
            guard let self else { return }
            try await self.applyLatest(snapshot)
            try await self.applyApplicationSnapshot()
            self.connectionFailure = nil
        }, onFailure: { [weak self] error in self?.connectionFailure = error.localizedDescription })
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
        Task { @MainActor [client] in client.disconnect() }
    }
}
