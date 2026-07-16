import AgentDomain
import Testing
@testable import DashboardFeature

// PM 著・凍結（task-1 契約）。アサーションを変更・弱体化しないこと。
// 新 API（AgentStartCardMode / AgentStartCardsModel.modes(for:)）をプロダクション側へ実装して green にする。

@Test func agentStartCardMode_backendMapping() {
    #expect(AgentStartCardMode.chat.backend == .appServer)
    #expect(AgentStartCardMode.terminal.backend == .pty)
}

@Test func agentStartCardModes_chatCapableAgent_offersChatThenTerminal() {
    let descriptor = AgentRegistry.descriptor(for: .claudeCode)
    #expect(descriptor.supportsStructuredChat)
    #expect(AgentStartCardsModel.modes(for: descriptor) == [.chat, .terminal])
}
