import Foundation
import PhloxCore
import Testing
@testable import Features

@MainActor
struct CompletionParityAcceptanceTests {
    @Test("背面では確認せず、前面ではその完了tokenだけを確認する")
    func viewingControlsAcknowledgementAndRefresh() async {
        let session = completionSession(token: "exec:1", unseen: true)
        let api = CompletionSessionAPI(session: session)
        let model = SessionDetailViewModel(session: session, api: api)
        await model.load()

        await model.setCompletionViewing(false)
        await model.refresh()
        #expect(await api.acknowledgedTokens.isEmpty)

        await model.setCompletionViewing(true)
        #expect(await api.acknowledgedTokens == ["exec:1"])
        #expect(!model.session.hasUnseenCompletion)
        #expect(model.completionSyncError == nil)

        await api.updateSession(completionSession(token: "exec:2", unseen: true))
        await model.refresh()
        #expect(await api.acknowledgedTokens == ["exec:1", "exec:2"])
        await model.refresh()
        #expect(await api.acknowledgedTokens == ["exec:1", "exec:2"])

        await model.setCompletionViewing(false)
        await api.updateSession(completionSession(token: "exec:3", unseen: true))
        await model.refresh()
        #expect(await api.acknowledgedTokens == ["exec:1", "exec:2"])
        #expect(model.session.hasUnseenCompletion)
    }

    @Test("確認送信に失敗したら未確認を保ち、前面で次回取り直す")
    func acknowledgementFailureRemainsVisibleAndCanRecover() async {
        let session = completionSession(token: "exec:1", unseen: true)
        let api = CompletionSessionAPI(session: session, error: .unreachable)
        let model = SessionDetailViewModel(session: session, api: api)
        await model.load()

        await model.setCompletionViewing(true)
        #expect(model.session.hasUnseenCompletion)
        #expect(model.completionSyncError != nil)

        await api.setAcknowledgementError(nil)
        await model.refresh()
        #expect(!model.session.hasUnseenCompletion)
        #expect(model.completionSyncError == nil)
        #expect(await api.acknowledgedTokens == ["exec:1", "exec:1"])
    }

    @Test("旧サーバーがtokenを返さない完了を勝手に確認済みにしない")
    func missingTokenDoesNotPretendToAcknowledge() async {
        let session = completionSession(token: nil, unseen: true)
        let api = CompletionSessionAPI(session: session)
        let model = SessionDetailViewModel(session: session, api: api)
        await model.load()

        await model.setCompletionViewing(true)

        #expect(await api.acknowledgedTokens.isEmpty)
        #expect(model.session.hasUnseenCompletion)
    }
}

private func completionSession(token: String?, unseen: Bool) -> Session {
    Session(id: "session-1", name: "Task", agent: .codex, status: .completed(exitCode: 0),
            subtitle: "Phlox", hasUnseenCompletion: unseen, completionToken: token,
            updatedAt: Date(timeIntervalSince1970: 1))
}

private actor CompletionSessionAPI: PhloxAPI {
    private var session: Session
    private var acknowledgementError: PhloxError?
    private(set) var acknowledgedTokens: [String] = []

    init(session: Session, error: PhloxError? = nil) {
        self.session = session
        acknowledgementError = error
    }
    func updateSession(_ session: Session) { self.session = session }
    func setAcknowledgementError(_ error: PhloxError?) { acknowledgementError = error }
    func listSessions() async throws -> [Session] { [session] }
    func markCompletionSeen(sessionID: String, completionToken: String) async throws {
        acknowledgedTokens.append(completionToken)
        if let acknowledgementError { throw acknowledgementError }
        guard session.completionToken == completionToken else {
            throw PhloxError.server(status: 409, message: "completion changed")
        }
        session = completionSession(token: completionToken, unseen: false)
    }
    func spawn(_ request: SpawnRequest) async throws -> Session { session }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}
