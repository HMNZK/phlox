import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

@MainActor
@Suite struct UserQuestionWireWhiteboxTests {
  @MainActor
  private final class DeltaDashboardStub: ControlActionDashboard {
    var deltaResponse: TranscriptDelta?

    func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
      deltaResponse
    }

    var controlSessionSummaries: [ControlSessionSummary] = []
    func sendMessage(
      to recipient: Recipient,
      text: String,
      submit: Bool,
      from: SessionID?,
      inReplyTo: UUID?,
      images: [ControlImageAttachment]
    ) async -> DashboardViewModel.SendOutcome { .sent }
    func spawnSession(
      ref: AgentRef,
      from: SessionID?,
      backend: SessionBackend,
      workingDirectory: String?
    ) async throws -> SessionID { SessionID() }
    func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
    func removeSession(_ id: SessionID) async -> Bool { true }
    func renameSession(_ id: SessionID, to name: String) {}
    func sessionOutput(for id: SessionID) -> String? { nil }
    func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
    func waitUntilDone(
      for id: SessionID,
      timeout: Duration,
      sentinel: String?
    ) async -> DashboardViewModel.DoneResult { .done(output: "") }
    func listApprovals() async -> [ApprovalDTO] { [] }
    func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
    func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .notFound }
    func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
    func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
    func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
  }

  private func bodyJSON(_ response: ControlResponse) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
  }

  @Test func expiredUserQuestionUsesWireStateKey() async throws {
    let dashboard = DeltaDashboardStub()
    dashboard.deltaResponse = TranscriptDelta(
      items: [.userQuestion(
        id: "q-expired",
        requestId: "req-exp",
        questions: [
          ChatUserQuestion(
            question: "続行?",
            header: "Confirm",
            options: [ChatUserQuestionOption(label: "yes")],
            multiSelect: false
          ),
        ],
        answers: nil,
        state: .expired,
        timestamp: Date()
      )],
      cursor: "c-exp",
      isSnapshot: false
    )
    let handler = ControlActionHandler()
    handler.dashboard = dashboard

    let response = await handler.handle(
      ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
    )

    #expect(response.statusCode == 200)
    let message = try #require((try bodyJSON(response)["messages"] as? [[String: Any]])?.first)
    #expect(message["state"] as? String == ControlQuestionWireContract.stateExpired)
    #expect(message["answers"] == nil)
  }

  @Test func userQuestionWireUsesContractKeysOnly() async throws {
    let dashboard = DeltaDashboardStub()
    dashboard.deltaResponse = TranscriptDelta(
      items: [.userQuestion(
        id: "q-keys",
        requestId: "req-keys",
        questions: [
          ChatUserQuestion(
            question: "Q?",
            header: "H",
            options: [ChatUserQuestionOption(label: "only")],
            multiSelect: true
          ),
        ],
        answers: ["Q?": ["only"]],
        state: .answered,
        timestamp: Date()
      )],
      cursor: "c-keys",
      isSnapshot: false
    )
    let handler = ControlActionHandler()
    handler.dashboard = dashboard

    let response = await handler.handle(
      ControlRequest(requester: nil, action: .messages(id: SessionID(), since: nil, wait: nil))
    )

    let message = try #require((try bodyJSON(response)["messages"] as? [[String: Any]])?.first)
    #expect(Set(message.keys).isSuperset(of: [
      "id", "type",
      ControlQuestionWireContract.requestIdKey,
      ControlQuestionWireContract.stateKey,
      ControlQuestionWireContract.questionsKey,
      ControlQuestionWireContract.answersKey,
    ]))
    #expect(message["text"] == nil)
  }
}
