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

    @Test func sessionAndChatUseTheirSpecifiedLogoSizes() {
        #expect(DSSessionRow.agentLogoSize == 38)
        #expect(DSChatBubble.agentLogoSize == 28)
    }

    @Test func skeletonRowsUseTheSessionLogoSize() {
        #expect(DSSkeletonRow.agentLogoSize == DSSessionRow.agentLogoSize)
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func resolvesDescriptorViaAgentRegistry(kind: AgentKind) {
        let icon = AgentBrandIcon(kind: kind, size: DSSessionRow.agentLogoSize)
        #expect(icon.descriptor.displayName == AgentRegistry.descriptor(for: kind).displayName)
        #expect(icon.descriptor.displayName == kind.displayName)
    }

    @Test func brandArtworkLoadsFromTheDesignSystemBundle() {
        #expect(AgentBrandIcon.assetBundle.bundleURL != Bundle.main.bundleURL)
    }
}
