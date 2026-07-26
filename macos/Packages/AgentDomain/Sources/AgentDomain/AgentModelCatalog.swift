import Foundation
import os

/// A selectable agent model shared by the control API and macOS UI.
/// Codable's synthesized keys deliberately remain the frozen `id` / `displayName` wire shape.
public struct ControlModelOption: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// Supplies an agent's current model list. Implementations may run CLI or JSON-RPC work;
/// callers publish the result into `AgentModelCatalog` rather than doing that work on a
/// request handler's synchronous path.
public protocol AgentModelListProviding: Sendable {
    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption]
}

/// Process-wide, synchronously readable model snapshot. It belongs in AgentDomain because
/// both the HTTP server and UI consume the same catalog without either depending on the other.
public enum AgentModelCatalog {
    private static let logger = Logger(subsystem: "com.phlox.Phlox", category: "AgentModelCatalog")
    private static let claudeModels = [
        ControlModelOption(id: "opus", displayName: "Opus 4.8"),
        ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
        ControlModelOption(id: "fable", displayName: "Fable 5"),
        ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
    ]
    // `cursor-agent models` (2026-07-26) lists these current, representative selectable IDs.
    // Keep `composer-2.5` so the shared default rule can preserve Cursor's established
    // default; retain current Codex and Claude families as offline choices. Deliberately
    // exclude `auto`: it is Cursor's routing mode, not a stable explicit model fallback.
    private static let cursorModels = ["composer-2.5", "gpt-5.3-codex", "claude-opus-5-high"].map {
        ControlModelOption(id: $0, displayName: $0)
    }
    private static let state = State()

    public static func models(for kind: AgentKind) -> [ControlModelOption] {
        state.lock.withLock { state.snapshots[kind] ?? builtinModels(for: kind) }
    }

    public static func builtinModels(for kind: AgentKind) -> [ControlModelOption] {
        switch kind {
        case .claudeCode: claudeModels
        case .codex: []
        case .cursor: cursorModels
        }
    }

    public static func configure(provider: (any AgentModelListProviding)?) {
        state.lock.withLock {
            // Reconfiguration deliberately preserves the last completed snapshot. Synchronous
            // readers must never briefly lose a usable catalog while a live source is replaced.
            state.provider = provider
            state.generation += 1
        }
    }

    public static func refresh() async {
        let configuration = state.lock.withLock { (state.provider, state.generation) }
        guard let provider = configuration.0 else { return }
        var refreshed: [AgentKind: [ControlModelOption]] = [:]
        var failures = Set<AgentKind>()
        for kind in AgentKind.allCases {
            do {
                refreshed[kind] = try await provider.fetchModels(for: kind)
            } catch {
                refreshed[kind] = builtinModels(for: kind)
                failures.insert(kind)
                logger.error("Live model refresh failed for \(kind.rawValue, privacy: .public); using built-in fallback: \(error.localizedDescription, privacy: .public)")
            }
        }
        state.lock.withLock {
            // Do not publish a stale result from a provider replaced during this refresh.
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
        // This is the sole default-selection rule for both the control API and macOS UI.
        // Prefer the user-selected Claude default `opus`, and preserve Cursor's established
        // `composer-2.5` default when it is available. This avoids letting CLI ordering make
        // the API select Cursor's leading `auto` while the macOS UI selects composer-2.5.
        // When either preferred ID is absent, use the CLI's first available model.
        let preferred: String? = switch kind {
        case .claudeCode: "opus"
        case .cursor: "composer-2.5"
        case .codex: nil
        }
        if let preferred, models.contains(where: { $0.id == preferred }) {
            return preferred
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
