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
        XCTAssertTrue(vm.message.contains("3 件の子孫"))
    }

    func testZeroCascadeMessage() {
        let vm = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0, api: MockAPI(), onDeleted: {})
        XCTAssertTrue(vm.message.contains("このセッションを削除します"))
        XCTAssertFalse(vm.message.contains("子孫"))
    }

    func testDoesNotCallAPIBeforeConfirmation() async {
        let mock = MockAPI()
        _ = DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 0, api: mock, onDeleted: {})
        let count = await mock.removeCount
        XCTAssertEqual(count, 0, "確認前に DELETE を呼ばない")
    }
}
