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
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected .failed")
        }
    }

    func testCascadeCountMessage() {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 3, api: MockAPI(), onDeleted: {})
        XCTAssertEqual(vm.message, "子孫のセッション 3 件も一緒に削除されます。合わせて 4 件です。元に戻せません。")
        XCTAssertEqual(vm.deleteButtonLabel, "4 件を削除")
    }

    func testZeroCascadeMessage() {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0, api: MockAPI(), onDeleted: {})
        XCTAssertEqual(vm.message, "Mac 側のセッションと会話の記録が削除されます。元に戻せません。")
        XCTAssertEqual(vm.title, "“セッション” を削除しますか？")
        XCTAssertEqual(vm.deleteButtonLabel, "1 件を削除")
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
