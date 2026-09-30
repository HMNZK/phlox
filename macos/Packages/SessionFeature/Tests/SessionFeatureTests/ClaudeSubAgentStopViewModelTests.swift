import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

/// Claude サブエージェントの個別停止（VM 経由）。stop_task の送信・確認待ち・失敗/タイムアウトでの復帰・確認後の消去。
@Suite("Claude サブエージェントの個別停止（VM）")
@MainActor
struct ClaudeSubAgentStopViewModelTests {
    private final class StopClient: StructuredAgentClient, SubAgentStopping, @unchecked Sendable {
        let events: AsyncStream<NormalizedChatEvent>
        private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
        private let lock = NSLock()
        private var _stopped: [String] = []
        private var _attempts: [Int] = []
        var stopped: [String] { lock.withLock { _stopped } }
        var attempts: [Int] { lock.withLock { _attempts } }

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
        func stopSubAgent(toolUseId: String, attempt: Int) async throws { lock.withLock { _stopped.append(toolUseId); _attempts.append(attempt) } }
        func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    }

    private func make() -> (ChatSessionViewModel, StopClient) {
        let client = StopClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-subagent-stop-vm-test"
        )
        return (vm, client)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for condition")
    }

    private func startChild(_ vm: ChatSessionViewModel, _ client: StopClient) async throws {
        client.yield(.turnStarted)
        client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "general-purpose", description: "bg"))
        client.yield(.subAgentStopAvailable(toolUseId: "tu1"))
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .available }
    }

    @Test("停止を押すと stop_task を要求し、確認までは実行中の札のまま停止中になる")
    func stopRequestsAndWaitsForConfirmation() async throws {
        let (vm, client) = make()
        try await startChild(vm, client)

        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { client.stopped == ["tu1"] }

        #expect(vm.subAgentStopState(forDisplayID: "tu1") == .stopping)
        #expect(vm.stripSubAgents.contains { $0.id == "tu1" && $0.status == .running })

        vm.stopSubAgent(displayID: "tu1")
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.stopped == ["tu1"], "停止中の二重押しは送らない")
    }

    @Test("停止の確認（stopped 通知）が来たら札が消え、会話マーカー用の状態は停止になる")
    func confirmedStopRemovesTheChip() async throws {
        let (vm, client) = make()
        try await startChild(vm, client)
        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { client.stopped == ["tu1"] }

        client.yield(.subAgentCompleted(toolUseId: "tu1", status: "stopped", summary: "", outputFile: nil))
        try await waitUntil { vm.subAgents.first?.status == .stopped }

        #expect(!vm.stripSubAgents.contains { $0.id == "tu1" })
        #expect(vm.subAgentStopState(forDisplayID: "tu1") == nil)
    }

    @Test("停止要求が失敗したら、停止中が解除されて実行中のまま再び押せる")
    func failedStopReturnsToAvailable() async throws {
        let (vm, client) = make()
        try await startChild(vm, client)
        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .stopping }

        client.yield(.subAgentStopFailed(toolUseId: "tu1", attempt: 1))
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .available }
        #expect(vm.stripSubAgents.contains { $0.id == "tu1" && $0.status == .running })
    }

    @Test("確認が来ないままタイムアウトしたら、停止中が解除される")
    func timeoutReleasesStopping() async throws {
        let (vm, client) = make()
        vm.subAgentStopTimeout = .milliseconds(50)
        try await startChild(vm, client)
        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .stopping }

        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .available }
    }

    @Test("stop_task の宛先が分かる前は、押しても何も送らない")
    func noStopBeforeTheTaskIsKnown() async throws {
        let (vm, client) = make()
        client.yield(.turnStarted)
        client.yield(.subAgentStarted(toolUseId: "tu1", subagentType: "x", description: "bg"))
        try await waitUntil { vm.subAgents.contains { $0.id == "tu1" } }

        vm.stopSubAgent(displayID: "tu1")
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.stopped.isEmpty)
        #expect(vm.subAgentStopState(forDisplayID: "tu1") == nil)
    }

    @Test("停止確定のあとに届く完了・失敗（親の tool_result 由来）で、停止は上書きされず札も戻らない")
    func laterCompletionOrFailureDoesNotOverwriteStopped() async throws {
        for later in ["completed", "failed"] {
            let (vm, client) = make()
            try await startChild(vm, client)
            client.yield(.subAgentCompleted(toolUseId: "tu1", status: "stopped", summary: "", outputFile: nil))
            try await waitUntil { vm.subAgents.first?.status == .stopped }

            client.yield(.subAgentCompleted(toolUseId: "tu1", status: later, summary: "The user doesn't want to proceed", outputFile: nil))
            client.yield(.turnCompleted(nativeSessionId: nil))
            try await waitUntil { vm.status == .idle }

            #expect(vm.subAgents.first?.status == .stopped, "\(later)")
            #expect(!vm.stripSubAgents.contains { $0.id == "tu1" }, "\(later)")
        }
    }

    @Test("再試行のあとに届いた 1 回目への遅れた失敗応答は、今の停止待ちとタイマーを解除しない")
    func lateFailureOfEarlierAttemptIsIgnored() async throws {
        let (vm, client) = make()
        try await startChild(vm, client)
        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { client.attempts == [1] }
        client.yield(.subAgentStopFailed(toolUseId: "tu1", attempt: 1))
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .available }

        vm.subAgentStopTimeout = .milliseconds(700)
        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { client.attempts == [1, 2] }

        // 1 回目への遅れた応答。あとの sentinel が処理された時点で、この応答も処理済み（イベントは順に届く）。
        client.yield(.subAgentStopFailed(toolUseId: "tu1", attempt: 1))
        client.yield(.subAgentStarted(toolUseId: "tu2", subagentType: "x", description: "sentinel"))
        try await waitUntil { vm.subAgents.contains { $0.id == "tu2" } }
        #expect(vm.subAgentStopState(forDisplayID: "tu1") == .stopping)

        // 2 回目のタイマーは生きていて、確認が来なければ解除される。
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .available }
    }

    @Test("今の試行への失敗応答は停止中を解除する")
    func failureOfCurrentAttemptReleasesStop() async throws {
        let (vm, client) = make()
        try await startChild(vm, client)
        vm.stopSubAgent(displayID: "tu1")
        try await waitUntil { client.attempts == [1] }

        client.yield(.subAgentStopFailed(toolUseId: "tu1", attempt: 1))
        try await waitUntil { vm.subAgentStopState(forDisplayID: "tu1") == .available }
    }
}
