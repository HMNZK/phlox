import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-4 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-4.md — A3 sendText の status 復帰 / S1 terminate の pending 承認解決 / N1 Command 空行。

/// turnStart を1回だけ throw させられる自己完結のフェイククライアント（A3 用）。
private final class PM3Task4ThrowingClient: StructuredAgentClient, @unchecked Sendable {
    struct SendFailure: Error {}

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var throwNextTurnStart = false
    private var turnStartCount = 0

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        let shouldThrow = lock.withLock { () -> Bool in
            turnStartCount += 1
            if throwNextTurnStart {
                throwNextTurnStart = false
                return true
            }
            return false
        }
        if shouldThrow { throw SendFailure() }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func armThrowNextTurnStart() { lock.withLock { throwNextTurnStart = true } }
    func recordedTurnStartCount() -> Int { lock.withLock { turnStartCount } }
}

private final class PM3Task4Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    func isSet() -> Bool { lock.withLock { value } }
}

/// close() の滞在を外部フラグで制御できるフェイククライアント（terminate 中の interleaving 再現用）。
private final class PM3Task4CloseGateClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let closeEntered: PM3Task4Flag
    private let releaseClose: PM3Task4Flag

    init(closeEntered: PM3Task4Flag, releaseClose: PM3Task4Flag) {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured!
        self.closeEntered = closeEntered
        self.releaseClose = releaseClose
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func resetConversation() async {}

    func close() async {
        closeEntered.set()
        // release されるまで滞在する（上限 10 秒で必ず抜ける）。
        for _ in 0..<2000 where !releaseClose.isSet() {
            try? await Task.sleep(for: .milliseconds(5))
        }
        continuation.finish()
    }
}

@MainActor
private func pm3Task4VM(
    client: PM3Task4ThrowingClient,
    broker: ChatApprovalBroker = ChatApprovalBroker()
) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/pm3task4",
        transcriptStore: NoOpTranscriptStore()
    )
}

@Suite(.serialized)
struct PM3Task4ChatSendTerminateAcceptanceTests {

    // A3: turnStart が throw したら sendText はエラーを伝播しつつ status を .idle に戻す
    // （.running のまま固着しない）。その後の送信は正常に機能する。
    @Test @MainActor
    func sendText_turnStartThrows_restoresIdleStatusAndAllowsRetry() async throws {
        let client = PM3Task4ThrowingClient()
        let vm = pm3Task4VM(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.armThrowNextTurnStart()
        await #expect(throws: PM3Task4ThrowingClient.SendFailure.self) {
            try await vm.sendText("失敗する送信", submit: true)
        }
        #expect(vm.status == .idle, "turnStart 失敗後に status が .idle に戻っていない: \(vm.status)")

        // 回復: 次の送信は通常どおり走り、turn 完了で idle に戻る。
        try await vm.sendText("再送", submit: true)
        #expect(client.recordedTurnStartCount() == 2)
        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { vm.status == .idle }
    }

    // S1: 承認待ち（ChatApprovalBroker.pending）で await 中の呼び出しは、terminate() で
    // 全て復帰する（continuation リークしない）。
    @Test @MainActor
    func terminate_resolvesPendingApprovalContinuations() async throws {
        let broker = ChatApprovalBroker()
        let client = PM3Task4ThrowingClient()
        let vm = pm3Task4VM(client: client, broker: broker)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        let approvalJSON = """
        {"threadId":"t1","turnId":"turn1","itemId":"item1","startedAtMs":0,"command":"rm -rf /tmp/x","reason":"確認"}
        """
        let payload = try JSONDecoder().decode(
            CommandExecutionApprovalRequest.self,
            from: Data(approvalJSON.utf8)
        )
        let handler = broker.serverRequestHandler
        let completed = PM3Task4Flag()
        let approvalTask = Task.detached {
            _ = try? await handler(.commandExecutionApproval(payload))
            completed.set()
        }

        // pending が登録される（= VM の承認 UI に要求が現れる）まで待つ。
        // 注: broker.requests は単一消費者の AsyncStream で VM 自身が消費するため、
        // テストは VM が公開する pendingApprovals を観測する。
        try await waitUntil { !vm.pendingApprovals.isEmpty }
        #expect(completed.isSet() == false, "terminate 前に承認待ちが解決してしまっている")

        await vm.terminate()
        try await waitUntil { completed.isSet() }

        approvalTask.cancel()
    }

    // S1 補: terminate は二重呼び出しでも安全（クラッシュ・ハングしない）。
    @Test @MainActor
    func terminate_isIdempotent() async throws {
        let client = PM3Task4ThrowingClient()
        let vm = pm3Task4VM(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        await vm.terminate()
        await vm.terminate()
    }

    // S1 補（stage2 指摘の interleaving）: terminate の進行中（cancelAll 後・close 中）に
    // 遅れて到達した承認要求も、リークせず復帰する。terminate 完了後の broker は
    // 新規 pending を無期限に抱え込んではならない（terminal 状態で即時解決する）。
    @Test @MainActor
    func terminate_resolvesApprovalArrivingDuringClientClose() async throws {
        let broker = ChatApprovalBroker()
        let closeEntered = PM3Task4Flag()
        let releaseClose = PM3Task4Flag()
        let client = PM3Task4CloseGateClient(closeEntered: closeEntered, releaseClose: releaseClose)
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.cursor),
            client: client,
            approvalBroker: broker,
            workingDirectory: "/tmp/pm3task4",
            transcriptStore: NoOpTranscriptStore()
        )

        let handler = broker.serverRequestHandler
        let completed = PM3Task4Flag()
        let terminating = Task { await vm.terminate() }
        // terminate が cancelAll を済ませ client.close() に滞在するまで待つ。
        try await waitUntil { closeEntered.isSet() }

        let approvalJSON = """
        {"threadId":"t1","turnId":"turn1","itemId":"late","startedAtMs":0,"command":"echo late","reason":"確認"}
        """
        let payload = try JSONDecoder().decode(
            CommandExecutionApprovalRequest.self,
            from: Data(approvalJSON.utf8)
        )
        let lateRequest = Task.detached {
            _ = try? await handler(.commandExecutionApproval(payload))
            completed.set()
        }

        releaseClose.set()
        _ = await terminating.value
        try await waitUntil { completed.isSet() }

        lateRequest.cancel()
    }

    // N1: command == nil の commandExecution は "Command: " の空行を出力しない。
    @Test
    func plainText_commandExecutionWithNilCommand_hasNoEmptyCommandLine() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let withOutput = ChatItem.commandExecution(
            id: "c1", command: nil, output: "hello", timestamp: timestamp
        )
        #expect(withOutput.plainText == "hello", "command==nil で 'Command: ' 行が混入: \(withOutput.plainText)")

        let empty = ChatItem.commandExecution(
            id: "c2", command: nil, output: "", timestamp: timestamp
        )
        #expect(empty.plainText.isEmpty, "command==nil・output 空で残骸が出力される: '\(empty.plainText)'")

        // 既存挙動の凍結: command がある場合は従来どおり。
        let withCommand = ChatItem.commandExecution(
            id: "c3", command: "ls", output: "a.txt", timestamp: timestamp
        )
        #expect(withCommand.plainText == "Command: ls\na.txt")
    }
}
