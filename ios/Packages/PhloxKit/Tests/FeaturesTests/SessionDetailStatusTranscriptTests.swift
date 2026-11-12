import Foundation
import PhloxCore
import Testing
@testable import Features

@MainActor
struct SessionDetailStatusTranscriptTests {
    private func makeViewModel(api: MockAPI) -> SessionDetailViewModel {
        SessionDetailViewModel(session: Session(id: "s1", name: "Rose", agent: .claudeCode, status: .running,
            subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)), api: api)
    }

    private func projection(_ id: String) -> MobileStatusTranscript {
        MobileStatusTranscript(blocks: [.messages(ids: [id])])
    }

    @Test func initialLoadAndEmptyDeltaReplaceProjectionAndCarryCursor() async {
        let api = MockAPI()
        await api.setMessagesDeltaScript([
            .success(MessagesDelta(messages: [.agent(id: "answer", text: "回答")], cursor: "c1", isSnapshot: true,
                statusTranscript: projection("initial"))),
            .success(MessagesDelta(messages: [], cursor: "c2", isSnapshot: false, statusTranscript: projection("updated"))),
        ])
        let vm = makeViewModel(api: api)
        await vm.load()
        #expect(vm.chatMessages == [.agent(id: "answer", text: "回答")])
        #expect(vm.statusTranscript == projection("initial"))

        await vm.refresh()

        #expect(vm.chatMessages == [.agent(id: "answer", text: "回答")])
        #expect(vm.statusTranscript == projection("updated"))
        #expect(await api.deltaSinceLog == [nil, "c1"])
        #expect(await api.messagesCount == 0)
    }

    @Test func failedRefreshAndReloadKeepProjectionAndMessagesUntilSuccessfulSnapshot() async {
        let api = MockAPI()
        await api.setMessagesDeltaScript([
            .success(MessagesDelta(messages: [.agent(id: "old", text: "前の返答")], cursor: "c1", isSnapshot: true,
                statusTranscript: projection("old"))),
            .failure(.unreachable), .failure(.unreachable),
            .success(MessagesDelta(messages: [], cursor: "c0", isSnapshot: true, statusTranscript: MobileStatusTranscript(blocks: []))),
        ])
        let vm = makeViewModel(api: api)
        await vm.load()
        await vm.refresh()
        #expect(vm.statusTranscript == projection("old"))
        #expect(vm.chatMessages.map(\.id) == ["old"])

        await vm.load()
        #expect(vm.statusTranscript == projection("old"))
        #expect(vm.chatMessages.map(\.id) == ["old"])

        await vm.refresh()
        #expect(vm.statusTranscript == MobileStatusTranscript(blocks: []))
        #expect(vm.chatMessages.isEmpty)
    }

    @Test func oldMacAndSuccessfulFallbackClearProjectionWhileFailedFallbackKeepsIt() async {
        let api = MockAPI(messagesOutcome: .failure(.unreachable))
        await api.setMessagesDeltaScript([
            .success(MessagesDelta(messages: [.agent(id: "old", text: "返答")], cursor: "c1", isSnapshot: true,
                statusTranscript: projection("old"))),
            .failure(.notFound),
            .success(MessagesDelta(messages: [], cursor: "c2", isSnapshot: false)),
            .success(MessagesDelta(messages: [], cursor: "c3", isSnapshot: false, statusTranscript: projection("again"))),
            .failure(.server(status: 501, message: "old Mac")),
        ])
        let vm = makeViewModel(api: api)
        await vm.load()
        await vm.refresh()
        #expect(vm.statusTranscript == projection("old"))
        await vm.refresh()
        #expect(vm.statusTranscript == nil)
        await vm.refresh()
        #expect(vm.statusTranscript == projection("again"))
        await api.setMessagesOutcome(.success([]))
        await vm.refresh()
        #expect(vm.statusTranscript == nil)
        #expect(vm.chatMessages.isEmpty)
    }
}
