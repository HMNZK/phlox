import Testing
import AgentDomain
@testable import DesignSystemIOS

/// task-1 白箱テスト（実装役著）。DSSessionRow のブランド SVG バッジ差し替え契約を補強する。
@Suite @MainActor struct Task1SessionRowBrandArtworkTests {
    @Test func agentBadgeUsesBrandArtworkFlagIsTrue() {
        #expect(DSSessionRow.agentBadgeUsesBrandArtwork)
    }

    @Test func agentBadgeSizeTokensMatchCampAgentBadge() {
        #expect(DSSessionRow.agentBadgeSize == DSCampAgentBadge.sessionRowSize)
        #expect(DSSessionRow.agentBadgeCornerRadius == DSCampAgentBadge.sessionRowCornerRadius)
        #expect(DSSessionRow.agentBadgeSize == 38)
        #expect(DSSessionRow.agentBadgeCornerRadius == 10)
    }

    @Test func agentBadgeCornerRadiusMatchesDSAgentAvatarMapping() {
        #expect(
            DSAgentAvatar.cornerRadius(for: DSSessionRow.agentBadgeSize)
                == DSSessionRow.agentBadgeCornerRadius
        )
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func campAbbreviationRemainsPublicAPI(kind: AgentKind) {
        #expect(DSSessionRow.campAbbreviation(for: kind) == DSCampAgentBadge.abbreviation(for: kind))
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func sessionRowBadgeSizeSupportsBrandArtwork(kind: AgentKind) {
        #expect(DSAgentAvatar.usesBrandArtwork(for: kind))
        let avatar = DSAgentAvatar(kind: kind, size: DSSessionRow.agentBadgeSize)
        #expect(avatar.kind == kind)
        #expect(avatar.size == DSSessionRow.agentBadgeSize)
    }
}
