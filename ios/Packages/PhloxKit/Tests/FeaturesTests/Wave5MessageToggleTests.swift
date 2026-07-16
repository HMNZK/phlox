import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite struct Wave5MessageToggleTests {
    @Test func collapsibleMessagesStartCollapsed() {
        let viewModel = makeViewModel()

        #expect(!viewModel.isMessageExpanded("reasoning-1"))
        #expect(!viewModel.isMessageExpanded("command-1"))
        #expect(!viewModel.isMessageExpanded("file-change-1"))
    }

    @Test func toggleExpandsAndCollapsesPerMessageID() {
        let viewModel = makeViewModel()

        viewModel.toggleMessageExpansion("reasoning-1")
        #expect(viewModel.isMessageExpanded("reasoning-1"))

        viewModel.toggleMessageExpansion("command-1")
        #expect(viewModel.isMessageExpanded("command-1"))
        #expect(viewModel.isMessageExpanded("reasoning-1"))

        viewModel.toggleMessageExpansion("reasoning-1")
        #expect(!viewModel.isMessageExpanded("reasoning-1"))
        #expect(viewModel.isMessageExpanded("command-1"))
    }

    @Test func expansionStateSurvivesChatMessagesRefresh() async {
        let initial: [ChatMessage] = [
            .reasoning(id: "reasoning-1", text: "方針を整理"),
            .command(id: "command-1", command: "ls", output: "README.md"),
        ]
        let mock = MockAPI(messagesOutcome: .success(initial))
        await mock.setMessagesDeltaScript([
            .success(MessagesDelta(messages: initial, cursor: "cursor-1", isSnapshot: true)),
        ])
        let viewModel = makeViewModel(api: mock)
        await viewModel.load()

        viewModel.toggleMessageExpansion("reasoning-1")
        viewModel.toggleMessageExpansion("command-1")
        #expect(viewModel.isMessageExpanded("reasoning-1"))
        #expect(viewModel.isMessageExpanded("command-1"))

        let updated: [ChatMessage] = [
            .reasoning(id: "reasoning-1", text: "方針を整理（更新）"),
            .command(id: "command-1", command: "ls -la", output: "README.md\nsrc"),
            .agent(id: "agent-1", text: "完了"),
        ]
        await mock.setMessagesDeltaScript([
            .success(MessagesDelta(messages: updated, cursor: "cursor-2", isSnapshot: true)),
        ])
        await viewModel.refresh()

        #expect(viewModel.chatMessages.map(\.id) == ["reasoning-1", "command-1", "agent-1"])
        #expect(viewModel.isMessageExpanded("reasoning-1"))
        #expect(viewModel.isMessageExpanded("command-1"))
        #expect(!viewModel.isMessageExpanded("agent-1"))
    }

    @Test func userAndAgentMessagesAreNotCollapsible() {
        let user = ChatMessage.user(id: "user-1", text: "こんにちは")
        let agent = ChatMessage.agent(id: "agent-1", text: "はい")

        #expect(!SessionDetailViewModel.supportsMessageExpansionToggle(user))
        #expect(!SessionDetailViewModel.supportsMessageExpansionToggle(agent))
        #expect(SessionDetailViewModel.supportsMessageExpansionToggle(.reasoning(id: "r", text: "考え")))
        #expect(SessionDetailViewModel.supportsMessageExpansionToggle(.command(id: "c", command: "pwd", output: "")))
        #expect(
            SessionDetailViewModel.supportsMessageExpansionToggle(
                .fileChange(id: "f", changes: [ChatFileChange(path: "a.swift", diff: "+x")])
            )
        )
    }

    private func makeViewModel(api: MockAPI = MockAPI()) -> SessionDetailViewModel {
        SessionDetailViewModel(
            session: Session(
                id: "session-1",
                name: "Rose",
                agent: .claudeCode,
                status: .running,
                subtitle: "",
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            api: api
        )
    }
}
