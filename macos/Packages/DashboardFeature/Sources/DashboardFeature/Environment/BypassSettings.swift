import Foundation
import AgentDomain

public enum BypassSettings {
    public static let claudeCodeKey = AgentRegistry.descriptor(for: .claudeCode).bypassKey
    public static let codexKey = AgentRegistry.descriptor(for: .codex).bypassKey
    public static let cursorKey = AgentRegistry.descriptor(for: .cursor).bypassKey

    public static var defaultsDictionary: [String: Any] {
        Dictionary(uniqueKeysWithValues: AgentRegistry.allDescriptors.map { ($0.bypassKey, true) })
    }

    public static func isEnabled(
        for kind: AgentKind,
        defaults: UserDefaults = .phloxDefaults()
    ) -> Bool {
        isEnabled(for: key(for: kind), defaults: defaults)
    }

    public static func isEnabled(
        for ref: AgentRef,
        defaults: UserDefaults = .phloxDefaults()
    ) -> Bool {
        isEnabled(for: key(for: ref), defaults: defaults)
    }

    private static func isEnabled(for key: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    public static func key(for kind: AgentKind) -> String {
        AgentRegistry.descriptor(for: kind).bypassKey
    }

    public static func key(for ref: AgentRef) -> String {
        switch ref { case .builtin(let kind): key(for: kind) }
    }
}
