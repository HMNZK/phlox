// AskUserQuestion のセッション側の振る舞い（ChatSessionViewModel）。
//   - running 中に .userQuestionRequested を受けたら hasUnseenCompletion をラッチする
//     （SessionGridView の赤枠は hasUnseenCompletion が駆動する）
//   - 同時に remoteSessionNotifier.approvalPending を 1 回だけ発火する（多重通知しない）
//   - markCompletionSeen() でラッチが解除される。質問の解決は新たな通知・ラッチを発火しない
//   - 解決通知の冪等性・中断時は未回答カードだけ失効・二重回答は 1 回だけ受理

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeViewModel(
    notifier: MockRemoteSessionNotifier? = nil
) -> (ChatSessionViewModel, QuestionClient) {
    let client = QuestionClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-question-attention-test"
    )
    vm.remoteSessionNotifier = notifier
    return (vm, client)
}

private func question(_ text: String = "どの方式にしますか？") -> ChatUserQuestion {
    ChatUserQuestion(
        question: text,
        header: "方式",
        options: [ChatUserQuestionOption(label: "A案"), ChatUserQuestionOption(label: "B案")],
        multiSelect: false
    )
}

@Suite("AskUserQuestion session")
struct UserQuestionSessionTests {
    @Test @MainActor
    func running中の質問到着で未確認停止をラッチする() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        #expect(vm.hasUnseenCompletion == false)

        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.hasUnseenCompletion }

        #expect(vm.hasUnseenCompletion)
    }

    @Test @MainActor
    func 質問到着でリモート通知をちょうど1回発火する() async throws {
        let notifier = MockRemoteSessionNotifier()
        let (vm, client) = makeViewModel(notifier: notifier)
        vm.name = "Question Session"

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { notifier.approvalPendingCalls.count >= 1 }

        #expect(notifier.approvalPendingCalls.count == 1)
        #expect(notifier.approvalPendingCalls.first?.sessionName == "Question Session")
    }

    @Test @MainActor
    func markCompletionSeenでラッチが解除される() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { vm.hasUnseenCompletion }

        vm.markCompletionSeen()

        #expect(vm.hasUnseenCompletion == false)
    }

    @Test @MainActor
    func 質問の解決は追加の通知もラッチもしない() async throws {
        let notifier = MockRemoteSessionNotifier()
        let (vm, client) = makeViewModel(notifier: notifier)

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }
        client.yield(.userQuestionRequested(requestId: "q-1", questions: [question()]))
        try await waitUntil { notifier.approvalPendingCalls.count >= 1 }
        vm.markCompletionSeen()

        client.yield(.userQuestionResolved(
            requestId: "q-1",
            outcome: .answered(answers: ["どの方式にしますか？": ["A案"]])
        ))
        try await waitUntil { vm.transcript.contains { item in
            if case .userQuestion(_, _, _, _, let state, _) = item { return state == .answered }
            return false
        } }

        #expect(notifier.approvalPendingCalls.count == 1)
        #expect(vm.hasUnseenCompletion == false)
    }
}

private final class QuestionClient: StructuredAgentClient, @unchecked Sendable {
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
        let shouldSuspend = lock.withLock {
            let armed = gateArmed
            gateArmed = false
            return armed
        }
        if shouldSuspend {
            await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
                lock.withLock { respondGate = gate }
            }
        }
        lock.withLock { recordedResponses.append((requestId, answers)) }
    }

    // 送信 suspend 中の二重回答レース再現用の gate（armRespondGate 後の最初の
    // respondToUserQuestion を releaseRespondGate まで suspend させる）
    private var respondGate: CheckedContinuation<Void, Never>?
    private var gateArmed = false

    func armRespondGate() {
        lock.withLock { gateArmed = true }
    }

    var isGateWaiting: Bool {
        lock.withLock { respondGate != nil }
    }

    func releaseRespondGate() {
        let gate = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let captured = respondGate
            respondGate = nil
            return captured
        }
        gate?.resume()
    }
}

@MainActor
private func makeLifecycleViewModel(client: QuestionClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

private let lifecycleQuestion = ChatUserQuestion(
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
    let client = QuestionClient()
    let vm = makeLifecycleViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-a", questions: [lifecycleQuestion]))
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
    let client = QuestionClient()
    let vm = makeLifecycleViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "pending-one", questions: [lifecycleQuestion]))
    client.yield(.userQuestionRequested(requestId: "answered-one", questions: [lifecycleQuestion]))
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
    let client = QuestionClient()
    let vm = makeLifecycleViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-keep", questions: [lifecycleQuestion]))
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

// 1回目の回答が client 送信で suspend している間の二重回答は受理しない
// （stage1 レビュー MUST の回帰ガード: 両方 true になり answers が競合上書きされるレース）。
@Test @MainActor
func concurrentDoubleRespondAcceptsOnlyOne() async throws {
    let client = QuestionClient()
    let vm = makeLifecycleViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.userQuestionRequested(requestId: "req-race", questions: [lifecycleQuestion]))
    try await waitForCard(vm, requestId: "req-race")

    client.armRespondGate()
    async let first = vm.respondToUserQuestion(requestId: "req-race", answers: ["色は?": ["red"]])
    for _ in 0..<200 {
        if client.isGateWaiting { break }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(client.isGateWaiting, "1回目の回答が client 送信で suspend している")

    let second = await vm.respondToUserQuestion(requestId: "req-race", answers: ["色は?": ["blue"]])
    client.releaseRespondGate()
    let firstResult = await first

    #expect(firstResult == true)
    #expect(second == false, "送信中の同一質問への二重回答は false")
    #expect(client.respondCalls.count == 1, "client への送信は1回のみ")

    if let card = vm.transcript.first(where: { item in
        if case .userQuestion(_, "req-race", _, _, _, _) = item { return true }
        return false
    }), case .userQuestion(_, _, _, let answers, .answered, _) = card {
        #expect(answers == ["色は?": ["red"]], "answers は実際に送信された1回目の値")
    } else {
        Issue.record("expected answered userQuestion card")
    }
}
