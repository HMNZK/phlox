import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-4 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-4.md
// 目的: 「セッションが完了・待機しているのに通知が来ない」の取りこぼし遷移を塞ぐ。
//   確認済みの穴（フェーズ0/1 調査）:
//   (1) 承認待ち・質問待ちの間に turnCompleted が届くと完了通知が出ない
//       （guard previousStatus == .running）
//   (2) pty 型はプロセス終了（completed/error）が完了通知の対象外（running→idle のみ）
//   既存の意図的な無通知（interrupt 由来 idle・復元リプレイ・連続 awaiting）は維持する
//   （既存凍結テスト ChatRemoteSessionNotifierTests と共存すること）。

// MARK: - ハーネス（ChatRemoteSessionNotifierTests と同型）

private final class NotifyFakeAgentClient: StructuredAgentClient, @unchecked Sendable {
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

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

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
    notifier: MockRemoteSessionNotifier
) -> (ChatSessionViewModel, NotifyFakeAgentClient) {
    let client = NotifyFakeAgentClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-notify-gap-test"
    )
    vm.remoteSessionNotifier = notifier
    return (vm, client)
}

// MARK: - 取りこぼし遷移 (1): 待機中に届いた turnCompleted

@Test @MainActor
func turnCompletedWhileAwaitingApproval_firesSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    vm.enterAwaitingApproval(prompt: "approve?")
    #expect(notifier.approvalPendingCalls.count == 1)

    // 承認待ちのまま turn が終わった（承認不要になった・turn 側で決着した）場合も
    // 「本物のターン完了」として完了通知を出すこと。
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1, "承認待ち経由の完了で通知が取りこぼされないこと")
}

@Test @MainActor
func turnCompletedWhileAwaitingUserQuestion_firesSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    client.yield(.userQuestionRequested(requestId: "req-1", questions: [
        ChatUserQuestion(question: "どちらにしますか?", header: "選択", options: [], multiSelect: false),
    ]))
    try await waitUntil { vm.status == .awaitingUserQuestion }

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1, "質問待ち経由の完了で通知が取りこぼされないこと")
}

// MARK: - 過剰通知の禁止（既存の意図的無通知の維持）

@Test @MainActor
func turnInterruptedAfterAwaitingApproval_doesNotFireSessionCompleted() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    vm.enterAwaitingApproval(prompt: "approve?")

    // ユーザー起点の中断（esc・拒否）で idle 化しても完了通知は出さないこと。
    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.isEmpty, "interrupt 由来の idle 遷移では鳴らさない（既存仕様の維持）")
}

@Test @MainActor
func duplicateTurnCompleted_firesSessionCompletedOnlyOnce() async throws {
    let notifier = MockRemoteSessionNotifier()
    let (vm, client) = makeViewModel(notifier: notifier)

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    #expect(notifier.sessionCompletedCalls.count == 1, "idle 中の重複 turnCompleted で多重通知しないこと")
}

// MARK: - 取りこぼし遷移 (2): pty 型のプロセス終了（純ポリシー）

@Suite("Acceptance: 完了通知ポリシー（task-4）")
struct AcceptanceCompletionNotificationPolicyTests {

    @Test("running からの実効的な停止（idle・プロセス終了・エラー終了）は通知対象")
    func runningToTerminalStatesNotify() {
        #expect(SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .idle))
        #expect(
            SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .completed(exitCode: 0)),
            "実行中のプロセス終了（completed）は完了として通知すること（現行の取りこぼし）"
        )
        #expect(
            SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .error(message: "boom")),
            "実行中の異常終了（error）も要対応の停止として通知すること（現行の取りこぼし）"
        )
    }

    @Test("実行を経ない遷移・状態の継続は通知しない")
    func nonRunningTransitionsStaySilent() {
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .starting, next: .idle))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .starting, next: .completed(exitCode: 0)))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .idle, next: .idle))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .idle, next: .running))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(previous: .running, next: .running))
        #expect(!SessionCompletionNotificationPolicy.shouldNotifyCompletion(
            previous: .running, next: .awaitingApproval(prompt: "p")
        ), "承認待ち入りは完了ではない（awaiting 系の通知は別経路）")
    }
}
