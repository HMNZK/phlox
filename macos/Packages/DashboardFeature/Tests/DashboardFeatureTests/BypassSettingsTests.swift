import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Test func bypassSettings_builtinRefDefaultsTrueAndUsesBuiltinKey() {
    let suiteName = "BypassSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let ref = AgentRef.builtin(.cursor)
    let key = AgentRegistry.descriptor(for: .cursor).bypassKey

    #expect(BypassSettings.key(for: ref) == key)
    #expect(BypassSettings.isEnabled(for: ref, defaults: defaults) == true)

    defaults.set(false, forKey: key)

    #expect(BypassSettings.isEnabled(for: ref, defaults: defaults) == false)
}
