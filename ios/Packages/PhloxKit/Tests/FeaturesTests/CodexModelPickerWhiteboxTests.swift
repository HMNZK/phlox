import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite(.serialized)
struct CodexModelPickerWhiteboxTests {
    @Test func nonEmptyCodexCatalogCreatesModelEntriesInsteadOfAgentOnlyEntry() async {
        let viewModel = SessionDetailViewModel(
            session: Session(
                id: "draft-compose",
                name: "phlox",
                agent: .claudeCode,
                status: .running,
                subtitle: "phlox",
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            api: NonEmptyCodexCatalogAPI()
        )

        await viewModel.prepareDraft(SessionComposeDraft(project: "phlox"))

        let codexEntries = viewModel.modelPickerEntries.filter { $0.kind == .codex }
        #expect(codexEntries.map(\.modelID) == ["gpt-5.3-codex", "gpt-5.2"])
        #expect(codexEntries.map(\.displayName) == ["GPT-5.3 Codex", "GPT-5.2"])
    }
}

private actor NonEmptyCodexCatalogAPI: PhloxAPI {
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        switch kind {
        case .claudeCode:
            AgentModels(models: [], defaultModel: nil)
        case .cursor:
            AgentModels(models: [], defaultModel: nil)
        case .codex:
            AgentModels(
                models: [
                    SessionModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex"),
                    SessionModelOption(id: "gpt-5.2", displayName: "GPT-5.2"),
                ],
                defaultModel: "gpt-5.3-codex"
            )
        }
    }

    func spawn(_ request: SpawnRequest) async throws -> Session { fatalError("Not used") }
    func waitUntilReady(sessionID: String) async throws -> Bool { fatalError("Not used") }
    func send(_ request: SendRequest) async throws -> SendResult { fatalError("Not used") }
    func listSessions() async throws -> [Session] { [] }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
