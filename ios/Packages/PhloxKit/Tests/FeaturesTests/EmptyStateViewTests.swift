import XCTest
@testable import Features
import DesignSystemIOS

// DP-4-11 検証。カンプ⑪の文言・寸法を View 層で保証する。
final class EmptyStateViewTests: XCTestCase {

    func testTitleMatchesCamp() {
        XCTAssertEqual(EmptyStateCopy.title, "セッションがありません")
    }

    func testSubtitleMentionsSpawnViaPlus() {
        XCTAssertTrue(EmptyStateCopy.subtitle.contains("+ をタップして"))
        XCTAssertTrue(EmptyStateCopy.subtitle.contains("spawn しましょう"))
        XCTAssertTrue(EmptyStateCopy.subtitle.contains("外出先でも指示できます"))
    }

    func testCTATitleMatchesCamp() {
        XCTAssertEqual(EmptyStateCopy.ctaTitle, "+ 新規タスクを作成")
    }

    func testIconPlaceholderUsesDashedAccentBorder() {
        XCTAssertEqual(EmptyStateMetrics.iconContainerBorderWidth, DSSpacing.xxs)
        XCTAssertEqual(EmptyStateMetrics.iconBorderOpacity, 0.45, accuracy: 0.001)
    }

    func testLoadedListSubtitleFormat() {
        XCTAssertEqual(
            SessionListViewModel.listSubtitle(sessionCount: 5, host: "100.64.0.1"),
            "5 件 · 100.64.0.1"
        )
    }
}
