import AgentDomain
import Foundation
import Observation
import StructuredChatKit
import ClaudeAgentKit

@MainActor
@Observable
public final class UsageMonitor {
    public private(set) var usages: [AgentKind: CLIUsage]
    /// 取得に失敗し、前回の値を出し続けている CLI（07 U4）。成功するか前回の値を出さなくなったら消す。
    public private(set) var failures: [AgentKind: UsageFailure] = [:]

    /// 取得に失敗しても前回の値は出し続ける（07 U4）。スマホへは古さを伝えられないので取得できない扱いで送る（`syncedUsages`）。
    nonisolated static let defaultStalenessInterval: TimeInterval = .infinity
    private static let fastRefreshKinds = AgentRegistry.allDescriptors
        .filter { [.codex, .cursor].contains($0.usageProviderKind) }
        .map(\.kind)
    private static let slowRefreshKinds = AgentRegistry.allDescriptors
        .filter { $0.usageProviderKind == .claudeRateLimits }
        .map(\.kind)

    private let providers: [AgentKind: any UsageProvider]
    private let stalenessInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var lastSuccessfulUsages: [AgentKind: CLIUsage]
    public let claudeProcess: ClaudeUsageProcess?
    @ObservationIgnored private var claudeRefresh: ClaudeUsageRefresh?
    @ObservationIgnored private var settingsObserver: (any NSObjectProtocol)?

    public init(
        environment: AppEnvironment,
        connections: @escaping @MainActor () -> [ClaudeUsageConnection] = { [] }
    ) {
        self.providers = Self.makeProviders(environment: environment)
        self.stalenessInterval = Self.defaultStalenessInterval
        self.now = Date.init
        self.usages = [:]
        self.lastSuccessfulUsages = [:]
        let process = ClaudeUsageProcess(command: environment.claudeBinaryPath, environment: [
            "PATH": environment.pathEnvironment,
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(),
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
        ])
        self.claudeProcess = process
        self.claudeRefresh = ClaudeUsageRefresh(
            connections: connections, dedicated: process, closeDedicated: { await process.close() },
            cache: ClaudeUsageProvider(rateLimitsURL: environment.claudeUsageRateLimitsURL)
        ) { [weak self] usage, failure in
            self?.usages[.claudeCode] = usage
            self?.failures[.claudeCode] = failure.map { UsageFailure(reason: $0, at: Date()) }
        }
    }

    init(
        providers: [AgentKind: any UsageProvider],
        stalenessInterval: TimeInterval = defaultStalenessInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.providers = Dictionary(uniqueKeysWithValues: AgentRegistry.allDescriptors.map { descriptor in
            (descriptor.kind, providers[descriptor.kind] ?? EmptyUsageProvider(kind: descriptor.kind))
        })
        self.stalenessInterval = stalenessInterval
        self.now = now
        self.usages = [:]
        self.lastSuccessfulUsages = [:]
        self.claudeProcess = nil
    }

