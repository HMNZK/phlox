import AgentDomain
import Testing
@testable import DashboardFeature

// エージェント選択カードの起動モード（チャット / ターミナル）。
// AgentStartCardMode が起動バックエンドへ写像され、chat 対応エージェントは [chat, terminal]、
// 非対応エージェントはターミナルのみを提示する。

@Test func agentStartCardMode_backendMapping() {
    #expect(AgentStartCardMode.chat.backend == .appServer)
    #expect(AgentStartCardMode.terminal.backend == .pty)
}

@Test func agentStartCardModes_chatCapableAgent_offersChatThenTerminal() {
    let descriptor = AgentRegistry.descriptor(for: .claudeCode)
    #expect(descriptor.supportsStructuredChat)
    #expect(AgentStartCardsModel.modes(for: descriptor) == [.chat, .terminal])
}

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
