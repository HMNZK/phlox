import AgentDomain
import DesignSystem
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// 04 B5・01 E1: 120 秒反応がないチャット型は、タブ・サイドバー・対応待ちの一覧で「無応答」になる。

private final class StallFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func makeRunningVM() async throws -> (ChatSessionViewModel, StallFakeClient) {
    let client = StallFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("質問です", submit: true)
    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running && vm.hangAssessment(now: Date()) != nil }
    return (vm, client)
}

@Test @MainActor
func chatStall_runningTurnWithoutEvents_showsAsStalledAndClearsOnCompletion() async throws {
    let (vm, client) = try await makeRunningVM()
    let node = SessionNode.appServer(vm)

    vm.updateStalled(now: Date().addingTimeInterval(60))
    #expect(node.tabDisplayState == .running)

    let stalledAt = Date().addingTimeInterval(121)
    vm.updateStalled(now: stalledAt)
    #expect(node.tabDisplayState == .stalled)
    // 対応待ちの待ち時間は無応答になった時刻から数える。
    #expect(node.statusEnteredAt == stalledAt)

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    #expect(vm.isStalled == false)
    #expect(node.tabDisplayState != .stalled)
}

@Test @MainActor
func chatStall_eventAfterStall_clearsImmediately() async throws {
    let (vm, client) = try await makeRunningVM()
    vm.updateStalled(now: Date().addingTimeInterval(121))
    #expect(vm.isStalled)

    // 1 秒周期を待たず、反応が届いた時点で解ける。
    client.yield(.agentMessageDelta(itemId: "a1", "続き"))
    try await waitUntil { !vm.transcript.isEmpty && !vm.isStalled }
}

@Test @MainActor
func turnUsage_withoutCost_isShownUnderLastAgentMessage() async throws {
    let (vm, client) = try await makeRunningVM()
    client.yield(.agentMessageDelta(itemId: "a1", "答え"))
    client.yield(.turnUsage(TurnUsage(inputTokens: 18_200, contextUsedTokens: 92_000, contextWindowTokens: 200_000)))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    let agentID = vm.transcript.compactMap { item -> String? in
        if case .agentMessage(let id, _, _) = item { return id } else { return nil }
    }.last
    let id = try #require(agentID)
    #expect(vm.turnUsageByItemID[id]?.inputTokens == 18_200)
    #expect(!vm.transcript.contains { if case .turnCost = $0 { true } else { false } })
}

@Test @MainActor
func chatStall_awaitingUserQuestion_isNotCountedAsStalled() async throws {
    let (vm, client) = try await makeRunningVM()
    let question = ChatUserQuestion(question: "どちら?", header: "選択", options: [], multiSelect: false)
    client.yield(.userQuestionRequested(requestId: "q1", questions: [question]))
    try await waitUntil { vm.status != .running }

    vm.updateStalled(now: Date().addingTimeInterval(600))
    #expect(vm.isStalled == false)
    #expect(SessionNode.appServer(vm).tabDisplayState == .question)
}

// 13 Review: ⌘+ / ⌘− / ⌘0 はフォーカス中の領域（会話かターミナル）だけを変える。

@Test @MainActor
func fontSizeTarget_followsFrontChildTabOfChatSession() {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: StallFakeClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    let node = SessionNode.appServer(vm)
    #expect(DashboardViewModel.fontSizeTarget(node: node, selectedChildTab: .conversation) == .chat)
    #expect(DashboardViewModel.fontSizeTarget(node: node, selectedChildTab: .terminal) == .terminal)
    #expect(DashboardViewModel.fontSizeTarget(node: node, selectedChildTab: .file("a.swift")) == .chat)
    // 共通ターミナルを前面にしている間は、背後の会話ではなく端末。
    #expect(DashboardViewModel.fontSizeTarget(node: node, selectedChildTab: .conversation, showsCommonTerminal: true) == .terminal)
    // セッションを選んでいなければ、従来どおり両方を動かす。
    #expect(DashboardViewModel.fontSizeTarget(node: nil, selectedChildTab: nil) == .both)
}
