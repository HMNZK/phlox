import AgentDomain
import ClaudeAgentKit
import Foundation
import StructuredChatKit
import os

/// VM の購読寿命を識別する。セッションIDが再利用されても旧VMの応答を採用しない。
public struct ClaudeUsageConnection: Sendable {
    public let id: UUID
    public let query: any UsageQuerying

    public init(id: UUID, query: any UsageQuerying) {
        self.id = id
        self.query = query
    }
}

/// Claude だけの取得期限・枠別の新旧判定。表示データの形式には状態を追加しない。
@MainActor
final class ClaudeUsageRefresh {
    private let logger = Logger(subsystem: "com.phlox.usage", category: "Claude")
    private let connections: @MainActor () -> [ClaudeUsageConnection]
    private let dedicated: any UsageQuerying
    private let closeDedicated: @Sendable () async -> Void
    private let cache: any UsageProvider
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let publish: (CLIUsage, String?) -> Void
    private var windows: [String: UsageBucket] = [:]
    private var observedAt: [String: Date] = [:]
    private var revisions: [String: Int] = [:]
    private var lastAttempt: Date?
    private var retryAt: Date?
    private var serverNotBefore: Date?
    private var failureCount = 0
    private var rotation = 0
    private var epoch = 0
    private var inFlight = false
    private var fetchingConnectionID: UUID?
    private var started = false
    private var initialFetchPending = true
    private var enabled = true
    private var automatic = true
    private var waitTask: Task<Void, Never>?
    private var failure: String?
    private var lastDataAt: Date?
    private var staleIDs: Set<String> = []

    init(connections: @escaping @MainActor () -> [ClaudeUsageConnection],
         dedicated: any UsageQuerying, closeDedicated: @escaping @Sendable () async -> Void,
         cache: any UsageProvider, now: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         publish: @escaping (CLIUsage, String?) -> Void) {
        self.connections = connections
        self.dedicated = dedicated
        self.closeDedicated = closeDedicated
        self.cache = cache
        self.now = now
        self.sleep = sleep
        self.publish = publish
    }

    func start(enabled: Bool, automatic: Bool) {
        guard !started else { return }
        started = true
        updateSettings(enabled: enabled, automatic: automatic)
    }

    func stop() {
        started = false
        epoch += 1
        waitTask?.cancel()
        waitTask = nil
        Task { await closeDedicated() }
    }

    func updateSettings(enabled: Bool, automatic: Bool) {
        let changed = self.enabled != enabled || self.automatic != automatic
        self.enabled = enabled
        self.automatic = automatic
        if changed { epoch += 1 }
        if !enabled {
            windows.removeAll()
            staleIDs.removeAll()
            observedAt.removeAll()
            failure = nil
            lastDataAt = nil
            emit(reason: "取得無効")
        }
        if !enabled || (changed && !automatic && !initialFetchPending) { Task { await closeDedicated() } }
        schedule()
    }

    func receive(_ snapshot: AgentRateLimitsSnapshot, from id: UUID) {
        guard started, enabled, connections().contains(where: { $0.id == id }) else { return }
        let accepted = merge(snapshot, since: nil)
        logger.debug("notification: accepted=\(accepted.sorted().joined(separator: ","), privacy: .public)")
        staleIDs.subtract(accepted)
        if !accepted.isEmpty, staleIDs.isDisjoint(with: windows.keys) {
            failure = nil
            failureCount = 0
            retryAt = nil
        }
        emit()
        schedule()
    }

    /// 接続が生まれたら専用プロセスを閉じる。問い合わせ間隔は引き継ぐ。
    func connectionsChanged() {
        let available = connections()
        if inFlight, fetchingConnectionID.map({ id in !available.contains { $0.id == id } }) ?? !available.isEmpty {
            epoch += 1
        }
        if !available.isEmpty { Task { await closeDedicated() } }
        schedule()
    }

    var nextFetchAt: Date? {
        guard enabled, initialFetchPending || automatic else { return nil }
        let missingDeadline = initialFetchPending ? .distantPast
            : ["5h", "weekly"].map { observedAt[$0]?.addingTimeInterval(60) ?? .distantPast }.min()!
        return max(missingDeadline, lastAttempt?.addingTimeInterval(60) ?? .distantPast,
                   retryAt ?? .distantPast, serverNotBefore ?? .distantPast)
    }

