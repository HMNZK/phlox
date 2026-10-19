import Foundation
import XCTest
import PhloxCore
@testable import Features

/// Errors の文言再生成ではなく、失敗を注入した本番VMの状態遷移を検査する。
@MainActor
final class RemainingErrorCatalogTests: XCTestCase {
    func testD3HTTPFailureRemovesStaleApprovalAndPollingCanRecover() async throws {
        try await verifyApprovalFailure(PhloxError.notFound)
    }

    func testD3UnexpectedFailureAlsoRemovesStaleApprovalAndCanRecover() async throws {
        try await verifyApprovalFailure(UnexpectedApprovalFailure())
    }

    private func verifyApprovalFailure(_ error: any Error & Sendable) async throws {
        let approval = Approval(id: "pending-1", sessionID: "remaining-session", kind: .codex, prompt: "git push")
        let api = RemainingCatalogAPI(approvals: [approval])
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.loadApprovals()
        XCTAssertEqual(vm.currentReplyApproval?.id, "codex:pending-1")

        await api.setApprovalFailure(error)
        await vm.loadApprovals()

        let presentation = try XCTUnwrap(vm.approvalLoadPresentation)
        XCTAssertEqual(presentation.title, "承認の内容を読み込めませんでした")
        XCTAssertEqual(presentation.cause, "承認待ちですが、何を許可するかを Mac から受け取れませんでした。")
        XCTAssertEqual(presentation.nextStep, "内容が読めるまで承認・却下は押せません。読み込み直しています。")
        XCTAssertEqual(presentation.technicalDetail, "承認情報の取得に失敗しました")
        XCTAssertEqual(vm.approvalLoadError, presentation.message)
        XCTAssertTrue(vm.replyApprovals.isEmpty, "取得できない以前の承認を操作可能なカードとして残さない")
        XCTAssertNil(vm.currentReplyApproval)
        XCTAssertEqual(vm.currentReplyApprovalPage, 0)
        let responses = await api.base.respondLog
        XCTAssertTrue(responses.isEmpty, "取得失敗だけで承認や却下を送らない")

        await api.setApprovalFailure(nil)
        await vm.loadApprovals()

        XCTAssertEqual(vm.currentReplyApproval?.id, "codex:pending-1")
        XCTAssertNil(vm.approvalLoadPresentation)
        XCTAssertNil(vm.approvalLoadError)
        let calls = await api.approvalCalls
        XCTAssertEqual(calls, 3)
    }

    func testF8CannotConfirmExistenceDoesNotClaimDeletionAndNextFetchCanConfirmIt() async {
        let api = MockAPI(messagesOutcome: .success([.agent(id: "history", text: "保持する会話")]))
        let vm = SessionDetailViewModel(session: session(), api: api)
        await vm.load()
        let history = vm.chatMessages
        await api.setMessagesOutcome(.failure(.notFound))
        await api.setListSessionsError(.unreachable)

        await vm.refresh()

        XCTAssertFalse(vm.isSessionMissing, "一覧照会も失敗した場合は削除済みと断定しない")
        XCTAssertEqual(vm.loadError, "セッションの存在を確認できませんでした · HTTP 404")
        XCTAssertEqual(vm.chatMessages, history)

        await api.setListSessionsError(nil)
        await vm.refresh()

        XCTAssertTrue(vm.isSessionMissing)
        XCTAssertEqual(vm.loadError, "HTTP 404 · session remaining-session")
        XCTAssertEqual(vm.chatMessages, history)
    }

    func testD6CascadeFailureDoesNotNotifyDeletionAndRetryClearsFailure() async throws {
        let api = RemainingCatalogAPI(approvals: [])
        await api.setRemoveFailure(.server(status: 403, message: "permission denied"))
        var deletedCount = 0
        let vm = DeleteConfirmationViewModel(
            sessionID: "remaining-session", cascadeCount: 2, api: api,
            onDeleted: { deletedCount += 1 }
        )

        await vm.confirmDelete()

        let presentation = try XCTUnwrap(vm.failurePresentation)
        XCTAssertEqual(presentation.cause, "セッションと子孫 2 件は、どれも消えずに残っています。")
        XCTAssertEqual(presentation.recoveryAction, "もう一度削除")
        XCTAssertEqual(presentation.technicalDetail, "HTTP 403 permission denied")
        XCTAssertEqual(deletedCount, 0)
        XCTAssertFalse(vm.isDeleting)
        guard case .failed = vm.state else { return XCTFail("削除失敗状態が必要") }

        await api.setRemoveFailure(nil)
        await vm.confirmDelete()

        XCTAssertEqual(vm.state, .deleted)
        XCTAssertNil(vm.failurePresentation)
        XCTAssertEqual(deletedCount, 1)
        let removedIDs = await api.removedIDs
        XCTAssertEqual(removedIDs, ["remaining-session", "remaining-session"])
    }

