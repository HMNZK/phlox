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
        isEnabled(for: .builtin(kind), catalog: .builtins, defaults: defaults)
    }

    public static func isEnabled(
        for ref: AgentRef,
        catalog: AgentCatalog,
        defaults: UserDefaults = .phloxDefaults()
    ) -> Bool {
        let key = key(for: ref, catalog: catalog)
        guard defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    public static func key(for kind: AgentKind) -> String {
        AgentRegistry.descriptor(for: kind).bypassKey
    }

    public static func key(for ref: AgentRef, catalog: AgentCatalog) -> String {
        catalog.descriptor(for: ref)?.bypassKey ?? "phlox.bypass.\(ref.id)"
    }
}
