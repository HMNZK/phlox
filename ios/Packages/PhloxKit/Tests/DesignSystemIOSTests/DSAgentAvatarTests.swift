import Testing
import CoreGraphics
import AgentDomain
@testable import DesignSystemIOS

@Suite @MainActor struct DSAgentAvatarTests {
    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func usesBrandArtworkForBuiltins(kind: AgentKind) {
        #expect(DSAgentAvatar.usesBrandArtwork(for: kind))
    }

    @Test func cornerRadiusMatchesCampAgentBadgeAtKnownSizes() {
        #expect(DSAgentAvatar.cornerRadius(for: DSCampAgentBadge.sessionRowSize) == DSCampAgentBadge.sessionRowCornerRadius)
        #expect(DSAgentAvatar.cornerRadius(for: DSCampAgentBadge.chatAvatarSize) == DSCampAgentBadge.chatAvatarCornerRadius)
    }

    @Test func cornerRadiusScalesFromSessionRowRatioForUnknownSizes() {
        let size: CGFloat = 48
        let expected = size * (DSCampAgentBadge.sessionRowCornerRadius / DSCampAgentBadge.sessionRowSize)
        #expect(DSAgentAvatar.cornerRadius(for: size) == expected)
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func resolvesDescriptorViaAgentRegistry(kind: AgentKind) {
        let avatar = DSAgentAvatar(kind: kind, size: DSCampAgentBadge.sessionRowSize)
        #expect(avatar.kind == kind)
        #expect(AgentRegistry.descriptor(for: kind).displayName == kind.displayName)
    }

    @Test func brandIconScaleIsLessThanBadgeSize() {
        #expect(DSAgentAvatar.brandIconScale > 0)
        #expect(DSAgentAvatar.brandIconScale < 1)
    }
}
