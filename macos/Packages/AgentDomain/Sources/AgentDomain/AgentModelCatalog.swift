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
    // Claude Code `/model` picker order (v2.1.261, observed 2026-09-05). The non-interactive
    // `/model` report also lists internal aliases, so it cannot be used as the picker itself.
    private static let claudeModels = [
        ControlModelOption(id: "default", displayName: "Default (recommended) — Opus 5 (1M context)"),
        ControlModelOption(id: "opus[1m]", displayName: "Opus 5 (1M context)"),
        ControlModelOption(id: "fable", displayName: "Fable 5.1"),
        ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
        ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
    ]
    // Current families from `codex app-server` model/list (2026-09-05). Keep the live order
    // so the first model remains Codex's current default when discovery is unavailable.
    private static let codexModels = [
        "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
    ].map {
        ControlModelOption(id: $0, displayName: $0)
    }
    // Cursor Agent `/model` picker order (v2026.09.02, observed 2026-09-05). The scriptable
    // `models` command expands these 35 families into roughly 170 parameter combinations;
    // exposing those IDs would not match Cursor's own picker.
    private static let cursorModels = [
        ControlModelOption(id: "auto", displayName: "Auto"),
        ControlModelOption(id: "grok-4.6", displayName: "Cursor Grok 4.6"),
        ControlModelOption(id: "composer-2.5", displayName: "Composer 2.5"),
        ControlModelOption(id: "claude-opus-5", displayName: "Claude Opus 5"),
        ControlModelOption(id: "claude-opus-4-8", displayName: "Claude Opus 4.8"),
        ControlModelOption(id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol"),
        ControlModelOption(id: "gpt-5.5", displayName: "GPT-5.5"),
        ControlModelOption(id: "claude-fable-5-1", displayName: "Claude Fable 5.1"),
        ControlModelOption(id: "claude-fable-5", displayName: "Claude Fable 5"),
        ControlModelOption(id: "gemini-3.8-flash", displayName: "Gemini 3.8 Flash"),
        ControlModelOption(id: "gemini-3.7-flash", displayName: "Gemini 3.7 Flash"),
        ControlModelOption(id: "gpt-5.6-terra", displayName: "GPT-5.6 Terra"),
        ControlModelOption(id: "claude-sonnet-5", displayName: "Claude Sonnet 5"),
        ControlModelOption(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
        ControlModelOption(id: "gpt-5.3-codex", displayName: "Codex 5.3"),
        ControlModelOption(id: "claude-opus-4-7", displayName: "Claude Opus 4.7"),
        ControlModelOption(id: "gpt-5.4", displayName: "GPT-5.4"),
        ControlModelOption(id: "claude-opus-4-6", displayName: "Claude Opus 4.6"),
        ControlModelOption(id: "claude-opus-4-5", displayName: "Claude Opus 4.5"),
        ControlModelOption(id: "gpt-5.2", displayName: "GPT-5.2"),
        ControlModelOption(id: "gpt-5.6-luna", displayName: "GPT-5.6 Luna"),
        ControlModelOption(id: "gemini-3.6-flash", displayName: "Gemini 3.6 Flash"),
        ControlModelOption(id: "gemini-3.1-pro", displayName: "Gemini 3.1 Pro"),
        ControlModelOption(id: "gpt-5.4-mini", displayName: "GPT-5.4 Mini"),
        ControlModelOption(id: "gpt-5.4-nano", displayName: "GPT-5.4 Nano"),
        ControlModelOption(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
        ControlModelOption(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
        ControlModelOption(id: "gpt-5.1", displayName: "GPT-5.1"),
        ControlModelOption(id: "gemini-3-flash", displayName: "Gemini 3 Flash"),
        ControlModelOption(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
        ControlModelOption(id: "claude-sonnet-4", displayName: "Claude Sonnet 4"),
        ControlModelOption(id: "gpt-5-mini", displayName: "GPT-5 Mini"),
        ControlModelOption(id: "kimi-k3", displayName: "Kimi K3"),
        ControlModelOption(id: "kimi-k2.7-code", displayName: "Kimi K2.7 Code"),
        ControlModelOption(id: "glm-5.2", displayName: "GLM 5.2"),
    ]
    private static let state = State()

    public static func models(for kind: AgentKind) -> [ControlModelOption] {
        state.lock.withLock { state.snapshots[kind] ?? builtinModels(for: kind) }
    }

    public static func builtinModels(for kind: AgentKind) -> [ControlModelOption] {
        switch kind {
        case .claudeCode: claudeModels
        case .codex: codexModels
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
        // Prefer Claude's interactive `default`, and preserve Cursor's established
        // `composer-2.5` default when it is available. This avoids letting CLI ordering make
        // the API select Cursor's leading `auto` while the macOS UI selects composer-2.5.
        // When either preferred ID is absent, use the CLI's first available model.
        let preferred: String? = switch kind {
        case .claudeCode: "default"
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
