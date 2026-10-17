import XCTest
import PhloxCore
@testable import Features

// E4-7 検証。承認取得（セッション絞り込み）、応答成功で非表示、Codex の許可・拒否を検証する。
@MainActor
final class ApprovalViewModelTests: XCTestCase {

    private let approvals = [
        Approval(id: "a1", sessionID: "s1", kind: .claudeCode, prompt: "削除しますか？"),
        Approval(id: "a2", sessionID: "s2", kind: .codex, prompt: "別セッション"),
    ]

    func testLoadFiltersApprovalsBySession() async {
        let vm = ApprovalViewModel(sessionID: "s1", api: MockAPI(approvalsList: approvals))
        await vm.load()
        XCTAssertEqual(vm.approvals.map(\.id), ["a1"])
        XCTAssertTrue(vm.isVisible)
    }

    func testRespondAcceptHidesBar() async {
        let mock = MockAPI(approvalsList: approvals)
        let vm = ApprovalViewModel(sessionID: "s1", api: mock)
        await vm.load()
        await vm.respond(.accept, approvalID: "a1")
        XCTAssertFalse(vm.isVisible)
        XCTAssertNotNil(vm.resultMessage)
        let log = await mock.respondLog
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.1, .accept)
    }

    func testCodexCanAcceptAndDeclineFromApprovalBarActions() async {
        let acceptMock = MockAPI(approvalsList: [Approval(id: "a9", sessionID: "s1", kind: .codex, prompt: "p")])
        let acceptVM = ApprovalViewModel(sessionID: "s1", api: acceptMock)
        await acceptVM.load()
        await acceptVM.tapPrimary(approvalID: "a9", decision: .accept)
        XCTAssertFalse(acceptVM.isVisible)
        let acceptLog = await acceptMock.respondLog
        XCTAssertEqual(acceptLog.map(\.1), [.accept])

        let declineMock = MockAPI(approvalsList: [Approval(id: "a10", sessionID: "s1", kind: .codex, prompt: "p")])
        let declineVM = ApprovalViewModel(sessionID: "s1", api: declineMock)
        await declineVM.load()
        await declineVM.tapPrimary(approvalID: "a10", decision: .decline)
        XCTAssertFalse(declineVM.isVisible)
        let declineLog = await declineMock.respondLog
        XCTAssertEqual(declineLog.map(\.1), [.decline])
    }

    func testNonCodexTapRespondsDirectly() async {
        let mock = MockAPI(approvalsList: approvals)
        let vm = ApprovalViewModel(sessionID: "s1", api: mock)
        await vm.tapPrimary(approvalID: "a1", decision: .decline)
        let log = await mock.respondLog
        XCTAssertEqual(log.first?.1, .decline)
        XCTAssertFalse(vm.isVisible)
    }

    func testRespondFailureShowsError() async {
        let vm = ApprovalViewModel(sessionID: "s1",
                                   api: MockAPI(approvalsList: approvals, respondError: .unauthorized))
        await vm.respond(.accept, approvalID: "a1")
        XCTAssertNotNil(vm.errorMessage)
    }
}
