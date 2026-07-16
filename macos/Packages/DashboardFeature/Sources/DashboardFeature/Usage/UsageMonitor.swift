import AgentDomain
import Foundation
import Observation
import StructuredChatKit

@MainActor
@Observable
public final class UsageMonitor {
    public private(set) var usages: [AgentKind: CLIUsage]
    public private(set) var lastRefreshedAt: Date?
    public private(set) var isRefreshing: Bool

    private static let defaultStalenessInterval: TimeInterval = 300
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

    public init(
        environment: AppEnvironment,
        sessions: @escaping @Sendable () async -> [any UsageQuerying] = { [] }
    ) {
        self.providers = Self.makeProviders(environment: environment, sessions: sessions)
        self.stalenessInterval = Self.defaultStalenessInterval
        self.now = Date.init
        self.usages = [:]
        self.lastSuccessfulUsages = [:]
        self.lastRefreshedAt = nil
        self.isRefreshing = false
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
        self.lastRefreshedAt = nil
        self.isRefreshing = false
    }

    public func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refresh(kinds: [AgentKind] = AgentKind.allCases) async {
        let selectedProviders = kinds.compactMap { providers[$0] }
        guard !selectedProviders.isEmpty else { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshedAt = Date()
        }

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

    private func apply(_ usage: CLIUsage) {
        let resolved = Self.expiringPassedResets(
            in: Self.resolvedUsage(
                incoming: usage,
                previousOK: lastSuccessfulUsages[usage.kind],
                now: now(),
                stalenessInterval: stalenessInterval
            ),
            now: now()
        )
        usages[usage.kind] = resolved
        if case .ok = resolved.state {
            lastSuccessfulUsages[resolved.kind] = resolved
        }
    }

    /// リセット時刻を過ぎたバケットは旧ウィンドウの値なので、使用 0%(残り100%)に正規化する。
    /// 新ウィンドウのリセット時刻は次の取得まで不明なため nil にする。
    nonisolated static func expiringPassedResets(in usage: CLIUsage, now: Date) -> CLIUsage {
        guard case let .ok(buckets) = usage.state else { return usage }
        let normalized = buckets.map { bucket in
            guard let resetsAt = bucket.resetsAt, resetsAt <= now else { return bucket }
            return UsageBucket(id: bucket.id, label: bucket.label, usedPercent: 0, resetsAt: nil)
        }
        return CLIUsage(
            kind: usage.kind,
            state: .ok(normalized),
            updatedAt: usage.updatedAt,
            action: usage.action,
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
            if let previousOK,
               case .ok = previousOK.state,
               now.timeIntervalSince(previousOK.updatedAt) <= stalenessInterval {
                previousOK
            } else {
                incoming
            }
        }
    }

    private func runRefreshLoop() async {
        var codexCursorTick = 0
        var claudeTick = 0

        while !Task.isCancelled {
            if Self.autoRefreshEnabled {
                var kinds: [AgentKind] = []
                if codexCursorTick == 0 {
                    kinds.append(contentsOf: Self.fastRefreshKinds)
                }
                if claudeTick == 0 {
                    kinds.append(contentsOf: Self.slowRefreshKinds)
                }
                if !kinds.isEmpty {
                    await refresh(kinds: kinds)
                }
            }

            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }

            codexCursorTick = 0
            claudeTick = (claudeTick + 60) % 300
        }
    }

    private static var autoRefreshEnabled: Bool {
        let defaults = UserDefaults.phloxDefaults()
        guard defaults.object(forKey: "phlox.usage.autoRefresh") != nil else {
            return true
        }
        return defaults.bool(forKey: "phlox.usage.autoRefresh")
    }

    private static func makeProviders(
        environment: AppEnvironment,
        sessions: @escaping @Sendable () async -> [any UsageQuerying]
    ) -> [AgentKind: any UsageProvider] {
        Dictionary(uniqueKeysWithValues: AgentRegistry.allDescriptors.map { descriptor in
            (descriptor.kind, provider(for: descriptor, environment: environment, sessions: sessions))
        })
    }

    private static func provider(
        for descriptor: AgentDescriptor,
        environment: AppEnvironment,
        sessions: @escaping @Sendable () async -> [any UsageQuerying]
    ) -> any UsageProvider {
        switch descriptor.usageProviderKind {
        case .claudeRateLimits:
            return ClaudeChatUsageSource(
                sessions: sessions,
                fallback: ClaudeUsageProvider(rateLimitsURL: environment.claudeUsageRateLimitsURL)
            )
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
