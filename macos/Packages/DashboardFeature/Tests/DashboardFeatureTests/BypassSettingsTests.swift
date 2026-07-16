import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Test func bypassSettings_customRefDefaultsTrueAndUsesCustomKey() {
    let suiteName = "BypassSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let descriptor = AgentDescriptor(
        ref: .custom("aider"),
        displayName: "Aider",
        binaryName: "aider",
        symbolName: "wrench.and.screwdriver",
        colorRGB: AgentRGB(0xE5, 0xA5, 0x3F),
        bypassKey: "phlox.bypass.aider",
        launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
    )
    let catalog = AgentCatalog(customDescriptors: [descriptor])

    #expect(BypassSettings.key(for: .custom("aider"), catalog: catalog) == "phlox.bypass.aider")
    #expect(BypassSettings.isEnabled(for: .custom("aider"), catalog: catalog, defaults: defaults) == true)

    defaults.set(false, forKey: "phlox.bypass.aider")

    #expect(BypassSettings.isEnabled(for: .custom("aider"), catalog: catalog, defaults: defaults) == false)
}
