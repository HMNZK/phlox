import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-1 の白箱テスト（実装役著）。受け入れテストが押さえない内部経路
// ＝トークンの単調増加・1操作あたりの発火回数・revert が nil を返す経路 を符号化する。

private final class WhiteboxFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func waitUntilWhitebox(
    _ description: String,
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("タイムアウト: \(description)")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
}

@MainActor
private func makeWhiteboxViewModel() async throws -> (ChatSessionViewModel, WhiteboxFakeClient) {
    let client = WhiteboxFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-composer-focus-whitebox-test"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("依頼A", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntilWhitebox("1ターン目が idle へ戻る") { vm.status == .idle }
    try await vm.sendText("依頼B", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntilWhitebox("2ターン目が idle へ戻る") { vm.status == .idle }
    return (vm, client)
}

@MainActor
private func openPicker(_ vm: ChatSessionViewModel, at base: Date = Date()) throws {
    vm.handleEscapeKey(now: base)
    vm.handleEscapeKey(now: base.addingTimeInterval(0.2))
    try #require(vm.isHistoryPickerPresented, "前提条件: esc 2連打でピッカーが開くこと")
}

@Suite("白箱: composerFocusRequest の発火規律（task-1）")
@MainActor
struct ComposerFocusRequestWhiteboxTests {

    @Test("イニシャライザ直後は未要求（token == 0）")
    func initialStateIsNone() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        #expect(vm.composerFocusRequest == .none)
        #expect(vm.composerFocusRequest.token == 0)
    }

    @Test("ピッカーのキャンセル1回で token はちょうど 1 進む（二重発火しない）")
    func cancellingPickerAdvancesTokenExactlyOnce() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        try openPicker(vm)
        let before = vm.composerFocusRequest.token

        vm.handleEscapeKey()

        #expect(vm.composerFocusRequest.token == before + 1)
    }

    @Test("復元1回で token はちょうど 1 進む（二重発火しない）")
    func confirmRevertAdvancesTokenExactlyOnce() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        try openPicker(vm)
        let candidate = try #require(vm.revertCandidates.first)
        let before = vm.composerFocusRequest.token

        await vm.confirmRevert(toUserMessageID: candidate.id)

        #expect(vm.composerFocusRequest.token == before + 1)
    }

    @Test("復元とキャンセルを繰り返しても token は狭義単調増加")
    func tokenIsStrictlyIncreasingAcrossOperations() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        var observed: [Int] = []

        try openPicker(vm)
        vm.handleEscapeKey()
        observed.append(vm.composerFocusRequest.token)

        try openPicker(vm, at: Date().addingTimeInterval(10))
        let candidate = try #require(vm.revertCandidates.first)
        await vm.confirmRevert(toUserMessageID: candidate.id)
        observed.append(vm.composerFocusRequest.token)

        try openPicker(vm, at: Date().addingTimeInterval(20))
        vm.handleEscapeKey()
        observed.append(vm.composerFocusRequest.token)

        #expect(observed == [1, 2, 3])
    }

    @Test("revert が本文を返さない経路でも token は進み、キャレットは動かさない")
    func confirmRevertWithoutRestorationStillRequestsFocus() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        try openPicker(vm)
        let before = vm.composerFocusRequest.token

        // 存在しない id → revert は nil を返す（本文復元なし）。それでもピッカーは閉じるのでフォーカスは返す。
        await vm.confirmRevert(toUserMessageID: "no-such-user-message-id")

        #expect(vm.draftRestoration == nil, "前提条件: 本文は復元されていない")
        #expect(vm.composerFocusRequest.token == before + 1)
        #expect(vm.composerFocusRequest.movesCaretToEnd == false)
        #expect(vm.isHistoryPickerPresented == false)
    }

    @Test("処理中の単発 esc（interrupt 経路）ではフォーカス復帰を要求しない")
    func singleEscapeWhileProcessingDoesNotRequestFocus() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        try await vm.sendText("走行中の依頼", submit: true)
        try #require(vm.showsProcessingIndicator, "前提条件: 処理中インジケータが出ていること")
        let before = vm.composerFocusRequest

        vm.handleEscapeKey()

        #expect(vm.composerFocusRequest == before)
    }

    @Test("esc と無関係な操作（sendText）ではフォーカス復帰を要求しない")
    func unrelatedOperationsDoNotRequestFocus() async throws {
        let (vm, _) = try await makeWhiteboxViewModel()
        let before = vm.composerFocusRequest

        try await vm.sendText("追加の依頼", submit: true)

        #expect(vm.composerFocusRequest == before)
    }

    @Test("候補が空で2連打してもピッカーは開かず、フォーカス復帰も要求しない")
    func doubleEscapeWithoutCandidatesDoesNotRequestFocus() async throws {
        let client = WhiteboxFakeClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-composer-focus-whitebox-empty"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try #require(vm.revertCandidates.isEmpty, "前提条件: リバート候補が空")
        let before = vm.composerFocusRequest

        let base = Date()
        vm.handleEscapeKey(now: base)
        vm.handleEscapeKey(now: base.addingTimeInterval(0.2))

        #expect(vm.isHistoryPickerPresented == false)
        #expect(vm.composerFocusRequest == before)
    }
}
