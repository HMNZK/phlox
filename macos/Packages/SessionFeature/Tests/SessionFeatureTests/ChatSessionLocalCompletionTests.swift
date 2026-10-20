import Foundation
import Testing
import AgentDomain
import StructuredChatKit
import CodexAppServerKit
@testable import SessionFeature

private actor LocalCompletionClient: StructuredAgentClient, CodexOrderedEventsProviding {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let orderedEvents: AsyncStream<CodexStructuredEvent>
    nonisolated let continuation: AsyncStream<CodexStructuredEvent>.Continuation
    private let normalizedContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    let rejectsSend: Bool
    enum Rejected: Error { case send }

    init(rejectsSend: Bool = false) {
        self.rejectsSend = rejectsSend
        (events, normalizedContinuation) = AsyncStream.makeStream()
        (orderedEvents, continuation) = AsyncStream.makeStream()
    }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        if rejectsSend { throw Rejected.send }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish(); normalizedContinuation.finish() }
}

@Suite @MainActor struct ChatSessionLocalCompletionTests {
    @Test func firstCompletionWithoutStartedEventIsUnreadLikeSecondCompletion() async throws {
        let (vm, client, root) = try await fixture()
        for turn in 1...2 {
            try await vm.sendText("指示\(turn)", submit: true)
            // 実サーバーの初回ログ: active → idle → completed。turnStartedだけが来ない。
            if turn == 2 { client.continuation.yield(.normalized(.turnStarted)) }
            client.continuation.yield(.thread(.threadStatusChanged(
                threadId: "restored-chat", status: .active(flags: [])
            )))
            client.continuation.yield(.thread(.threadStatusChanged(threadId: "restored-chat", status: .idle)))
            client.continuation.yield(.normalized(.turnCompleted(nativeSessionId: "restored-chat")))
            try await waitUntil { vm.completedTurnSeq == turn }
            #expect(vm.status == .idle)
            #expect(vm.hasUnseenCompletion, "第\(turn)回の指示の完了を表示する")
            vm.markCompletionSeen()
        }
        await vm.terminate()
        try FileManager.default.removeItem(at: root)
    }

    @Test func replayWithoutASubmittedInstructionDoesNotCreateUnreadCompletion() async throws {
        let (vm, client, root) = try await fixture()
        client.continuation.yield(.thread(.threadStatusChanged(threadId: "restored-chat", status: .idle)))
        client.continuation.yield(.normalized(.turnCompleted(nativeSessionId: "restored-chat")))
        try await waitUntil { vm.completedTurnSeq == 1 }
        #expect(!vm.hasUnseenCompletion)
        await vm.terminate()
        try FileManager.default.removeItem(at: root)
    }

    @Test func rejectedSendDoesNotLeaveAnActiveTurnForLateEvents() async throws {
        let (vm, client, root) = try await fixture(rejectsSend: true)
        await #expect(throws: LocalCompletionClient.Rejected.self) {
            try await vm.sendText("送信に失敗する指示", submit: true)
        }
        client.continuation.yield(.thread(.threadStatusChanged(
            threadId: "restored-chat", status: .active(flags: [])
        )))
        client.continuation.yield(.thread(.threadStatusChanged(threadId: "restored-chat", status: .idle)))
        client.continuation.yield(.normalized(.turnCompleted(nativeSessionId: "restored-chat")))
        try await waitUntil { vm.completedTurnSeq == 1 }
        #expect(!vm.hasUnseenCompletion)
        await vm.terminate()
        try FileManager.default.removeItem(at: root)
    }

    private enum WaitError: Error { case timedOut }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func fixture(rejectsSend: Bool = false) async throws -> (ChatSessionViewModel, LocalCompletionClient, URL) {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".verification/live-completion-trace/test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let client = LocalCompletionClient(rejectsSend: rejectsSend)
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path)
        await vm.restore(threadId: "restored-chat", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        return (vm, client, root)
    }
}
