// 契約の正本: tasks/task-1.md — 停止ボタン（showsProcessingIndicator）の持続性。
// このファイルは PM が凍結する受け入れテスト。実装役は編集禁止（ハーネス欠陥は PM 承認の上でのみ修理可）。
//
// 不変契約: turn が終端イベント（turnCompleted / turnInterrupted）に達するまで、
// showsProcessingIndicator は true を維持する。途中イベント（delta / warning / usage）で消えない。
// 終端に達したら false に戻る（running 固着しない）。

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// MARK: - Test double（イベントを任意に注入できる StructuredAgentClient）

private final class ScriptedStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

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

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }
}

@MainActor
private func makeViewModel(client: ScriptedStructuredClient, agent: AgentKind) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(agent),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

/// イベント処理が非同期に流れ切るまでの短い猶予（「消えていないこと」の観測用）。
private let settleNanoseconds: UInt64 = 100_000_000

@Suite("Acceptance: 停止ボタンの持続性（task-1）")
@MainActor
struct AcceptanceStopButtonPersistenceTests {
    /// Cursor one-shot 相当: 送信後、イベントが一切届かない間も実行中表示を維持する。
    @Test func 送信後イベント未着でも実行中表示を維持する_cursor() async throws {
        let client = ScriptedStructuredClient()
        let vm = makeViewModel(client: client, agent: .cursor)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        try await vm.sendText("run something", submit: true)
        #expect(vm.showsProcessingIndicator)

        try await Task.sleep(nanoseconds: settleNanoseconds)
        #expect(vm.showsProcessingIndicator)
    }

    /// Codex app-server 相当: turnStarted 後、途中イベント（delta / commandExecution / warning /
    /// turnUsage）をいくら受けても、終端イベントまでは実行中表示を維持する。
    @Test func 途中イベントでは実行中表示が消えない_codex() async throws {
        let client = ScriptedStructuredClient()
        let vm = makeViewModel(client: client, agent: .codex)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.turnStarted)
        try await waitUntil { vm.showsProcessingIndicator }

        client.yield(.agentMessageDelta(itemId: "a-1", "working..."))
        client.yield(.commandExecution(itemId: "c-1", command: "swift build", outputDelta: ""))
        client.yield(.warning(message: "transient diagnostics"))
        client.yield(.turnUsage(TurnUsage(inputTokens: 1, outputTokens: 1)))

        try await Task.sleep(nanoseconds: settleNanoseconds)
        #expect(vm.showsProcessingIndicator)
    }

    /// 終端イベント（turnCompleted）で実行中表示が消える（running 固着しない）。
    @Test func 終端イベントで実行中表示が消える() async throws {
        let client = ScriptedStructuredClient()
        let vm = makeViewModel(client: client, agent: .codex)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.turnStarted)
        try await waitUntil { vm.showsProcessingIndicator }

        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { !vm.showsProcessingIndicator }
        #expect(!vm.showsProcessingIndicator)
    }

    /// turnInterrupted でも実行中表示が消える（停止経路の回帰）。
    @Test func 中断イベントで実行中表示が消える() async throws {
        let client = ScriptedStructuredClient()
        let vm = makeViewModel(client: client, agent: .cursor)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.turnStarted)
        try await waitUntil { vm.showsProcessingIndicator }

        client.yield(.turnInterrupted(nativeSessionId: nil))
        try await waitUntil { !vm.showsProcessingIndicator }
        #expect(!vm.showsProcessingIndicator)
    }
}
