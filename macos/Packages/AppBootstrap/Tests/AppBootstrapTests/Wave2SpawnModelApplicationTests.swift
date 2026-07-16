import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

/// task-1 受け入れ回帰テスト（PM 著・凍結。アサーション変更禁止。ハーネス欠陥は PM 承認の上で修理可）。
///
/// deep ハザード「spawn 後のモデル適用」の end-to-end 不変条件を stub dashboard で観測する:
/// `ControlActionHandler.handleSpawn` は、`ControlSpawnContext.model` が非 nil のとき、
/// **spawn 完了後に生成された session id（requester ではない）へ** `setSessionModel` を適用してから
/// 201 を返す。model 未指定なら setSessionModel を呼ばず従来動作（201）を維持する。
/// （applier 単体の素通しではなく handleSpawn の実配線を検証する。）
@MainActor
@Suite struct Wave2SpawnModelApplicationTests {
    @MainActor
    private final class ModelDashboardStub: ControlActionDashboard {
        let spawnedID = SessionID()
        private(set) var spawnCallCount = 0
        private(set) var appliedModel: (id: SessionID, model: String)?

        var controlSessionSummaries: [ControlSessionSummary] = []

        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID {
            spawnCallCount += 1
            return spawnedID
        }

        func setSessionModel(_ model: String, for id: SessionID) async -> Bool {
            appliedModel = (id, model)
            return true
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

    private func makeHandler(_ dashboard: ModelDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func spawnRequest() -> ControlRequest {
        ControlRequest(
            requester: nil,
            action: .spawn(ref: .builtin(.claudeCode), backend: .appServer, workingDirectory: nil)
        )
    }

    @Test func spawnAppliesModelToSpawnedSessionAfterSpawn() async throws {
        let dashboard = ModelDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await ControlSpawnContext.$model.withValue("opus") {
            await handler.handle(spawnRequest())
        }

        #expect(response.statusCode == 201)
        #expect(dashboard.spawnCallCount == 1)
        // 生成された session id（requester ではない）へ、指定モデルが適用される。
        #expect(dashboard.appliedModel?.id == dashboard.spawnedID)
        #expect(dashboard.appliedModel?.model == "opus")
    }

    @Test func spawnWithoutModelDoesNotApplyModel() async throws {
        let dashboard = ModelDashboardStub()
        let handler = makeHandler(dashboard)

        let response = await ControlSpawnContext.$model.withValue(nil) {
            await handler.handle(spawnRequest())
        }

        #expect(response.statusCode == 201)
        #expect(dashboard.spawnCallCount == 1)
        #expect(dashboard.appliedModel == nil)
    }
}
