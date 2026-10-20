import Foundation
import Testing
import AgentDomain
import StructuredChatKit
import CodexAppServerKit
@testable import SessionFeature

private actor TranscriptOrderClient: StructuredAgentClient, CodexOrderedEventsProviding {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let orderedEvents: AsyncStream<CodexStructuredEvent>
    nonisolated let continuation: AsyncStream<CodexStructuredEvent>.Continuation
    private let normalizedContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let holdsResume: Bool
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    init(holdsResume: Bool = false) {
        self.holdsResume = holdsResume
        (events, normalizedContinuation) = AsyncStream.makeStream()
        (orderedEvents, continuation) = AsyncStream.makeStream()
    }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {
        if holdsResume {
            await withCheckedContinuation { resumeWaiter = $0 }
        }
    }
    func releaseResume() { resumeWaiter?.resume(); resumeWaiter = nil }
    var resumeIsPending: Bool { resumeWaiter != nil }
    func interrupt() async throws {}
    func close() async { continuation.finish(); normalizedContinuation.finish() }
}

@Suite @MainActor struct CodexTranscriptOrderTests {
    @Test func midTurnAndRestartPreserveStartedOrderAndCompletedSummary() async throws {
        let (vm, client, store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        client.continuation.yield(.normalized(.turnStarted))
        client.continuation.yield(.normalized(.reasoningDelta(itemId: "thought", "**First****Second**")))
        client.continuation.yield(.thread(.itemStarted(threadId: "thread", turnId: "turn", item: try item(
            #"{"id":"answer","type":"agentMessage","text":"Partial"}"#))))
        client.continuation.yield(.thread(.itemCompleted(threadId: "thread", turnId: "turn", item: try item(
            #"{"id":"command","type":"commandExecution","command":"pwd","aggregatedOutput":"ok"}"#))))
        try await waitUntil { vm.transcript.contains { $0.id == "command" } }
        let deadline = ContinuousClock.now + .seconds(2)
        while !(try await store.loadTranscript(for: vm.id).contains { $0.id == "command" }) {
            guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try await store.loadTranscript(for: vm.id).map(\.id) == ["thought", "answer", "command"])

        client.continuation.yield(.thread(.itemCompleted(threadId: "thread", turnId: "turn", item: try item(
            #"{"id":"answer","type":"agentMessage","text":"Done"}"#))))
        client.continuation.yield(.thread(.itemCompleted(threadId: "thread", turnId: "turn", item: try item(
            #"{"id":"thought","type":"reasoning","summary":["**First**","", "**Second**", "**Second**"]}"#))))
        client.continuation.yield(.normalized(.turnCompleted(nativeSessionId: "thread")))
        try await waitUntil { vm.completedTurnSeq == 1 }
        await vm.flushTranscriptNow()
        let persisted = try await store.loadTranscript(for: vm.id)
        #expect(persisted.map(\.id) == ["thought", "answer", "command"])
        guard case .reasoning(_, let text, _) = try #require(persisted.first { $0.id == "thought" }) else {
            Issue.record("The reasoning output must survive restart")
            return
        }
        #expect(text == "**First**\n\n**Second**\n\n**Second**")
        let restored = ChatSessionViewModel(id: vm.id, agentRef: .builtin(.codex), client: TranscriptOrderClient(),
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path, transcriptStore: store)
        await restored.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        #expect(restored.transcript == vm.transcript)
        await restored.terminate()
        await vm.terminate()
    }

    @Test func failedRestoreDoesNotReplaceSavedHistoryWithAnError() async throws {
        let (vm, _, store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = ChatItem.agentMessage(id: "saved", text: "Keep", timestamp: Date())
        try await store.replaceTranscript(for: vm.id, with: [original])
        let display = ChatDisplayState(turnUsageByItemID: [:], lastTurnCompletedAt: Date(timeIntervalSince1970: 123), subAgents: [])
        try await store.saveDisplayState(display, for: vm.id)
        vm.markRestoreFailed("Failed")
        await vm.flushTranscriptNow()
        #expect(try await store.loadTranscript(for: vm.id) == [original])
        #expect(try await store.loadDisplayState(for: vm.id) == display)
        await vm.terminate()
    }

    @Test func incompleteRestoreDoesNotReplaceSavedHistory() async throws {
        let (originalVM, _, store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = ChatItem.agentMessage(id: "saved", text: "Keep", timestamp: Date())
        try await store.replaceTranscript(for: originalVM.id, with: [original])
        let display = ChatDisplayState(turnUsageByItemID: [:], lastTurnCompletedAt: Date(timeIntervalSince1970: 123), subAgents: [])
        try await store.saveDisplayState(display, for: originalVM.id)
        let client = TranscriptOrderClient(holdsResume: true)
        let vm = ChatSessionViewModel(id: originalVM.id, agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path, transcriptStore: store)
        let restoration = Task {
            await vm.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await client.resumeIsPending) {
            guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
            await Task.yield()
        }
        vm.reportError("Temporary restore-time output")
        await vm.flushTranscriptNow()
        #expect(try await store.loadTranscript(for: vm.id) == [original])
        #expect(try await store.loadDisplayState(for: vm.id) == display)
        await client.releaseResume()
        await restoration.value
        await vm.terminate()
        await originalVM.terminate()
    }

    @Test func unreadableSavedHistoryFailsRestoreAndRemainsUntouched() async throws {
        let (vm, _, _, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("\(vm.id.rawValue.uuidString).json")
        let unreadable = Data("incomplete-json".utf8)
        try unreadable.write(to: file)
        await vm.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        guard case .failed = vm.restoreState else {
            Issue.record("Unreadable saved history must fail restoration")
            return
        }
        await vm.flushTranscriptNow()
        #expect(try Data(contentsOf: file) == unreadable)
        await vm.terminate()
    }

    @Test func explicitRevertCanClearSavedHistoryAndFlushKeepsItEmpty() async throws {
        let (vm, client, store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await vm.sendText("Remove this turn", submit: true)
        let userID = try #require(vm.transcript.first?.id)
        client.continuation.yield(.normalized(.agentMessageDelta(itemId: "answer", "Done")))
        client.continuation.yield(.normalized(.turnCompleted(nativeSessionId: "thread")))
        try await waitUntil { vm.completedTurnSeq == 1 }
        await vm.flushTranscriptNow()
        #expect(try await store.loadTranscript(for: vm.id).count == 2)
        #expect(await vm.revert(toUserMessageID: userID) == "Remove this turn")
        await vm.flushTranscriptNow()
        #expect(try await store.loadTranscript(for: vm.id).isEmpty)
        await vm.terminate()
    }

    @Test func completedReasoningStillAcceptsLegacySummaryStrings() async throws {
        let (vm, client, store, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        client.continuation.yield(.thread(.itemCompleted(threadId: "thread", turnId: "turn", item: try item(
            #"{"id":"legacy","type":"reasoning","summary":"Legacy summary"}"#))))
        try await waitUntil { vm.transcript.contains { $0.id == "legacy" } }
        await vm.flushTranscriptNow()
        guard case .reasoning(_, let text, _) = try #require(try await store.loadTranscript(for: vm.id).first) else {
            Issue.record("Legacy summary must remain reasoning")
            return
        }
        #expect(text == "Legacy summary")
        await vm.terminate()
    }

    private func item(_ json: String) throws -> ThreadItem {
        try JSONDecoder().decode(ThreadItem.self, from: Data(json.utf8))
    }

    private enum WaitError: Error { case timedOut }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func fixture() async throws -> (ChatSessionViewModel, TranscriptOrderClient, FileTranscriptStore, URL) {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".verification/codex-transcript-order/fixtures/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let client = TranscriptOrderClient()
        let store = FileTranscriptStore(directoryURL: root)
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path, transcriptStore: store)
        await vm.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        return (vm, client, store, root)
    }
}
