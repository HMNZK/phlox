import AgentDomain
import AppBootstrap
import ControlServer
import DashboardFeature
import Foundation
import SessionFeature
import StructuredChatKit
import Testing

@MainActor
struct CompletionParityHandlerAcceptanceTests {
    @Test("完了確認の不在・token競合・成功を別々の応答にする", arguments: [404, 409, 204])
    func acknowledgementResponsePreservesOutcome(status: Int) async {
        let dashboard = CompletionDashboardStub(outcome: status == 404 ? nil : status == 204)
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        let id = SessionID()

        let response = await handler.handle(ControlRequest(requester: nil,
            action: .markCompletionSeen(id: id, completionToken: "exec:1")))

        #expect(response.statusCode == status)
        #expect(dashboard.receivedID == id)
        #expect(dashboard.receivedToken == "exec:1")
    }
}

@MainActor
private final class CompletionDashboardStub: ControlActionDashboard {
    var controlSessionSummaries: [ControlSessionSummary] = []
    private let outcome: Bool?
    private(set) var receivedID: SessionID?
    private(set) var receivedToken: String?
    init(outcome: Bool?) { self.outcome = outcome }
    func markCompletionSeen(_ id: SessionID, completionToken: String) async throws -> Bool? {
        receivedID = id
        receivedToken = completionToken
        return outcome
    }
    func spawnSession(ref: AgentRef, from: SessionID?, backend: SessionBackend, workingDirectory: String?,
                      projectID: ProjectID?, initialSettings: CodexAppServerSessionSettings?) async throws -> SessionID { SessionID() }
    func sendMessage(to recipient: Recipient, text: String, submit: Bool, from: SessionID?, inReplyTo: UUID?,
                     images: [ControlImageAttachment]) async -> DashboardViewModel.SendOutcome { .sent }
    func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
    func removeSession(_ id: SessionID) async -> Bool { true }
    func renameSession(_ id: SessionID, to name: String) {}
    func sessionOutput(for id: SessionID) -> String? { nil }
    func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
    func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
    func waitUntilDone(for id: SessionID, timeout: Duration, sentinel: String?) async -> DashboardViewModel.DoneResult { .done(output: "") }
    func listApprovals() async -> [ApprovalDTO] { [] }
    func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
    func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .accepted }
    func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
    func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
    func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
}
