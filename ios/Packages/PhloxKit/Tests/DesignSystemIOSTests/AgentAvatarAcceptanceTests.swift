import Testing
import AgentDomain
@testable import DesignSystemIOS

/// task-6 受け入れテスト（PM 著・実装役は編集禁止）。
/// エージェントアバターのパリティ: テキスト略号（"CC"/"Cx"/"Cu"）ではなく、
/// Phlox 本体と同じ SVG ブランドロゴ（AgentBrandIcon のアセット）で描画する。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
struct AgentAvatarAcceptanceTests {
    @Test("ビルトイン3エージェントはブランド SVG アートワークで描画される")
    func builtinsUseBrandArtwork() {
        #expect(DSAgentAvatar.usesBrandArtwork(for: .claudeCode))
        #expect(DSAgentAvatar.usesBrandArtwork(for: .codex))
        #expect(DSAgentAvatar.usesBrandArtwork(for: .cursor))
    }
}
