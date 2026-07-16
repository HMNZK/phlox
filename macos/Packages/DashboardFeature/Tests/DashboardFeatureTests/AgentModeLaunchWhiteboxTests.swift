import AgentDomain
import Testing
@testable import DashboardFeature

@Test func agentStartCardModes_nonChatCapableAgent_offersTerminalOnly() {
    let descriptor = makeCustomAgentDescriptor()
    #expect(!descriptor.supportsStructuredChat)
    #expect(AgentStartCardsModel.modes(for: descriptor) == [.terminal])
}

@Test func agentStartCardModes_builtinCodex_offersChatAndTerminal() {
    let descriptor = AgentRegistry.descriptor(for: .codex)
    #expect(descriptor.supportsStructuredChat)
    #expect(AgentStartCardsModel.modes(for: descriptor) == [.chat, .terminal])
}
