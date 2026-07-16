import Foundation
import AgentDomain

public enum CodexUserHooksSettings {
    public static let enabledKey = "phlox.codexUserHooks.enabled"

    public static var defaultsDictionary: [String: Any] {
        [enabledKey: false]
    }

    public static func isEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    public static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .phloxDefaults()) {
        defaults.set(enabled, forKey: enabledKey)
    }
}
