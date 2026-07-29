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
/// 契約（tasks/wire-contract.md §1・§2）: ハンドラ層は
///  - `Action.spawn` の `projectID` をそのまま `spawnSession(projectID:)` へ渡す
///  - `AgentSpawnError.unknownProject` を **422 `{"error":"unknown projectId"}`** に写す
///    （iOS は 422 のみ `spawnRejected(reason:)` として理由を画面に出せるため）
///  - 既存の rate limit 429 / depth 403 / その他 400 の対応表は変えない
@MainActor
@Suite struct AcceptanceSpawnProjectIdHandlerTests {
    @MainActor
    private final class ProjectSpawnDashboardStub: ControlActionDashboard {
        var controlSessionSummaries: [ControlSessionSummary] = []
        var spawnResult: Result<SessionID, any Error> = .success(SessionID())
        private(set) var receivedProjectID: ProjectID?
        private(set) var receivedWorkingDirectory: String?
        private(set) var spawnCallCount = 0

        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome {
            .sent
        }

        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?,
            projectID: ProjectID?
        ) async throws -> SessionID {
            spawnCallCount += 1
            receivedProjectID = projectID
            receivedWorkingDirectory = workingDirectory
            return try spawnResult.get()
        }

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

    private func makeHandler(_ dashboard: ProjectSpawnDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func spawnRequest(projectID: ProjectID?, workingDirectory: String? = nil) -> ControlRequest {
        ControlRequest(
            requester: nil,
            action: .spawn(
                ref: .builtin(.claudeCode),
                backend: .appServer,
                workingDirectory: workingDirectory,
                projectID: projectID
            )
        )
    }

    @Test("projectID はそのまま spawnSession へ渡り 201 を返す")
    func handlerForwardsProjectID() async throws {
        let projectID = ProjectID()
        let dashboard = ProjectSpawnDashboardStub()
        let response = await makeHandler(dashboard).handle(spawnRequest(projectID: projectID))

        #expect(response.statusCode == 201)
        #expect(dashboard.receivedProjectID == projectID)
    }

    @Test("projectID 省略時は nil のまま渡す（後方互換）")
    func handlerForwardsNilProjectID() async throws {
        let dashboard = ProjectSpawnDashboardStub()
        let response = await makeHandler(dashboard).handle(spawnRequest(projectID: nil))

        #expect(response.statusCode == 201)
        #expect(dashboard.receivedProjectID == nil)
    }

    @Test("未知の projectID は 422 と unknown projectId を返し spawn 失敗を隠さない")
    func unknownProjectMapsTo422() async throws {
        let dashboard = ProjectSpawnDashboardStub()
        dashboard.spawnResult = .failure(AgentSpawnError.unknownProject)

        let response = await makeHandler(dashboard).handle(spawnRequest(projectID: ProjectID()))

        #expect(response.statusCode == 422)
        let body = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(body["error"] as? String == "unknown projectId")
    }

    @Test("既存のエラー対応表（rate limit 429 / depth 403）は変えない")
    func existingSpawnErrorMappingUnchanged() async throws {
        let rateLimited = ProjectSpawnDashboardStub()
        rateLimited.spawnResult = .failure(AgentSpawnError.spawnRateLimited)
        #expect(await makeHandler(rateLimited).handle(spawnRequest(projectID: nil)).statusCode == 429)

        let tooDeep = ProjectSpawnDashboardStub()
        tooDeep.spawnResult = .failure(AgentSpawnError.depthLimitExceeded)
        #expect(await makeHandler(tooDeep).handle(spawnRequest(projectID: nil)).statusCode == 403)
    }
}
