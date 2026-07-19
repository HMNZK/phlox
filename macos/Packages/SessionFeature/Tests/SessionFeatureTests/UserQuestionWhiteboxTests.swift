import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-2 白箱テスト（実装エージェント著）。VM の冪等性・複数カード・resolved.answered を補完する。

private final class WhiteboxQuestionClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var recordedResponses: [(requestId: String, answers: [String: [String]])] = []

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    var respondCalls: [(requestId: String, answers: [String: [String]])] {
        lock.withLock { recordedResponses }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }

    func respondToUserQuestion(requestId: String, answers: [String: [String]]) async {
        lock.withLock { recordedResponses.append((requestId, answers)) }
    }
}

@MainActor
private func makeWhiteboxViewModel(client: WhiteboxQuestionClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

private let whiteboxQuestion = ChatUserQuestion(
    question: "色は?",
    header: "Color",
    options: [ChatUserQuestionOption(label: "red", description: nil)],
    multiSelect: false
)

@MainActor
private func waitForCard(_ vm: ChatSessionViewModel, requestId: String) async throws {
    for _ in 0..<200 {
        if vm.transcript.contains(where: { item in
            if case .userQuestion(_, let rid, _, _, _, _) = item { return rid == requestId }
            return false
        }) {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("question card did not appear")
}

@Test @MainActor
func resolvedAnsweredIsIdempotentAfterLocalRespond() async throws {
    let client = WhiteboxQuestionClient()
    let vm = makeWhiteboxViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-a", questions: [whiteboxQuestion]))
    try await waitForCard(vm, requestId: "req-a")

    let accepted = await vm.respondToUserQuestion(requestId: "req-a", answers: ["色は?": ["red"]])
    #expect(accepted)

    client.yield(.userQuestionResolved(
        requestId: "req-a",
        outcome: .answered(answers: ["色は?": ["red"]])
    ))
    try await Task.sleep(nanoseconds: 50_000_000)

    let card = vm.transcript.first { item in
        if case .userQuestion(_, let rid, _, _, _, _) = item { return rid == "req-a" }
        return false
    }
    guard case .userQuestion(_, _, _, let answers, .answered, _) = card else {
        Issue.record("expected answered card")
        return
    }
    #expect(answers == ["色は?": ["red"]])
    #expect(client.respondCalls.count == 1)
}

@Test @MainActor
func turnInterruptedExpiresOnlyPendingCards() async throws {
    let client = WhiteboxQuestionClient()
    let vm = makeWhiteboxViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "pending-one", questions: [whiteboxQuestion]))
    client.yield(.userQuestionRequested(requestId: "answered-one", questions: [whiteboxQuestion]))
    try await waitForCard(vm, requestId: "pending-one")
    try await waitForCard(vm, requestId: "answered-one")

    _ = await vm.respondToUserQuestion(requestId: "answered-one", answers: ["色は?": ["red"]])
    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await Task.sleep(nanoseconds: 50_000_000)

    func state(for requestId: String) -> ChatUserQuestionState? {
        for item in vm.transcript {
            if case .userQuestion(_, let rid, _, _, let state, _) = item, rid == requestId {
                return state
            }
        }
        return nil
    }

    #expect(state(for: "pending-one") == .expired)
    #expect(state(for: "answered-one") == .answered)
    #expect(vm.transcript.filter {
        if case .userQuestion = $0 { return true }
        return false
    }.count == 2)
}

@Test @MainActor
func answeredCardRemainsInTranscriptAfterExpirySignal() async throws {
    let client = WhiteboxQuestionClient()
    let vm = makeWhiteboxViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-keep", questions: [whiteboxQuestion]))
    try await waitForCard(vm, requestId: "req-keep")
    _ = await vm.respondToUserQuestion(requestId: "req-keep", answers: ["色は?": ["red"]])

    client.yield(.userQuestionResolved(requestId: "req-keep", outcome: .expired))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(vm.transcript.contains { $0.id == "question-req-keep" })
    if case .userQuestion(_, _, _, let answers, let state, _) = vm.transcript.first(where: { $0.id == "question-req-keep" }) {
        #expect(state == .answered)
        #expect(answers == ["色は?": ["red"]])
    } else {
        Issue.record("expected userQuestion item to remain")
    }
}
