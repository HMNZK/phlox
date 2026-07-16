import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite struct Wave5MenuPresentationTests {
    @Test func renameCanBePresentedRepeatedlyAfterDismissal() {
        let viewModel = makeViewModel()

        for _ in 0..<3 {
            viewModel.beginRename()
            #expect(viewModel.isRenamePresented)

            viewModel.isRenamePresented = false
            #expect(!viewModel.isRenamePresented)
        }
    }

    @Test func modelPickerCanBePresentedRepeatedlyAfterDismissal() {
        let viewModel = makeViewModel()

        for _ in 0..<3 {
            viewModel.beginModelSelection()
            #expect(viewModel.isModelSheetPresented)

            viewModel.isModelSheetPresented = false
            #expect(!viewModel.isModelSheetPresented)
        }
    }

    @Test func openingRenameDismissesModelPicker() {
        let viewModel = makeViewModel()
        viewModel.beginModelSelection()

        viewModel.beginRename()

        #expect(viewModel.isRenamePresented)
        #expect(!viewModel.isModelSheetPresented)
    }

    @Test func openingModelPickerDismissesRename() {
        let viewModel = makeViewModel()
        viewModel.beginRename()

        viewModel.beginModelSelection()

        #expect(viewModel.isModelSheetPresented)
        #expect(!viewModel.isRenamePresented)
    }

    private func makeViewModel() -> SessionDetailViewModel {
        SessionDetailViewModel(
            session: Session(
                id: "session-1",
                name: "Rose",
                agent: .claudeCode,
                status: .idle,
                subtitle: "",
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            api: MenuPresentationAPI()
        )
    }
}

private actor MenuPresentationAPI: PhloxAPI {
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(
            id: "spawned",
            name: "Spawned",
            agent: request.agent,
            status: .starting,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
