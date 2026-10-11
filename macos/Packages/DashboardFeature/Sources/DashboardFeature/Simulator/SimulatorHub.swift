import AgentDomain
import Foundation
import Observation

/// 端末はアプリ全体で共有し、表示の可視性だけで画面取得の寿命を管理する。
@MainActor @Observable
public final class SimulatorHub {
    private(set) var devices: [SimulatorDevice] = []
    private(set) var listingReason: String?
    private(set) var listingDiagnosticReason: String?
    private(set) var operationReason: String?
    @ObservationIgnored private let catalog: SimulatorCatalog
    @ObservationIgnored private let makeConnection: () -> SimulatorDisplayConnection
    @ObservationIgnored private let refreshInterval: TimeInterval
    private var selections: [ProjectID: String] = [:]
    private var menuFocusRevisions: [ProjectID: Int] = [:]
    private var connections: [String: SimulatorDisplayConnection] = [:]
    @ObservationIgnored private var visibleDisplays: [UUID: ProjectID] = [:]
    private var unverifiedProjects: [ProjectID: String] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    public convenience init() {
        self.init(catalog: SimulatorCatalog())
    }

    init(catalog: SimulatorCatalog, refreshInterval: TimeInterval = 2,
         makeConnection: @escaping () -> SimulatorDisplayConnection = { SimulatorDisplayConnection() }) {
        self.catalog = catalog
        self.refreshInterval = refreshInterval
        self.makeConnection = makeConnection
    }

    isolated deinit {
        refreshTask?.cancel()
        for connection in connections.values { connection.disconnect() }
    }

    func selectedDevice(for projectID: ProjectID) -> SimulatorDevice? {
        if let udid = selections[projectID] { return devices.first { $0.udid == udid } }
        return devices.first
    }

    public func requestMenuFocus(for projectID: ProjectID?) {
        guard let projectID else { return }
        menuFocusRevisions[projectID, default: 0] += 1
    }

    func menuFocusRevision(for projectID: ProjectID) -> Int {
        menuFocusRevisions[projectID, default: 0]
    }

    func select(udid: String?, for projectID: ProjectID) {
        guard selections[projectID] != udid else { return }
        if let previous = selectedDevice(for: projectID) { connections[previous.udid]?.releaseAll() }
        unverifiedProjects.removeValue(forKey: projectID)
        selections[projectID] = udid
        operationReason = nil
        reconcileConnections()
    }

    #if DEBUG
    /// バックグラウンドの実画面検査で、専用端末を明示してからタブを開く。
    public func refreshForTesting(udid: String, projectID: ProjectID) async {
        await refresh()
        select(udid: udid, for: projectID)
    }
    #endif

    func connection(for projectID: ProjectID) -> SimulatorDisplayConnection? {
        guard let device = selectedDevice(for: projectID) else { return nil }
        return connections[device.udid]
    }

    func displayCount(udid: String) -> Int {
        visibleDisplays.values.filter { selectedDevice(for: $0)?.udid == udid }.count
    }


    func support(for projectID: ProjectID, displayID: UUID) -> SimulatorPolicy.Support {
        guard connection(for: projectID)?.blocksRetry != true else { return .unsupported }
        guard let device = selectedDevice(for: projectID), let connection = connection(for: projectID),
              let policy = connection.policy else { return .unsupported }
        let triesUnverified = unverifiedProjects[projectID] == device.udid
        guard let capability = connection.capability else {
            return triesUnverified && connection.support == .unverified ? .unverified : .unsupported
        }
        return policy.support(xcodeBuild: capability.xcodeBuild, runtimeIdentifier: device.runtimeIdentifier,
                              triesUnverified: triesUnverified)
    }

    func tryUnverified(displayID: UUID) {
        guard let projectID = visibleDisplays[displayID], let device = selectedDevice(for: projectID) else { return }
        unverifiedProjects[projectID] = device.udid
        reconcileConnections()
    }

    func removeDisplay(_ displayID: UUID) {
        visibleDisplays.removeValue(forKey: displayID)
        reconcileConnections()
    }

    func setVisible(_ visible: Bool, displayID: UUID, projectID: ProjectID) {
        if visible {
            visibleDisplays[displayID] = projectID
            if selections[projectID] == nil { selections[projectID] = devices.first?.udid }
        }
        else { visibleDisplays.removeValue(forKey: displayID) }
        reconcileConnections()
        if visibleDisplays.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
        } else if refreshTask == nil {
            let interval = refreshInterval
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                }
            }
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let listing = await catalog.list()
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        devices = listing.devices
        listingReason = listing.reason
        listingDiagnosticReason = listing.diagnosticReason
        // 初回の並び順を記憶し、外部起動による並び替えで選択端末を変えない。
        for projectID in Set(visibleDisplays.values) where selections[projectID] == nil {
            selections[projectID] = devices.first?.udid
        }
        reconcileConnections()
    }

    func boot(for projectID: ProjectID) async {
        guard let device = selectedDevice(for: projectID), device.state == "Shutdown" else { return }
        await perform { try await catalog.boot(udid: device.udid) }
        await refresh()
    }

    func shutdown(udid: String) async {
        guard let device = devices.first(where: { $0.udid == udid }), device.isBooted else { return }
        await perform { try await catalog.shutdown(udid: device.udid) }
        await refresh()
    }

    func screenshot(for projectID: ProjectID, destination: URL) async -> Bool {
        guard let device = selectedDevice(for: projectID), device.isBooted else { return false }
        return await perform { try await catalog.screenshot(udid: device.udid, destination: destination) }
    }

    public func removeProject(_ projectID: ProjectID) {
        selections.removeValue(forKey: projectID)
        menuFocusRevisions.removeValue(forKey: projectID)
        unverifiedProjects.removeValue(forKey: projectID)
        visibleDisplays = visibleDisplays.filter { $0.value != projectID }
        reconcileConnections()
        if visibleDisplays.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    public func disconnectAll() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        visibleDisplays.removeAll()
        unverifiedProjects.removeAll()
        for connection in connections.values { connection.disconnect() }
        connections.removeAll()
    }

    @discardableResult private func perform(_ operation: () async throws -> Void) async -> Bool {
        operationReason = nil
        do {
            try await operation()
            return true
        } catch {
            operationReason = error.localizedDescription
            return false
        }
    }

    private func reconcileConnections() {
        let required = Set(visibleDisplays.values.compactMap { projectID -> String? in
            guard let device = selectedDevice(for: projectID), device.isBooted else { return nil }
            return device.udid
        })
        for udid in Array(connections.keys) where !required.contains(udid) {
            connections.removeValue(forKey: udid)?.disconnect()
        }
        for udid in required where connections[udid] == nil {
            let connection = makeConnection()
            if connection.policy == nil { connection.policy = .verified }
            connection.automaticallyReconnects = true
            if let device = devices.first(where: { $0.udid == udid }) {
                connection.configure(runtimeIdentifier: device.runtimeIdentifier,
                                     triesUnverified: triesUnverified(udid: udid))
            }
            connections[udid] = connection
            connection.attach(udid: udid)
        }
        for udid in required {
            guard let device = devices.first(where: { $0.udid == udid }) else { continue }
            connections[udid]?.configure(runtimeIdentifier: device.runtimeIdentifier,
                                        triesUnverified: triesUnverified(udid: udid))
        }
    }

    private func triesUnverified(udid: String) -> Bool {
        visibleDisplays.values.contains { projectID in
            unverifiedProjects[projectID] == udid && selectedDevice(for: projectID)?.udid == udid
        }
    }
}
