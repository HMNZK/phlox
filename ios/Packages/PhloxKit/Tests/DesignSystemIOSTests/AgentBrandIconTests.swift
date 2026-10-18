import Testing
import Foundation
import AgentDomain
@testable import DesignSystemIOS

@Suite @MainActor struct AgentBrandIconTests {
    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func builtinsResolveTheirSharedDescriptors(kind: AgentKind) {
        let icon = AgentBrandIcon(kind: kind, size: 38)
        #expect(icon.descriptor.displayName == AgentRegistry.descriptor(for: kind).displayName)
        #expect(icon.size == 38)
        #expect(AgentBrandIcon.assetBundle.bundleURL != Bundle.main.bundleURL)
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func resolvesDescriptorViaAgentRegistry(kind: AgentKind) {
        let icon = AgentBrandIcon(kind: kind, size: 24)
        #expect(icon.descriptor.displayName == AgentRegistry.descriptor(for: kind).displayName)
        #expect(icon.descriptor.displayName == kind.displayName)
    }

    @Test func brandArtworkLoadsFromTheDesignSystemBundle() {
        #expect(AgentBrandIcon.assetBundle.bundleURL != Bundle.main.bundleURL)
    }
}
