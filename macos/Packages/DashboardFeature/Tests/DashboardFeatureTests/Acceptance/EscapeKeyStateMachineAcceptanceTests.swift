// task-9 受け入れテスト（PM 著・実装役は編集禁止）

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class EscRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var interruptCount = 0

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws { lock.withLock { interruptCount += 1 } }
    func close() async { continuation.finish() }
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func interruptCalls() -> Int { lock.withLock { interruptCount } }
}

@MainActor
private func makeSeededVM(client: EscRecordingClient) async throws -> ChatSessionViewModel {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    // 2 ターン分の userMessage を積む。
    try await vm.sendText("古い依頼", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try await vm.sendText("新しい依頼", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    return vm
}

@Test @MainActor
func escWhileRunning_firesInterrupt_withoutOpeningPicker() async throws {
    let client = EscRecordingClient()
    let vm = try await makeSeededVM(client: client)
    try await vm.sendText("実行中の依頼", submit: true) // running へ

    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    vm.handleEscapeKey(now: t0)

    try await waitUntil { client.interruptCalls() == 1 }
    #expect(!vm.isHistoryPickerPresented)
}

@Test @MainActor
func doubleEscWithinWindow_opensPickerWithUserMessagesNewestFirst() async throws {
    let client = EscRecordingClient()
    let vm = try await makeSeededVM(client: client)

    let t0 = Date(timeIntervalSinceReferenceDate: 2_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.5))

    #expect(vm.isHistoryPickerPresented)
    let candidateTexts = vm.revertCandidates.map(\.plainText)
    try #require(candidateTexts.count == 2)
    #expect(candidateTexts[0].contains("新しい依頼"), "新しい順で並んでいない")
    #expect(candidateTexts[1].contains("古い依頼"))
}

@Test @MainActor
func doubleEscOutsideWindow_doesNotOpenPicker() async throws {
    let client = EscRecordingClient()
    let vm = try await makeSeededVM(client: client)

    let t0 = Date(timeIntervalSinceReferenceDate: 3_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(2.0)) // 1.5 秒窓の外

    #expect(!vm.isHistoryPickerPresented)
}

@Test @MainActor
func escWhilePickerPresented_closesPicker() async throws {
    let client = EscRecordingClient()
    let vm = try await makeSeededVM(client: client)

    let t0 = Date(timeIntervalSinceReferenceDate: 4_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.3))
    try #require(vm.isHistoryPickerPresented)

    vm.handleEscapeKey(now: t0.addingTimeInterval(0.6))
    #expect(!vm.isHistoryPickerPresented)
}

@Test @MainActor
func emptyTranscript_doubleEsc_doesNotOpenPicker() async throws {
    let client = EscRecordingClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.3))
    #expect(!vm.isHistoryPickerPresented)
}

@Test @MainActor
func confirmRevert_revertsTranscript_setsDraftRestoration_andClosesPicker() async throws {
    let client = EscRecordingClient()
    let vm = try await makeSeededVM(client: client)

    let t0 = Date(timeIntervalSinceReferenceDate: 6_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.3))
    try #require(vm.isHistoryPickerPresented)

    let newest = try #require(vm.revertCandidates.first)
    await vm.confirmRevert(toUserMessageID: newest.id)

    #expect(!vm.isHistoryPickerPresented)
    #expect(vm.draftRestoration == "新しい依頼")
    #expect(!vm.transcript.map(\.plainText).joined().contains("新しい依頼"))

    vm.consumeDraftRestoration()
    #expect(vm.draftRestoration == nil)
}
