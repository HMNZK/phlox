import Testing
import AgentDomain
@testable import DesignSystemIOS

/// 表示名が共有ブランドアイコンのレジストリと一致することを検証する。
@MainActor
struct AgentAvatarAcceptanceTests {
    @Test("ビルトイン3エージェントの表示名は共有ブランドアイコンと揃う")
    func builtinAgentNamesUseSharedBrandIcons() {
        #expect(AgentBrandIcon(kind: .claudeCode, size: 38).descriptor.displayName == "Claude Code")
        #expect(AgentBrandIcon(kind: .codex, size: 38).descriptor.displayName == "Codex")
        #expect(AgentBrandIcon(kind: .cursor, size: 38).descriptor.displayName == "Cursor")
    }
}
