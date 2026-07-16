import Testing
import AgentDomain
@testable import DesignSystemIOS

/// task-1 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-1.md）。
/// 契約: セッション一覧行（DSSessionRow）のエージェントバッジはテキスト略号ではなく
/// ブランド SVG（DSAgentAvatar）で描画される。
@Suite struct Task1AcceptanceTests {
    @Test func sessionRowAgentBadgeUsesBrandArtwork() {
        #expect(DSSessionRow.agentBadgeUsesBrandArtwork)
    }

    /// 前提の不変条件: 3 ビルトインすべてにブランド SVG が存在する。
    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func brandArtworkAvailable(for kind: AgentKind) {
        #expect(DSAgentAvatar.usesBrandArtwork(for: kind))
    }

    /// 不変条件: バッジ寸法・角丸トークンは現状維持（38 / 10）。
    @Test func sessionRowBadgeDimensionsUnchanged() {
        #expect(DSSessionRow.agentBadgeSize == 38)
        #expect(DSSessionRow.agentBadgeCornerRadius == 10)
        #expect(DSAgentAvatar.cornerRadius(for: DSSessionRow.agentBadgeSize) == 10)
    }
}