    func refreshIfDue() async {
        guard started, enabled, !inFlight, let due = nextFetchAt, due <= now() else { return }
        inFlight = true
        initialFetchPending = false
        let requestEpoch = epoch
        let capturedRevisions = revisions
        let available = connections()
        let selected = available.isEmpty ? nil : available[rotation % available.count]
        fetchingConnectionID = selected?.id
        rotation += 1
        do {
            if selected != nil { await closeDedicated() }
            guard requestEpoch == epoch, started, enabled else { throw CancellationError() }
            lastAttempt = now()
            let snapshot = try await (selected?.query ?? dedicated).fetchRateLimits()
            guard requestEpoch == epoch, started, enabled,
                  selected == nil || connections().contains(where: { $0.id == selected?.id }) else {
                throw CancellationError()
            }
            guard !Self.buckets(snapshot, now: now()).isEmpty else { throw ClaudeChatClientError.malformedUsageResponse }
            let accepted = merge(snapshot, since: capturedRevisions)
            logger.debug("query: source=\(selected == nil ? "dedicated" : "chat", privacy: .public) accepted=\(accepted.sorted().joined(separator: ","), privacy: .public)")
            staleIDs.subtract(accepted)
            failureCount = 0
            retryAt = nil
            if staleIDs.isDisjoint(with: windows.keys) { failure = nil }
        } catch {
            if requestEpoch == epoch, started, enabled {
                failureCount += 1
                let serverDelay: TimeInterval
                if case ClaudeChatClientError.usageRequestThrottled(let seconds) = error {
                    serverDelay = seconds.isFinite ? max(0, seconds) : 0
                } else { serverDelay = 0 }
                if serverDelay > 0 { serverNotBefore = max(serverNotBefore ?? .distantPast, now().addingTimeInterval(serverDelay)) }
                retryAt = now().addingTimeInterval(max(Self.retryDelay(failureCount), serverDelay))
                logger.debug("query failed: retry delay=\(max(Self.retryDelay(self.failureCount), serverDelay))s")
                failure = "Claude使用量を取得できません: \(error.localizedDescription)"
                staleIDs.formUnion(windows.keys.filter { revisions[$0, default: 0] == capturedRevisions[$0, default: 0] })
                // キャッシュを読む時刻で観測期限を延ばさない。
                let cached = await cache.fetch()
                if requestEpoch == epoch, started, enabled,
                   case .ok(let buckets) = cached.state, let asOf = cached.dataAsOf, asOf <= now() {
                    for bucket in buckets where windows[bucket.id] == nil && Self.isValid(bucket, now: now()) {
                        windows[bucket.id] = bucket
                        staleIDs.insert(bucket.id)
                    }
                    if lastDataAt == nil { lastDataAt = asOf }
                    logger.debug("cache fallback: data timestamp=\(asOf.timeIntervalSince1970)")
                }
                if !windows.isEmpty, staleIDs.isDisjoint(with: windows.keys) { failure = nil }
            }
        }
        // プロセス起動・送信の遅延も含め、完了から次回まで最低60秒空ける。
        lastAttempt = now()
        if selected == nil, !automatic || !enabled || !started || requestEpoch != epoch {
            await closeDedicated()
        }
        inFlight = false
        fetchingConnectionID = nil
        if started, enabled { emit() }
        schedule()
    }

    static func retryDelay(_ failures: Int) -> TimeInterval {
        [120, 240, 480, 900][min(max(0, failures - 1), 3)]
    }

    @discardableResult
    private func merge(_ snapshot: AgentRateLimitsSnapshot, since captured: [String: Int]?) -> Set<String> {
        var accepted: Set<String> = []
        for bucket in Self.buckets(snapshot, now: now()) {
            if let captured, captured[bucket.id, default: 0] != revisions[bucket.id, default: 0] { continue }
            // 通知は整数秒、get_usageは小数秒（実測差0.163秒）。同じ秒を旧期間と誤判定しない。
            if let oldReset = windows[bucket.id]?.resetsAt, let newReset = bucket.resetsAt,
               newReset.timeIntervalSince1970.rounded(.down) < oldReset.timeIntervalSince1970.rounded(.down) { continue }
            windows[bucket.id] = bucket
            observedAt[bucket.id] = now()
            revisions[bucket.id, default: 0] += 1
            lastDataAt = snapshot.asOf
            accepted.insert(bucket.id)
        }
        return accepted
    }

    static func buckets(_ snapshot: AgentRateLimitsSnapshot, now: Date) -> [UsageBucket] {
        [("5h", "5時間", snapshot.fiveHour), ("weekly", "週次", snapshot.sevenDay)].compactMap { id, label, value in
            guard let value else { return nil }
            let bucket = UsageBucket(id: id, label: String(localized: String.LocalizationValue(label)),
                                     usedPercent: value.usedPercentage, resetsAt: value.resetsAt)
            return isValid(bucket, now: now) ? bucket : nil
        }
    }

    nonisolated static func isValid(_ bucket: UsageBucket, now: Date) -> Bool {
        bucket.usedPercent.isFinite && bucket.usedPercent >= 0
            && bucket.resetsAt.map { $0.timeIntervalSince1970.isFinite && $0 > now } == true
    }

    private func emit(reason: String = "Claude使用量は未取得です") {
        let countBefore = windows.count
        windows = windows.filter { Self.isValid($0.value, now: now()) }
        staleIDs.formIntersection(windows.keys)
        if !windows.isEmpty, staleIDs.isEmpty { failure = nil }
        if windows.count != countBefore { logger.debug("expired windows removed=\(countBefore - self.windows.count)") }
        let buckets = ["5h", "weekly"].compactMap { windows[$0] }
        publish(CLIUsage(kind: .claudeCode,
                         state: buckets.isEmpty ? .unavailable(reason: failure ?? reason) : .ok(buckets),
                         updatedAt: now(), dataAsOf: lastDataAt), failure)
    }

    private func schedule() {
        waitTask?.cancel()
        waitTask = nil
        guard started else { return }
        // 枠の期限切れは、取得失敗の待機中・自動更新オフでも表示から除く。
        var deadlines = windows.values.compactMap(\.resetsAt)
        if !inFlight, let nextFetchAt { deadlines.append(nextFetchAt) }
        guard let next = deadlines.min() else { return }
        let delay = max(0, next.timeIntervalSince(now()))
        let sleep = self.sleep
        waitTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.emit()
            await self.refreshIfDue()
            if !Task.isCancelled { self.schedule() }
        }
    }
}
