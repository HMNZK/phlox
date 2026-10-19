import XCTest
import PhloxCore
@testable import Features

// E4-9 検証。削除成功で popToRoot 相当コールバック、失敗でエラー、子孫件数表示、二段確認前は API 非呼び出し。
@MainActor
final class DeleteConfirmationViewModelTests: XCTestCase {

    func testSuccessfulDeleteInvokesOnDeleted() async {
        var deleted = false
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0, api: MockAPI(), onDeleted: { deleted = true })
        await vm.confirmDelete()
        XCTAssertEqual(vm.state, .deleted)
        XCTAssertTrue(deleted, "削除成功で popToRoot 相当が呼ばれる")
    }

    func testFailedDeleteShowsError() async {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0,
                                             api: MockAPI(removeError: .server(status: 403, message: "許可が必要です")),
                                             onDeleted: {})
        await vm.confirmDelete()
        if case .failed(let message) = vm.state {
            XCTAssertTrue(message.contains("セッションは消えずに残っています。"))
            XCTAssertTrue(message.contains("閉じるか、もう一度削除します。"))
            XCTAssertTrue(message.hasSuffix("HTTP 403 許可が必要です"))
        } else {
            XCTFail("expected .failed")
        }
        XCTAssertEqual(vm.failurePresentation?.title, "削除できませんでした")
        XCTAssertEqual(vm.failurePresentation?.cause, "セッションは消えずに残っています。")
        XCTAssertEqual(vm.failurePresentation?.nextStep, "閉じるか、もう一度削除します。")
        XCTAssertEqual(vm.failurePresentation?.technicalDetail, "HTTP 403 許可が必要です")
    }

    func testCascadeCountMessage() {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 3, api: MockAPI(), onDeleted: {})
        XCTAssertEqual(vm.message, "子孫のセッション 3 件も一緒に削除されます。合わせて 4 件です。元に戻せません。")
        XCTAssertEqual(vm.deleteButtonLabel, "4 件を削除")
    }

    func testImmediateIdenticalFailuresProduceDistinctPresentationEvents() async {
        let api = MockAPI(removeError: .server(status: 503, message: "削除できません"))
        var deletedCount = 0
        let vm = DeleteConfirmationViewModel(
            sessionID: "retry", cascadeCount: 2, api: api,
            onDeleted: { deletedCount += 1 }
        )
        XCTAssertEqual(vm.failureGeneration, 0)

        await vm.confirmDelete()
        let firstState = vm.state
        let firstPresentation = vm.failurePresentation
        XCTAssertNotNil(firstPresentation)
        XCTAssertEqual(vm.failureGeneration, 1)

        await vm.confirmDelete()
        XCTAssertEqual(vm.state, firstState)
        XCTAssertEqual(vm.failurePresentation, firstPresentation)
        XCTAssertEqual(vm.failureGeneration, 2, "同文の失敗でも再提示を通知する")
        let removeCount = await api.removeCount
        XCTAssertEqual(removeCount, 2)
        XCTAssertEqual(deletedCount, 0)
    }

    func testZeroCascadeMessage() {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0, api: MockAPI(), onDeleted: {})
        XCTAssertEqual(vm.message, "Mac 側のセッションと会話の記録が削除されます。元に戻せません。")
        XCTAssertEqual(vm.title, "“セッション” を削除しますか？")
        XCTAssertEqual(vm.deleteButtonLabel, "1 件を削除")
    }

    func testConcurrentDeleteAndPostSuccessCallsDoNotRepeatRemoval() async {
        let api = SuspendedDeleteAPI()
        var deletedCount = 0
        let vm = DeleteConfirmationViewModel(
            sessionID: "single-removal", cascadeCount: 0, api: api,
            onDeleted: { deletedCount += 1 }
        )
        let first = Task { await vm.confirmDelete() }
        await api.waitForFirstRemove()
        XCTAssertEqual(vm.state, .deleting)

        await vm.confirmDelete()
        let pendingRemoveCount = await api.removeCount
        XCTAssertEqual(pendingRemoveCount, 1)
        XCTAssertEqual(deletedCount, 0)

        await api.completeFirstRemove()
        await first.value
        XCTAssertEqual(vm.state, .deleted)
        XCTAssertEqual(deletedCount, 1)
        await vm.confirmDelete()
        let finalRemoveCount = await api.removeCount
        XCTAssertEqual(finalRemoveCount, 1)
        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(vm.failureGeneration, 0)
    }

    func testTitleUsesSessionName() {
        let vm = DeleteConfirmationViewModel(
            sessionID: "s1", sessionName: "Rose", cascadeCount: 0, api: MockAPI(), onDeleted: {}
        )
        XCTAssertEqual(vm.title, "“Rose” を削除しますか？")
    }

    func testDescendantCountIncludesChildrenAndGrandchildren() {
        let sessions = [
            Session(id: "root", name: "Root", agent: .claudeCode, status: .idle, updatedAt: .now),
            Session(id: "child", name: "Child", agent: .claudeCode, status: .idle, parentSessionId: "root", updatedAt: .now),
            Session(id: "grandchild", name: "Grandchild", agent: .claudeCode, status: .idle, parentSessionId: "child", updatedAt: .now),
            Session(id: "unrelated", name: "Other", agent: .claudeCode, status: .idle, updatedAt: .now),
        ]

        XCTAssertEqual(DeleteConfirmationViewModel.descendantCount(sessionID: "root", sessions: sessions), 2)
    }

    func testMissingParentIDsUseNoDescendantCount() {
        let sessions = [
            Session(id: "root", name: "Root", agent: .claudeCode, status: .idle, updatedAt: .now),
            Session(id: "child", name: "Child", agent: .claudeCode, status: .idle, updatedAt: .now),
        ]

        XCTAssertEqual(DeleteConfirmationViewModel.descendantCount(sessionID: "root", sessions: sessions), 0)
    }

    func testDoesNotCallAPIBeforeConfirmation() async {
        let mock = MockAPI()
        _ = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0, api: mock, onDeleted: {})
        let count = await mock.removeCount
        XCTAssertEqual(count, 0, "確認前に DELETE を呼ばない")
    }
}

private actor SuspendedDeleteAPI: PhloxAPI {
    private(set) var removeCount = 0
    private var firstRemove: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func remove(sessionID: String) async throws {
        removeCount += 1
        if removeCount == 1 {
            await withCheckedContinuation { continuation in
                firstRemove = continuation
                for waiter in startWaiters { waiter.resume() }
                startWaiters.removeAll()
            }
        }
    }

    func waitForFirstRemove() async {
        if removeCount > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func completeFirstRemove() {
        firstRemove?.resume()
        firstRemove = nil
    }

    func listSessions() async throws -> [Session] { throw PhloxError.unsupported }
    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.unsupported }
    func waitUntilReady(sessionID: String) async throws -> Bool { throw PhloxError.unsupported }
    func send(_ request: SendRequest) async throws -> SendResult { throw PhloxError.unsupported }
    func messages(sessionID: String) async throws -> [ChatMessage] { throw PhloxError.unsupported }
    func approvals() async throws -> [Approval] { throw PhloxError.unsupported }
    func respond(approvalID: String, decision: ApprovalDecision) async throws { throw PhloxError.unsupported }
}
