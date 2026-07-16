import XCTest
import PhloxCore
@testable import Features

// E4-7 検証。承認取得（セッション絞り込み）、応答成功で非表示、Codex 4 択シート分岐を検証する。
@MainActor
final class ApprovalViewModelTests: XCTestCase {

    private let approvals = [
        Approval(id: "a1", sessionID: "s1", kind: .claudeCode, prompt: "削除しますか？"),
        Approval(id: "a2", sessionID: "s2", kind: .codex, prompt: "別セッション"),
    ]

    func testLoadFiltersApprovalsBySession() async {
        let vm = ApprovalViewModel(sessionID: "s1", agentKind: .claudeCode, api: MockAPI(approvalsList: approvals))
        await vm.load()
        XCTAssertEqual(vm.approvals.map(\.id), ["a1"])
        XCTAssertTrue(vm.isVisible)
    }

    func testRespondAcceptHidesBar() async {
        let mock = MockAPI(approvalsList: approvals)
        let vm = ApprovalViewModel(sessionID: "s1", agentKind: .claudeCode, api: mock)
        await vm.load()
        await vm.respond(.accept, approvalID: "a1")
        XCTAssertFalse(vm.isVisible)
        XCTAssertNotNil(vm.resultMessage)
        let log = await mock.respondLog
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.1, .accept)
    }

    func testCodexUsesSheet() {
        let vm = ApprovalViewModel(sessionID: "s1", agentKind: .codex, api: MockAPI())
        XCTAssertTrue(vm.usesCodexSheet)
        let cc = ApprovalViewModel(sessionID: "s1", agentKind: .claudeCode, api: MockAPI())
        XCTAssertFalse(cc.usesCodexSheet)
    }

    func testCodexTapOpensSheetWithoutResponding() async {
        let mock = MockAPI(approvalsList: [Approval(id: "a9", sessionID: "s1", kind: .codex, prompt: "p")])
        let vm = ApprovalViewModel(sessionID: "s1", agentKind: .codex, api: mock)
        await vm.tapPrimary(approvalID: "a9", decision: .accept)
        XCTAssertTrue(vm.showCodexSheet)
        let log = await mock.respondLog
        XCTAssertTrue(log.isEmpty, "Codex は即応答せずシートを開く")
    }

    func testNonCodexTapRespondsDirectly() async {
        let mock = MockAPI(approvalsList: approvals)
        let vm = ApprovalViewModel(sessionID: "s1", agentKind: .claudeCode, api: mock)
        await vm.tapPrimary(approvalID: "a1", decision: .decline)
        let log = await mock.respondLog
        XCTAssertEqual(log.first?.1, .decline)
        XCTAssertFalse(vm.isVisible)
    }

    func testRespondFailureShowsError() async {
        let vm = ApprovalViewModel(sessionID: "s1", agentKind: .claudeCode,
                                   api: MockAPI(approvalsList: approvals, respondError: .unauthorized))
        await vm.respond(.accept, approvalID: "a1")
        XCTAssertNotNil(vm.errorMessage)
    }
}
