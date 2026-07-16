import XCTest
import PhloxCore
@testable import Features

// DP-4-3 検証。カンプ③のヘッダー・出力・入力バー契約を View 層で保証する。
final class SessionDetailViewTests: XCTestCase {

    private var calendar: Calendar!
    private var locale: Locale!
    private let startedAt = Date(timeIntervalSince1970: 1_704_067_920) // 2024-01-01 14:32:00 JST ≈ 05:32 UTC — use fixed components

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar = cal
        locale = Locale(identifier: "ja_JP")
    }

    func testHeaderAgentBadgeSizeMatchesCamp() {
        XCTAssertEqual(SessionDetailMetrics.headerAgentBadgeSize, 48)
    }

    func testInputPlaceholderMatchesCamp() {
        XCTAssertEqual(SessionDetailCopy.inputPlaceholder, "回答を入力…")
    }

    func testOutputSectionTitleMatchesCamp() {
        XCTAssertEqual(SessionDetailCopy.outputSectionTitle, "出力")
    }

    func testOutputCollapseLineLimitMatchesCamp() {
        XCTAssertEqual(SessionDetailMetrics.outputCollapseLineLimit, 12)
    }

    func testHeaderMetaLineFormatsAgentAndStartTime() {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 14
        components.minute = 32
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let date = calendar.date(from: components)!

        let line = SessionDetailCopy.headerMetaLine(
            agentDisplayName: "Claude Code",
            startedAt: date,
            calendar: calendar,
            locale: locale
        )
        XCTAssertEqual(line, "Claude Code · 開始 14:32")
    }

    func testOutputNeedsToggleWhenExceedsLineLimit() {
        let text = (1...13).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertTrue(SessionDetailMetrics.outputNeedsToggle(text: text))
    }

    func testOutputDoesNotNeedToggleWhenWithinLineLimit() {
        let text = (1...12).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertFalse(SessionDetailMetrics.outputNeedsToggle(text: text))
    }

    func testDisplayedOutputHiddenWhenCollapsedAndLong() {
        let text = (1...20).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertNil(SessionDetailMetrics.displayedOutput(text: text, isExpanded: false))
    }

    func testDisplayedOutputShowsFullTextWhenExpanded() {
        let text = (1...20).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(SessionDetailMetrics.displayedOutput(text: text, isExpanded: true), text)
    }

    func testDisplayedOutputShowsShortTextWhenCollapsed() {
        let text = "› running tests...\nOK"
        XCTAssertEqual(SessionDetailMetrics.displayedOutput(text: text, isExpanded: false), text)
    }

    func testCampAgentAbbreviationMatchesSessionRow() {
        XCTAssertEqual(SessionDetailMetrics.campAbbreviation(for: .claudeCode), "CC")
        XCTAssertEqual(SessionDetailMetrics.campAbbreviation(for: .codex), "Cx")
        XCTAssertEqual(SessionDetailMetrics.campAbbreviation(for: .cursor), "Cu")
    }

    func testUsageFormatShowsCostAndContextPercent() {
        let line = SessionDetailUsageFormat.line(
            for: TurnUsage(costUSD: 0.1234, contextUsedTokens: 1000, contextWindowTokens: 200_000)
        )
        XCTAssertEqual(line, "$0.1234 · コンテキスト 1%")
    }

    func testUsageFormatOmitsMissingFields() {
        XCTAssertNil(SessionDetailUsageFormat.line(for: TurnUsage(costUSD: nil, contextUsedTokens: nil, contextWindowTokens: nil)))
        XCTAssertEqual(SessionDetailUsageFormat.line(for: TurnUsage(costUSD: 1.0, contextUsedTokens: nil, contextWindowTokens: nil)), "$1.0000")
    }
}
