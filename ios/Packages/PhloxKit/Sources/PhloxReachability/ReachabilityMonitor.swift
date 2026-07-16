import Foundation
import Network
import PhloxCore

/// `NWPathMonitor`（一層目: 物理ネット有無）と health check（二層目: Phlox 応答）を合成して
/// `Reachability` を判定する actor（E3-4）。`scenePhase` 変化に応じて外部から `start()`/`stop()` する。
public actor ReachabilityMonitor: ReachabilityMonitoring {
    public typealias HealthCheck = @Sendable () async -> Bool

    private let healthCheck: HealthCheck
    private let queue = DispatchQueue(label: "com.phlox.mobile.reachability")
    private var monitor: NWPathMonitor?
    private var _current: Reachability = .unknown
    private var continuations: [UUID: AsyncStream<Reachability>.Continuation] = [:]
    private var isMonitoring = false
    private var lastNetworkSatisfied = true

    public init(healthCheck: @escaping HealthCheck, initialNetworkSatisfied: Bool = true) {
        self.healthCheck = healthCheck
        self.lastNetworkSatisfied = initialNetworkSatisfied
    }

    public var current: Reachability { _current }

    public func refresh() async {
        // 経路イベントを待たず、現在のネットワーク状態で即再判定する（QRペアリング直後・手動リトライ用）。
        // 監視中は NWPathMonitor の live な currentPath を優先し、未起動時のみ最後に観測した状態へフォールバックする
        // （offlineNetwork と unreachableHost を取り違えないため、キャッシュだけに依存しない）。
        let satisfied = monitor.map { $0.currentPath.status == .satisfied } ?? lastNetworkSatisfied
        await handlePath(satisfied: satisfied)
    }

    /// 純粋な合成ロジック（テスト可能・E3-4 の二層判定の核）。
    /// 物理ネットなし → offlineNetwork。ネットあり → ホスト応答で online / なしで unreachableHost。
    public static func resolve(networkSatisfied: Bool, healthOK: Bool) -> Reachability {
        guard networkSatisfied else { return .offlineNetwork }
        return healthOK ? .online : .unreachableHost
    }

    /// 監視開始。`scenePhase == .active` で App が呼ぶ。
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { await self?.handlePath(satisfied: satisfied) }
        }
        monitor.start(queue: queue)
    }

    /// 監視停止。`scenePhase == .background` で App が呼ぶ（ポーリング停止）。
    public func stop() {
        isMonitoring = false
        monitor?.cancel()
        monitor = nil
    }

    private func handlePath(satisfied: Bool) async {
        lastNetworkSatisfied = satisfied
        let healthOK = satisfied ? await healthCheck() : false
        update(to: Self.resolve(networkSatisfied: satisfied, healthOK: healthOK))
    }

    private func update(to value: Reachability) {
        _current = value
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    public nonisolated func stream() -> AsyncStream<Reachability> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<Reachability>.Continuation) {
        continuations[id] = continuation
        continuation.yield(_current)
        if !isMonitoring {
            start()
        }
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }
}
