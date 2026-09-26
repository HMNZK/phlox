import Testing
import CoreGraphics
@testable import SessionFeature

/// 承認カードの対象欄の高さ上限（長い入力でカードが窓の上端を越えないため）。
@Suite("承認カードの対象欄の高さ上限")
struct ApprovalSubjectHeightTests {
    @Test func usesQuarterOfTheChatHeight() {
        #expect(ApprovalCard.subjectMaxHeight(availableHeight: 600) == 150)
    }

    @Test func lowWindowStillShowsSomeLines() {
        #expect(ApprovalCard.subjectMaxHeight(availableHeight: 200) == 60)
    }

    @Test func tallWindowCapsAt360() {
        #expect(ApprovalCard.subjectMaxHeight(availableHeight: 2000) == 360)
    }
}
