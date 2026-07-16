import XCTest
import DesignSystemIOS
@testable import Features

// DP-4-8 検証。カンプ⑧の文言・4 択＋キャンセルカードの契約を View 層で保証する。
final class CodexApprovalSheetTests: XCTestCase {

    func testHeaderMatchesCamp() {
        XCTAssertEqual(CodexApprovalCopy.header, "承認の応答を選択")
    }

    func testMainOptionLabelsMatchCamp() {
        XCTAssertEqual(CodexApprovalCopy.accept, "承認する")
        XCTAssertEqual(CodexApprovalCopy.acceptForSession, "このセッションは常に許可")
        XCTAssertEqual(CodexApprovalCopy.decline, "却下する")
        XCTAssertEqual(CodexApprovalCopy.abort, "中止する")
    }

    func testDismissLabelMatchesCamp() {
        XCTAssertEqual(CodexApprovalCopy.dismiss, "キャンセル")
    }

    func testMainOptionsCountIsFour() {
        XCTAssertEqual(CodexApprovalCopy.mainOptions.count, 4)
    }

    func testMainOptionsMapToApprovalDecisions() {
        let decisions = CodexApprovalCopy.mainOptions.map(\.decision)
        XCTAssertEqual(decisions, [.accept, .acceptForSession, .decline, .cancel])
    }

    func testActionSheetCornerRadiusMatchesCamp() {
        XCTAssertEqual(CodexApprovalMetrics.cornerRadius, DSRadius.actionSheet)
        XCTAssertEqual(DSRadius.actionSheet, 16)
    }

    func testUITestingFallbackPromptMatchesCamp() {
        XCTAssertEqual(CodexApprovalCopy.uiTestingFallbackPrompt, "add /approvals endpoint · Codex")
    }
}