    func testF3NewChatCreationKeepsNeutralPresentationAndDraftWithoutCreatingSession() async throws {
        // 失敗経路ではsettingsを書かない。独立suiteを使い通常アプリの選択値も読まない。
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RemainingErrorCatalogTests.\(UUID().uuidString)"))
        let api = MockAPI(spawnOutcome: .failure(.rateLimited(retryAfter: 17)))
        await api.setProjectsOutcome(.success([ProjectSummary(id: "catalog-project", name: "Catalog")]))
        let vm = NewChatViewModel(
            api: api, entryProject: SessionComposeDraft(project: "Catalog"),
            settingsStore: NewChatSettingsStore(defaults: defaults)
        )
        await vm.load()
        vm.selectProject(id: "catalog-project")
        vm.inputText = "残す依頼"
        var created = false

        await vm.send { _, _ in created = true }

        let presentation = try XCTUnwrap(vm.creationErrorPresentation)
        XCTAssertTrue(presentation.isNeutral)
        XCTAssertEqual(presentation.technicalDetail, "HTTP 429 · Retry-After: 17")
        XCTAssertEqual(vm.inputText, "残す依頼")
        XCTAssertTrue(vm.canEditDraft)
        XCTAssertFalse(vm.hasCreatedSession)
        XCTAssertFalse(created)
        let spawnCalls = await api.spawnCount
        let sendCalls = await api.sendCount
        XCTAssertEqual(spawnCalls, 1)
        XCTAssertEqual(sendCalls, 0)
    }

    func testF3ListRefreshKeepsNeutralRateLimitPresentation() async throws {
        let vm = SessionListViewModel(repository: RateLimitedCatalogRepository())

        await vm.refresh()

        guard case .error(let error) = vm.state else { return XCTFail("429を一覧エラー状態として保持する") }
        XCTAssertTrue(error.presentation.isNeutral)
        XCTAssertEqual(error.presentation.technicalDetail, "HTTP 429 · Retry-After: 23")
    }

    private func session() -> Session {
        Session(
            id: "remaining-session", name: "Rose", agent: .codex,
            status: .awaitingApproval(prompt: "approval"), updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private struct UnexpectedApprovalFailure: Error, Sendable {}

private struct RateLimitedCatalogRepository: SessionRepositoryProtocol {
    func sessionStream(interval: Duration) -> AsyncStream<SessionsState> { AsyncStream { $0.finish() } }
    func refresh() async throws { throw PhloxError.rateLimited(retryAfter: 23) }
}

/// 既存の共有モックを委譲し、今回必要な承認取得/削除の失敗切替だけ追加する。
private actor RemainingCatalogAPI: PhloxAPI {
    let base = MockAPI()
    private let approvalItems: [Approval]
    private var approvalFailure: (any Error & Sendable)?
    private var removeFailure: PhloxError?
    private(set) var approvalCalls = 0
    private(set) var removedIDs: [String] = []

    init(approvals: [Approval]) { approvalItems = approvals }
    func setApprovalFailure(_ error: (any Error & Sendable)?) { approvalFailure = error }
    func setRemoveFailure(_ error: PhloxError?) { removeFailure = error }

    func approvals() async throws -> [Approval] {
        approvalCalls += 1
        if let approvalFailure { throw approvalFailure }
        return approvalItems
    }

    func remove(sessionID: String) async throws {
        removedIDs.append(sessionID)
        if let removeFailure { throw removeFailure }
    }

    func listSessions() async throws -> [Session] { try await base.listSessions() }
    func spawn(_ request: SpawnRequest) async throws -> Session { try await base.spawn(request) }
    func waitUntilReady(sessionID: String) async throws -> Bool { try await base.waitUntilReady(sessionID: sessionID) }
    func send(_ request: SendRequest) async throws -> SendResult { try await base.send(request) }
    func messages(sessionID: String) async throws -> [ChatMessage] { try await base.messages(sessionID: sessionID) }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {
        try await base.respond(approvalID: approvalID, decision: decision)
    }
}
