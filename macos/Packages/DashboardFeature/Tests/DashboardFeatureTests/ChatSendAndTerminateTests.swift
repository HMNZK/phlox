import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// Chat の送信失敗からの復帰と terminate、および承認待ち（ChatApprovalBroker）の解決。
// - sendText の turnStart が throw しても status が .running で固着しない。
// - terminate は承認待ちの continuation を全て解決する（リークしない・二重 resume しない）。
//   terminate 進行中に遅れて届いた承認要求も、リークせず解決される。

/// turnStart を1回だけ throw させられる自己完結のフェイククライアント（A3 用）。
private final class ThrowingTurnStartClient: StructuredAgentClient, @unchecked Sendable {
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

private final class SignalFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    func isSet() -> Bool { lock.withLock { value } }
}

/// close() の滞在を外部フラグで制御できるフェイククライアント（terminate 中の interleaving 再現用）。
private final class CloseGateClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let closeEntered: SignalFlag
    private let releaseClose: SignalFlag

    init(closeEntered: SignalFlag, releaseClose: SignalFlag) {
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
private func makeChatViewModel(
    client: ThrowingTurnStartClient,
    broker: ChatApprovalBroker = ChatApprovalBroker()
) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/chat-send-terminate",
        transcriptStore: NoOpTranscriptStore()
    )
}

/// NSLock ベースの Sendable カウンタ（waitUntil の同期クロージャから読める）。
private final class CompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    func get() -> Int { lock.withLock { value } }
}

/// broker.requests から観測した承認 id を集める（単一消費者ストリームを白箱で自分が消費）。
private final class ApprovalIDCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []
    func append(_ id: UUID) { lock.withLock { ids.append(id) } }
    func count() -> Int { lock.withLock { ids.count } }
    func all() -> [UUID] { lock.withLock { ids } }
}

private func makeCommandApproval(index: Int) -> CommandExecutionApprovalRequest {
    let json = """
    {"threadId":"t","turnId":"turn","itemId":"item-\(index)","startedAtMs":0,"command":"echo \(index)","reason":"確認"}
    """
    return try! JSONDecoder().decode(CommandExecutionApprovalRequest.self, from: Data(json.utf8))
}

private func makePermissionsApproval(index: Int) -> PermissionsApprovalRequest {
    let json = """
    {"threadId":"t","turnId":"turn","itemId":"perm-\(index)","startedAtMs":0,"cwd":"/tmp","reason":"権限","permissions":{"tools":["Bash"]}}
    """
    return try! JSONDecoder().decode(PermissionsApprovalRequest.self, from: Data(json.utf8))
}

@Suite("Chat send failure and terminate", .serialized)
struct ChatSendAndTerminateTests {

    // 送信失敗: turnStart が throw したら sendText はエラーを伝播しつつ status を .idle に戻す
    // （.running のまま固着しない）。その後の送信は正常に機能する。
    @Test @MainActor
    func sendText_turnStartThrows_restoresIdleStatusAndAllowsRetry() async throws {
        let client = ThrowingTurnStartClient()
        let vm = makeChatViewModel(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.armThrowNextTurnStart()
        await #expect(throws: ThrowingTurnStartClient.SendFailure.self) {
            try await vm.sendText("失敗する送信", submit: true)
        }
        #expect(vm.status == .idle, "turnStart 失敗後に status が .idle に戻っていない: \(vm.status)")

        // 回復: 次の送信は通常どおり走り、turn 完了で idle に戻る。
        try await vm.sendText("再送", submit: true)
        #expect(client.recordedTurnStartCount() == 2)
        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { vm.status == .idle }
    }

    // terminate: 承認待ち（ChatApprovalBroker.pending）で await 中の呼び出しは、terminate() で
    // 全て復帰する（continuation リークしない）。
    @Test @MainActor
    func terminate_resolvesPendingApprovalContinuations() async throws {
        let broker = ChatApprovalBroker()
        let client = ThrowingTurnStartClient()
        let vm = makeChatViewModel(client: client, broker: broker)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        let approvalJSON = """
        {"threadId":"t1","turnId":"turn1","itemId":"item1","startedAtMs":0,"command":"rm -rf /tmp/x","reason":"確認"}
        """
        let payload = try JSONDecoder().decode(
            CommandExecutionApprovalRequest.self,
            from: Data(approvalJSON.utf8)
        )
        let handler = broker.serverRequestHandler
        let completed = SignalFlag()
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

    // terminate: terminate は二重呼び出しでも安全（クラッシュ・ハングしない）。
    @Test @MainActor
    func terminate_isIdempotent() async throws {
        let client = ThrowingTurnStartClient()
        let vm = makeChatViewModel(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        await vm.terminate()
        await vm.terminate()
    }

    // terminate: terminate の進行中（cancelAll 後・close 中）に
    // 遅れて到達した承認要求も、リークせず復帰する。terminate 完了後の broker は
    // 新規 pending を無期限に抱え込んではならない（terminal 状態で即時解決する）。
    @Test @MainActor
    func terminate_resolvesApprovalArrivingDuringClientClose() async throws {
        let broker = ChatApprovalBroker()
        let closeEntered = SignalFlag()
        let releaseClose = SignalFlag()
        let client = CloseGateClient(closeEntered: closeEntered, releaseClose: releaseClose)
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.cursor),
            client: client,
            approvalBroker: broker,
            workingDirectory: "/tmp/chat-send-terminate",
            transcriptStore: NoOpTranscriptStore()
        )

        let handler = broker.serverRequestHandler
        let completed = SignalFlag()
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
}

@Suite("ChatApprovalBroker cancelAll", .serialized)
struct ChatApprovalBrokerCancelAllTests {

