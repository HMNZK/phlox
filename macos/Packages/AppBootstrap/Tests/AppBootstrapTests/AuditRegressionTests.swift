import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import SessionFeature
@testable import AppBootstrap

/// task-5（監査）回帰:
/// - I4 IDOR: `.rename` に自己/祖先認可を課す（未認可→403）。read 系（output/messages/wait/
///   waitReady/listSessions）は operator モデルとして認可を課さない（未認可でも従来どおり）。
/// - S ShellQuoting: dispatcher パス中のシングルクォートを ShellQuoting.singleQuoted でエスケープ。
/// - S BinaryPathResolver: stdout を waitUntilExit より前に読み切り、>64KB 出力で deadlock しない。
@MainActor
@Suite struct AuditRegressionTests {
    @MainActor
    private final class Stub: ControlActionDashboard {
        var isAuthorized = true
        private(set) var renamedTo: (id: SessionID, name: String)?
        var outputText: String? = "screen"
        var chatMessages: [ChatItem]? = []
        var doneResult: DashboardViewModel.DoneResult = .done(output: "")

        var controlSessionSummaries: [ControlSessionSummary] = []
        func sendMessage(to recipient: Recipient, text: String, submit: Bool, from: SessionID?, inReplyTo: UUID?, images: [ControlImageAttachment]) async -> DashboardViewModel.SendOutcome { .sent }
        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID { SessionID() }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { isAuthorized }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) { renamedTo = (id, name) }
        func sessionOutput(for id: SessionID) -> String? { outputText }
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
            chatMessages.map { TranscriptDelta(items: $0, cursor: "audit-cursor", isSnapshot: false) }
        }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(for id: SessionID, timeout: Duration, sentinel: String?) async -> DashboardViewModel.DoneResult { doneResult }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .accepted }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    private func makeHandler(_ stub: Stub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = stub
        return handler
    }

    private func request(_ action: ControlRequest.Action, requester: SessionID? = nil) -> ControlRequest {
        ControlRequest(requester: requester, action: action)
    }

    // MARK: - I4 IDOR: rename は認可を課す

    @Test func renameWithoutAuthorizationReturns403() async {
        let stub = Stub()
        stub.isAuthorized = false
        let handler = makeHandler(stub)

        let response = await handler.handle(request(.rename(id: SessionID(), name: "x"), requester: SessionID()))

        #expect(response.statusCode == 403)
        #expect(stub.renamedTo == nil, "未認可なのに rename が実行された（IDOR）")
    }

    @Test func renameWithAuthorizationReturns200() async {
        let stub = Stub()
        stub.isAuthorized = true
        let handler = makeHandler(stub)
        let id = SessionID()

        let response = await handler.handle(request(.rename(id: id, name: "renamed"), requester: SessionID()))

        #expect(response.statusCode == 200)
        #expect(stub.renamedTo?.id == id)
        #expect(stub.renamedTo?.name == "renamed")
    }

    // MARK: - read 系は operator モデル（未認可でも従来どおり・403 にしない）

    @Test func readOperationsAreNotBlockedByAuthorization() async {
        let stub = Stub()
        stub.isAuthorized = false  // 要求元は対象の祖先でない
        stub.outputText = "screen text"
        stub.chatMessages = []
        stub.doneResult = .done(output: "done")
        let handler = makeHandler(stub)
        let requester = SessionID()

        let output = await handler.handle(request(.output(id: SessionID(), mode: .screen), requester: requester))
        #expect(output.statusCode == 200, "read(output) が認可で 403 になった（operator モデル違反）")

        let messages = await handler.handle(request(.messages(id: SessionID(), since: nil, wait: nil), requester: requester))
        #expect(messages.statusCode == 200, "read(messages) が認可で 403 になった")

        let wait = await handler.handle(request(.wait(id: SessionID(), timeoutSeconds: 1, sentinel: nil), requester: requester))
        #expect(wait.statusCode == 200, "read(wait) が認可で 403 になった")
    }

    // MARK: - S ShellQuoting: dispatcher のシングルクォートをエスケープ

    @Test func settingsEscapesSingleQuotesInDispatcherPath() throws {
        let dispatcher = "/Users/x/it's a/dir/hook-dispatcher.sh"
        let settings = ClaudeSettingsGenerator.settings(
            defaultMode: "default",
            dispatcher: dispatcher,
            statusLineCommand: "sl"
        )
        let command = try firstHookCommand(settings, event: "SessionStart")
        // 期待: '/Users/x/it'\''s a/dir/hook-dispatcher.sh' sessionStart
        let expectedQuoted = ShellQuoting.singleQuoted(dispatcher)
        #expect(command == "\(expectedQuoted) sessionStart")
        // クォートを閉じずに連結する形（生の未エスケープ 'it's ' が出ない）を確認。
        #expect(command.contains("'\\''"))
        #expect(!command.contains("'it's a'"))
    }

    private func firstHookCommand(_ settings: [String: Any], event: String) throws -> String {
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let matchers = try #require(hooks[event] as? [[String: Any]])
        let inner = try #require(matchers.first?["hooks"] as? [[String: Any]])
        return try #require(inner.first?["command"] as? String)
    }

    // MARK: - S BinaryPathResolver: 64KB 超 stdout でも deadlock せず全読み取り

    @Test func runAndReadStdoutDoesNotDeadlockOnLargeOutput() throws {
        // 200KB の 'A' を stdout に出す子。パイプ既定 64KB を大きく超える。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "head -c 200000 /dev/zero | tr '\\0' 'A'"]

        let output = BinaryPathResolver.runAndReadStdout(process)
        #expect(output?.count == 200_000, "64KB 超の stdout が全量読み取れていない（deadlock/切り詰め）")
    }
}
