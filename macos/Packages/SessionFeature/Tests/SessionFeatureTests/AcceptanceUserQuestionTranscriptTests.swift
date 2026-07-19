import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-2 受け入れテスト（PM 著・凍結）。契約: tasks/task-2.md（VM 状態遷移）。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

// MARK: - ハーネス

private final class QuestionRecordingClient: StructuredAgentClient, @unchecked Sendable {
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
private func makeQuestionViewModel(client: QuestionRecordingClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

private let vmQuestions = [
    ChatUserQuestion(
        question: "デプロイ先は?",
        header: "Deploy",
        options: [
            ChatUserQuestionOption(label: "staging", description: "検証環境"),
            ChatUserQuestionOption(label: "prod", description: nil),
        ],
        multiSelect: false
    ),
]

@MainActor
private func questionItem(in vm: ChatSessionViewModel, requestId: String) -> (
    answers: [String: [String]]?, state: ChatUserQuestionState
)? {
    for item in vm.transcript {
        if case let .userQuestion(_, rid, _, answers, state, _) = item, rid == requestId {
            return (answers, state)
        }
    }
    return nil
}

private func waitUntilCondition(
    _ condition: @escaping @MainActor () -> Bool,
    timeoutMs: Int = 2000
) async throws {
    for _ in 0..<(timeoutMs / 10) {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let final = await condition()
    #expect(final, "waitUntilCondition timed out")
}

// MARK: - 受け入れ条件

@Test @MainActor
func userQuestionRequestedAppendsPendingCard() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: vmQuestions))

    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1") != nil }
    let card = try #require(questionItem(in: vm, requestId: "req-1"))
    #expect(card.state == .pending)
    #expect(card.answers == nil)
    // カード id は "question-<requestId>" 規約（transcript 置換の安定キー）。
    #expect(vm.transcript.contains { $0.id == "question-req-1" })
}

@Test @MainActor
func respondToUserQuestionForwardsToClientAndMarksAnswered() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: vmQuestions))
    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1") != nil }

    let accepted = await vm.respondToUserQuestion(
        requestId: "req-1",
        answers: ["デプロイ先は?": ["staging"]]
    )

    #expect(accepted)
    #expect(client.respondCalls.count == 1)
    #expect(client.respondCalls.first?.requestId == "req-1")
    #expect(client.respondCalls.first?.answers == ["デプロイ先は?": ["staging"]])
    let card = try #require(questionItem(in: vm, requestId: "req-1"))
    #expect(card.state == .answered)
    #expect(card.answers == ["デプロイ先は?": ["staging"]])
}

@Test @MainActor
func respondToUnknownRequestIdIsRejectedWithoutClientCall() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let accepted = await vm.respondToUserQuestion(requestId: "no-such", answers: ["Q": ["A"]])

    #expect(!accepted)
    #expect(client.respondCalls.isEmpty)
}

@Test @MainActor
func secondRespondToSameQuestionIsRejected() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: vmQuestions))
    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1") != nil }

    let first = await vm.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])
    let second = await vm.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["prod"]])

    #expect(first)
    #expect(!second)
    #expect(client.respondCalls.count == 1)
    let card = try #require(questionItem(in: vm, requestId: "req-1"))
    #expect(card.answers == ["デプロイ先は?": ["staging"]])
}

@Test @MainActor
func resolvedExpiredMarksCardExpired() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: vmQuestions))
    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1") != nil }

    client.yield(.userQuestionResolved(requestId: "req-1", outcome: .expired))

    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1")?.state == .expired }
    let expired = await vm.respondToUserQuestion(requestId: "req-1", answers: ["デプロイ先は?": ["staging"]])
    #expect(!expired)
    #expect(client.respondCalls.isEmpty)
}

@Test @MainActor
func turnInterruptedExpiresPendingCards() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: vmQuestions))
    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1") != nil }

    client.yield(.turnInterrupted(nativeSessionId: nil))

    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1")?.state == .expired }
    #expect(questionItem(in: vm, requestId: "req-1")?.state == .expired)
}

@Test @MainActor
func errorEventExpiresPendingCards() async throws {
    let client = QuestionRecordingClient()
    let vm = makeQuestionViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-1", questions: vmQuestions))
    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1") != nil }

    client.yield(.error(message: "boom"))

    try await waitUntilCondition { questionItem(in: vm, requestId: "req-1")?.state == .expired }
    #expect(questionItem(in: vm, requestId: "req-1")?.state == .expired)
}