    /// resume-exactly-once: respond と cancelAll を同時に走らせても、各 continuation は
    /// ちょうど1回だけ resume される（2回なら CheckedContinuation がプロセスをクラッシュさせる／
    /// 0回なら await が復帰せず waitUntil がタイムアウトする）。多数反復で interleaving を揺らす。
    @Test @MainActor
    func cancelAll_racingWithRespond_resumesEachContinuationExactlyOnce() async throws {
        let iterations = 40
        let perIteration = 6
        for _ in 0..<iterations {
            let broker = ChatApprovalBroker()
            let completed = CompletionCounter()
            let collector = ApprovalIDCollector()

            // 承認要求ストリームを消費して id を得る（respond に渡すため）。
            let consumer = Task {
                var seen = 0
                let stream = await broker.requests
                for await approval in stream {
                    collector.append(approval.id)
                    seen += 1
                    if seen == perIteration { break }
                }
            }

            // pending を perIteration 件積む。各 handler は解決されるまで await する。
            for i in 0..<perIteration {
                let req = makeCommandApproval(index: i)
                Task.detached {
                    _ = try? await broker.serverRequestHandler(.commandExecutionApproval(req))
                    completed.increment()
                }
            }

            // 全 pending が登録され id が出そろうまで待つ。
            try await waitUntil { collector.count() == perIteration }
            let ids = collector.all()

            // respond（各 id を並行に）と cancelAll を同時発火する。
            async let responders: Void = withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { await broker.respond(to: id, decision: .accept) }
                }
            }
            async let canceller: Void = broker.cancelAll()
            _ = await (responders, canceller)

            // 全 continuation が resume されて await が復帰する（リークしない）。
            try await waitUntil { completed.get() == perIteration }
            consumer.cancel()
        }
    }

    /// cancelAll は pending を全て解決する。mixed-kind（command と permissions）でも
    /// resolve の両分岐を通って await が復帰する。
    @Test @MainActor
    func cancelAll_resolvesAllPending_acrossKinds() async throws {
        let broker = ChatApprovalBroker()
        let completed = CompletionCounter()
        let collector = ApprovalIDCollector()
        let total = 4

        let consumer = Task {
            var seen = 0
            let stream = await broker.requests
            for await approval in stream {
                collector.append(approval.id)
                seen += 1
                if seen == total { break }
            }
        }

        for i in 0..<2 {
            let cmd = makeCommandApproval(index: i)
            Task.detached {
                _ = try? await broker.serverRequestHandler(.commandExecutionApproval(cmd))
                completed.increment()
            }
            let perm = makePermissionsApproval(index: i)
            Task.detached {
                _ = try? await broker.serverRequestHandler(.permissionsApproval(perm))
                completed.increment()
            }
        }

        try await waitUntil { collector.count() == total }
        #expect(completed.get() == 0, "cancelAll 前に解決してしまっている")

        await broker.cancelAll()
        try await waitUntil { completed.get() == total }
        consumer.cancel()
    }

    /// cancelAll は冪等（pending 空での2回目以降は no-op でクラッシュしない）。
    @Test @MainActor
    func cancelAll_isIdempotentWhenNoPending() async {
        let broker = ChatApprovalBroker()
        await broker.cancelAll()
        await broker.cancelAll()
    }

    /// respond で解決済みの id を cancelAll が二重に resume しない（respond 先行→cancelAll）。
    @Test @MainActor
    func cancelAll_afterRespond_doesNotDoubleResume() async throws {
        let broker = ChatApprovalBroker()
        let completed = CompletionCounter()
        let collector = ApprovalIDCollector()

        let consumer = Task {
            let stream = await broker.requests
            for await approval in stream {
                collector.append(approval.id)
                break
            }
        }

        let req = makeCommandApproval(index: 0)
        Task.detached {
            _ = try? await broker.serverRequestHandler(.commandExecutionApproval(req))
            completed.increment()
        }

        try await waitUntil { collector.count() == 1 }
        let id = collector.all()[0]

        await broker.respond(to: id, decision: .accept)
        try await waitUntil { completed.get() == 1 }
        // 解決済み id に対する cancelAll は no-op（二重 resume すればここでクラッシュする）。
        await broker.cancelAll()
        #expect(completed.get() == 1)
        consumer.cancel()
    }
}
