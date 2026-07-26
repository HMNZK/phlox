import AgentDomain
import Foundation
import os

public enum AgentModelCatalog {
    private static let logger = Logger(subsystem: "com.phlox.Phlox", category: "AgentModelCatalog")
    private static let claudeModels = [
        ControlModelOption(id: "opus", displayName: "Opus 4.8"),
        ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
        ControlModelOption(id: "fable", displayName: "Fable 5"),
        ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
    ]

    private static let cursorModels = ["gpt-5", "sonnet-4.5", "opus-4.1"].map {
        ControlModelOption(id: $0, displayName: $0)
    }

    private static let state = State()

    public static func models(for kind: AgentKind) -> [ControlModelOption] {
        state.lock.withLock { state.snapshots[kind] ?? builtinModels(for: kind) }
    }

    public static func builtinModels(for kind: AgentKind) -> [ControlModelOption] {
        switch kind {
        case .claudeCode:
            claudeModels
        case .codex:
            []
        case .cursor:
            cursorModels
        }
    }

    /// Registers the live source. Clearing it stops future refreshes but deliberately
    /// retains the last completed snapshot: synchronous readers must never briefly lose
    /// their usable catalog while a provider is being reconfigured.
    public static func configure(provider: (any AgentModelListProviding)?) {
        state.lock.withLock {
            state.provider = provider
            state.generation += 1
        }
    }

    /// Refreshes off the synchronous request path. Failures are emitted to the unified
    /// log and leave that kind on its built-in fallback; an empty successful response is
    /// kept as an intentional live catalog (not silently replaced).
    public static func refresh() async {
        let configuration = state.lock.withLock { (state.provider, state.generation) }
        let configuredProvider = configuration.0
        guard let configuredProvider else { return }

        var refreshed: [AgentKind: [ControlModelOption]] = [:]
        var failures = Set<AgentKind>()
        for kind in AgentKind.allCases {
            do {
                refreshed[kind] = try await configuredProvider.fetchModels(for: kind)
            } catch {
                refreshed[kind] = builtinModels(for: kind)
                failures.insert(kind)
                logger.error("Live model refresh failed for \(kind.rawValue, privacy: .public); using built-in fallback: \(String(describing: error), privacy: .public)")
            }
        }
        state.lock.withLock {
            // Do not publish a stale response from a provider that was replaced while
            // this asynchronous refresh was in flight.
            guard state.provider != nil, state.generation == configuration.1 else { return }
            state.snapshots = refreshed
            state.fallbackKinds = failures
        }
    }

    public static func kindsUsingFallback() -> Set<AgentKind> {
        state.lock.withLock { state.fallbackKinds }
    }

    public static func defaultModel(for kind: AgentKind) -> String? {
        let models = models(for: kind)
        // Claude's documented and historical default is sonnet. Keep that choice stable
        // when a live refresh fails and falls back to the built-in list.
        if kind == .claudeCode, models.contains(where: { $0.id == "sonnet" }) {
            return "sonnet"
        }
        return models.first?.id
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var provider: (any AgentModelListProviding)?
        var snapshots: [AgentKind: [ControlModelOption]] = [:]
        var fallbackKinds: Set<AgentKind> = []
        var generation = 0
    }
}