    public func start() {
        guard refreshTask == nil else { return }
        claudeRefresh?.start(enabled: Self.claudeEnabled, automatic: Self.autoRefreshEnabled)
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.usageSettingsChanged() }
        }
        refreshTask = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    public func stop() {
        claudeRefresh?.stop()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refresh(kinds: [AgentKind] = AgentKind.allCases) async {
        if kinds.contains(.claudeCode), let claudeRefresh { await claudeRefresh.refreshIfDue() }
        let selectedProviders = kinds.filter { $0 != .claudeCode || claudeRefresh == nil }.compactMap { providers[$0] }
        guard !selectedProviders.isEmpty else { return }

        let results = await withTaskGroup(of: CLIUsage.self, returning: [CLIUsage].self) { group in
            for provider in selectedProviders {
                group.addTask {
                    await provider.fetch()
                }
            }

            var usages: [CLIUsage] = []
            for await usage in group {
                usages.append(usage)
            }
            return usages
        }

        for usage in results {
            apply(usage)
        }
    }

    public func receiveClaudeUsage(_ snapshot: AgentRateLimitsSnapshot, from connectionID: UUID) {
        claudeRefresh?.receive(snapshot, from: connectionID)
    }

    public func claudeConnectionsChanged() { claudeRefresh?.connectionsChanged() }

    public func usageSettingsChanged() {
        claudeRefresh?.updateSettings(enabled: Self.claudeEnabled, automatic: Self.autoRefreshEnabled)
    }

    var currentDate: Date { now() }

    /// スマホへ送る値。前回の値を出し続けている CLI は、古さを伝えられないので取得できない扱いにする。
    public var syncedUsages: [AgentKind: CLIUsage] {
        usages.mapValues { usage in
            guard let failure = failures[usage.kind] else { return usage }
            return CLIUsage(kind: usage.kind, state: .unavailable(reason: failure.reason), updatedAt: failure.at)
        }
    }

    private func apply(_ usage: CLIUsage) {
        let kept = Self.resolvedUsage(
            incoming: usage,
            previousOK: lastSuccessfulUsages[usage.kind],
            now: now(),
            stalenessInterval: stalenessInterval
        )
        let resolved = Self.expiringPassedResets(in: kept, now: now())
        usages[usage.kind] = resolved
        if case .unavailable(let reason) = usage.state, case .ok = resolved.state {
            failures[usage.kind] = UsageFailure(reason: reason, at: now())
        } else {
            failures[usage.kind] = nil
        }
        // 0% に直す前の値を覚える。直した値を覚えると、次に失敗したときリセット済みと分からず「残り 100%」を出し続ける。
        if case .ok = kept.state {
            lastSuccessfulUsages[kept.kind] = kept
        }
    }

    /// Claudeの旧枠は不明にする。他エージェントの従来の扱いは維持する。
    nonisolated static func expiringPassedResets(in usage: CLIUsage, now: Date) -> CLIUsage {
        guard case let .ok(buckets) = usage.state else { return usage }
        if usage.kind == .claudeCode {
            let valid = buckets.filter { ClaudeUsageRefresh.isValid($0, now: now) }
            return CLIUsage(kind: usage.kind, state: valid.isEmpty ? .unavailable(reason: "Claude使用量は未取得です") : .ok(valid),
                            updatedAt: usage.updatedAt, dataAsOf: usage.dataAsOf)
        }
        let normalized = buckets.map { bucket in
            guard let resetsAt = bucket.resetsAt, resetsAt <= now else { return bucket }
            return UsageBucket(id: bucket.id, label: bucket.label, usedPercent: 0, resetsAt: nil)
        }
        return CLIUsage(
            kind: usage.kind,
            state: .ok(normalized),
            updatedAt: usage.updatedAt,
            dataAsOf: usage.dataAsOf
        )
    }

    nonisolated static func resolvedUsage(
        incoming: CLIUsage,
        previousOK: CLIUsage?,
        now: Date,
        stalenessInterval: TimeInterval
    ) -> CLIUsage {
        switch incoming.state {
        case .ok:
            incoming
        case .unavailable:
            // リセット時刻を過ぎたら前回の値は意味を失う（残り 100% と決めつけない）ので、取得の失敗をそのまま出す。
            if let previousOK,
               case .ok(let buckets) = previousOK.state,
               now.timeIntervalSince(previousOK.updatedAt) <= stalenessInterval,
               !buckets.contains(where: { ($0.resetsAt ?? .distantFuture) <= now }) {
                previousOK
            } else {
                incoming
            }
        }
    }

    private func runRefreshLoop() async {
        var codexCursorTick = 0
        // 自動更新がオフでも起動時に 1 回は取る（手動の更新はインスペクタごと廃止した。ADR 0192）。
        var isFirstPass = true

        while !Task.isCancelled {
            if isFirstPass || Self.autoRefreshEnabled {
                isFirstPass = false
                var kinds: [AgentKind] = []
                if codexCursorTick == 0 {
                    kinds.append(contentsOf: Self.fastRefreshKinds)
                }
                if claudeRefresh == nil { kinds.append(contentsOf: Self.slowRefreshKinds) }
                if !kinds.isEmpty {
                    await refresh(kinds: kinds)
                }
            }

            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            codexCursorTick = (codexCursorTick + 60) % 300
        }
    }

    private static var autoRefreshEnabled: Bool {
        let defaults = UserDefaults.phloxDefaults()
        guard defaults.object(forKey: "phlox.usage.autoRefresh") != nil else {
            return true
        }
        return defaults.bool(forKey: "phlox.usage.autoRefresh")
    }

    private static var claudeEnabled: Bool {
        UserDefaults.phloxDefaults().object(forKey: "phlox.usage.claudeScrape") as? Bool != false
    }

    private static func makeProviders(environment: AppEnvironment) -> [AgentKind: any UsageProvider] {
        Dictionary(uniqueKeysWithValues: AgentRegistry.allDescriptors.map { descriptor in
            (descriptor.kind, provider(for: descriptor, environment: environment))
        })
    }

    private static func provider(
        for descriptor: AgentDescriptor,
        environment: AppEnvironment
    ) -> any UsageProvider {
        switch descriptor.usageProviderKind {
        case .claudeRateLimits:
            return ClaudeUsageProvider(rateLimitsURL: environment.claudeUsageRateLimitsURL)
        case .codex:
            return CodexUsageProvider()
        case .cursor:
            return CursorUsageProvider()
        case .none:
            return EmptyUsageProvider(kind: descriptor.kind)
        }
    }
}

private struct EmptyUsageProvider: UsageProvider {
    let kind: AgentKind

    func fetch() async -> CLIUsage {
        CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "未設定")), updatedAt: Date())
    }
}

public struct UsageFailure: Equatable, Sendable {
    public let reason: String
    public let at: Date
}
