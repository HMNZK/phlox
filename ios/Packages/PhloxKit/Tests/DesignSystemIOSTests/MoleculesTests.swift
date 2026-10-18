import XCTest
import SwiftUI
import AgentDomain
import PhloxCore
@testable import DesignSystemIOS

// E2-4 検証。Molecules の決定ロジック（attention アクセント・プロンプト抽出・送信可否・
// 提示する承認決定・バナーのアイコン）を純粋ヘルパー/プロパティで検証する。
@MainActor
final class MoleculesTests: XCTestCase {

    func testThinkingIndicatorUsesActivityStateWordWhileWaiting() {
        let locale = Locale(identifier: "ja_JP")
        let waiting = DSThinkingIndicator(state: .waiting)
        XCTAssertEqual(waiting.displayLabel(locale: locale), "待機中…")
    }

    // MARK: - DSInputBar

    func testInputBarCannotSubmitWhenEmptyOrWhitespace() {
        XCTAssertFalse(DSInputBar.canSubmit(text: "", isLoading: false))
        XCTAssertFalse(DSInputBar.canSubmit(text: "   \n", isLoading: false))
    }

    func testInputBarCannotSubmitWhileLoading() {
        XCTAssertFalse(DSInputBar.canSubmit(text: "hello", isLoading: true))
    }

    func testInputBarCanSubmitWithText() {
        XCTAssertTrue(DSInputBar.canSubmit(text: "hello", isLoading: false))
    }

    func testInputBarChipAppearanceAndTouchTarget() {
        XCTAssertEqual(DSInputBar.chipVisualHeight, 34)
        XCTAssertEqual(DSInputBar.chipTouchTargetSize, 44)
    }

    // MARK: - DSResultBanner

    func testResultBannerIconReflectsError() {
        XCTAssertEqual(DSResultBanner.iconName(isError: true), DSIcon.errorBadge)
        XCTAssertNotEqual(DSResultBanner.iconName(isError: false), DSResultBanner.iconName(isError: true))
    }

    // MARK: - DSRelativeTime

    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-3), now: now), "今")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-30), now: now), "30秒前")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-120), now: now), "2分前")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-7200), now: now), "2時間前")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-172800), now: now), "2日前")
    }

    func testSubmitBarLogicAndSessionInputBarUseSameEligibility() {
        XCTAssertTrue(DSSubmitBarLogic.canSubmit(text: "hello", isLoading: false))
        XCTAssertFalse(DSSubmitBarLogic.canSubmit(text: "", isLoading: false))
        XCTAssertEqual(
            DSInputBar.canSubmit(text: "x", isLoading: false),
            DSSubmitBarLogic.canSubmit(text: "x", isLoading: false)
        )
    }

    func testInputBarFocusAndSendAccessibilityContract() {
        XCTAssertTrue(DSInputBar.usesFocusState)
        XCTAssertEqual(DSInputBar.sendAccessibilityLabel, "送信")
    }

    func testRelativeTimeClampsFutureToNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(60), now: now), "今")
    }

}
