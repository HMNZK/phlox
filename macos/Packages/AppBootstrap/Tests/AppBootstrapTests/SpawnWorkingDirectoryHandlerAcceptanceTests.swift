import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

/// task-1 受け入れテスト（PM 著・凍結。アサーションの変更は禁止。ハーネス欠陥を
/// 発見した場合は PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
///
/// 契約: `ControlActionDashboard.spawnSession` は `workingDirectory: String?` を受け取り、
/// `ControlActionHandler.handleSpawn` が**単一の関所**として検証する:
/// - nil → そのまま nil を透過（現行挙動の完全維持）
/// - 絶対パスの既存ディレクトリ → 値をそのまま透過し spawn 続行（201）
/// - 相対パス・不存在・非ディレクトリ（ファイル）・空文字 → 400 を返し
///   dashboard.spawnSession を**呼ばない**（黙って親継承へフォールバックしない）。
///   エラーメッセージには "workingDirectory" を含める（CLI 利用者の自己診断用）。
@MainActor
@Suite struct SpawnWorkingDirectoryHandlerAcceptanceTests {
    @MainActor
    private final class WDDashboardStub: ControlActionDashboard {
        var controlSessionSummaries: [ControlSessionSummary] = []
        var spawnResult: Result<SessionID, any Error> = .success(SessionID())
        private(set) var spawnCallCount = 0
        private(set) var receivedWorkingDirectory: String?

        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID {
            spawnCallCount += 1
            receivedWorkingDirectory = workingDirectory
            return try spawnResult.get()
        }

        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome { .sent }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { nil }
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .accepted }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    private func makeHandler(_ dashboard: WDDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func spawnRequest(workingDirectory: String?) -> ControlRequest {
        ControlRequest(
            requester: nil,
            action: .spawn(ref: .builtin(.claudeCode), backend: .pty, workingDirectory: workingDirectory)
        )
    }

    private func errorText(_ response: ControlResponse) throws -> String {
        let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        return try #require(json["error"] as? String)
    }

    /// テストごとの使い捨てディレクトリ/ファイル。
    private func makeTempDir() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wd-acceptance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeTempFile() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wd-acceptance-file-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        return url.path
    }

    @Test func nilWorkingDirectoryPassesNilThrough() async throws {
        let dashboard = WDDashboardStub()
        let id = SessionID()
        dashboard.spawnResult = .success(id)
        let handler = makeHandler(dashboard)

        let response = await handler.handle(spawnRequest(workingDirectory: nil))

        #expect(response.statusCode == 201)
        #expect(dashboard.spawnCallCount == 1)
        #expect(dashboard.receivedWorkingDirectory == nil)
    }

    @Test func validAbsoluteDirectoryPassesThroughVerbatim() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dashboard = WDDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(spawnRequest(workingDirectory: dir))

        #expect(response.statusCode == 201)
        #expect(dashboard.spawnCallCount == 1)
        #expect(dashboard.receivedWorkingDirectory == dir)
    }

    @Test func relativePathRejected400WithoutSpawning() async throws {
        let dashboard = WDDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(spawnRequest(workingDirectory: "relative/dir"))

        #expect(response.statusCode == 400)
        #expect(dashboard.spawnCallCount == 0)
        #expect(try errorText(response).contains("workingDirectory"))
    }

    @Test func nonexistentPathRejected400WithoutSpawning() async throws {
        let dashboard = WDDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            spawnRequest(workingDirectory: "/nonexistent-\(UUID().uuidString)")
        )

        #expect(response.statusCode == 400)
        #expect(dashboard.spawnCallCount == 0)
        #expect(try errorText(response).contains("workingDirectory"))
    }

    @Test func filePathRejected400WithoutSpawning() async throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: file) }
        let dashboard = WDDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(spawnRequest(workingDirectory: file))

        #expect(response.statusCode == 400)
        #expect(dashboard.spawnCallCount == 0)
        #expect(try errorText(response).contains("workingDirectory"))
    }

    @Test func emptyStringRejected400WithoutSpawning() async throws {
        let dashboard = WDDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(spawnRequest(workingDirectory: ""))

        #expect(response.statusCode == 400)
        #expect(dashboard.spawnCallCount == 0)
        #expect(try errorText(response).contains("workingDirectory"))
    }
}
