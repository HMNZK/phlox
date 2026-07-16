// task-6 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-6.md — 実行中ターンの経過時間・無応答検出（ハング可視化）。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - 純関数 ChatHangPolicy

@Test func chatHang_assess_computesElapsedAndSilence() {
    let start = Date(timeIntervalSince1970: 1_000)
    let lastEvent = Date(timeIntervalSince1970: 1_070)
    let now = Date(timeIntervalSince1970: 1_120)
    let assessment = ChatHangPolicy.assess(now: now, turnStartedAt: start, lastEventAt: lastEvent)
    #expect(assessment == ChatHangAssessment(elapsed: 120, silence: 50, isStalled: false))
}

@Test func chatHang_assess_noEventsUsesTurnStartAsSilenceBase() {
    let start = Date(timeIntervalSince1970: 1_000)
    let now = Date(timeIntervalSince1970: 1_120)
    let assessment = ChatHangPolicy.assess(now: now, turnStartedAt: start, lastEventAt: nil)
    #expect(assessment == ChatHangAssessment(elapsed: 120, silence: 120, isStalled: true))
}

@Test func chatHang_assess_stallBoundaryIsWarnAfter() {
    let start = Date(timeIntervalSince1970: 1_000)
    func silence(_ seconds: TimeInterval) -> Bool {
        ChatHangPolicy.assess(
            now: start.addingTimeInterval(seconds),
            turnStartedAt: start,
            lastEventAt: start,
            warnAfter: 120
        ).isStalled
    }
    #expect(silence(119) == false)
    #expect(silence(120) == true)
}

@Test func chatHang_assess_eventAfterStartResetsBaseEvenIfEarlier() {
    // lastEventAt が turnStartedAt より前（前ターンの残骸）なら turnStartedAt を基準にする
    let start = Date(timeIntervalSince1970: 1_000)
    let staleEvent = Date(timeIntervalSince1970: 500)
    let now = Date(timeIntervalSince1970: 1_060)
    let assessment = ChatHangPolicy.assess(now: now, turnStartedAt: start, lastEventAt: staleEvent)
    #expect(assessment.silence == 60)
}

// MARK: - ViewModel のターンライフサイクル

private final class HangFakeClient: StructuredAgentClient, @unchecked Sendable {
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
private func makeHangVM(client: HangFakeClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Test @MainActor
func chatHang_viewModel_assessmentAvailableWhileRunning_andClearsOnCompletion() async throws {
    let client = HangFakeClient()
    let vm = makeHangVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.hangAssessment(now: Date()) == nil)

    try await vm.sendText("質問です", submit: true)
    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    try await waitUntil { vm.hangAssessment(now: Date()) != nil }

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    #expect(vm.hangAssessment(now: Date()) == nil)
}

@Test @MainActor
func chatHang_viewModel_errorClearsAssessment() async throws {
    let client = HangFakeClient()
    let vm = makeHangVM(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await vm.sendText("質問です", submit: true)
    client.yield(.turnStarted)
    try await waitUntil { vm.hangAssessment(now: Date()) != nil }

    client.yield(.error(message: "boom"))
    try await waitUntil { vm.hangAssessment(now: Date()) == nil }
}
