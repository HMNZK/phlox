import XCTest
import AgentDomain
import DesignSystemIOS
import PhloxCore
@testable import Features

// DP-4-3 検証。カンプ③のヘッダー・入力バー契約を View 層で保証する。
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

    @MainActor
    func testAgentIconUsesSharedBrandBundleAndDetailSize() {
        let icon = AgentBrandIcon(kind: .claudeCode, size: 48)
        XCTAssertEqual(icon.size, 48)
        XCTAssertNotEqual(AgentBrandIcon.assetBundle.bundleURL, Bundle.main.bundleURL)
    }

    func testInputPlaceholderMatchesCamp() {
        XCTAssertEqual(SessionDetailCopy.inputPlaceholder(isAnsweringSelectionlessQuestion: false), "やりたいことを入力")
        XCTAssertEqual(SessionDetailCopy.inputPlaceholder(isAnsweringSelectionlessQuestion: true), "回答を入力")
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

    @MainActor
    func testAgentNamesComeFromSharedBrandIcons() {
        XCTAssertEqual(AgentBrandIcon(kind: .claudeCode, size: 48).descriptor.displayName, "Claude Code")
        XCTAssertEqual(AgentBrandIcon(kind: .codex, size: 48).descriptor.displayName, "Codex")
        XCTAssertEqual(AgentBrandIcon(kind: .cursor, size: 48).descriptor.displayName, "Cursor")
    }

    func testUsageFormatShowsCostAndContextPercent() {
        let line = SessionDetailUsageFormat.line(
            for: TurnUsage(costUSD: 0.1234, contextUsedTokens: 1000, contextWindowTokens: 200_000)
        )
        XCTAssertEqual(line, "$0.12 · コンテキスト 1%")
    }

    func testUsageFormatOmitsMissingFields() {
        XCTAssertNil(SessionDetailUsageFormat.line(for: TurnUsage(costUSD: nil, contextUsedTokens: nil, contextWindowTokens: nil)))
        XCTAssertEqual(SessionDetailUsageFormat.line(for: TurnUsage(costUSD: 1.0, contextUsedTokens: nil, contextWindowTokens: nil)), "$1.00")
    }

    func testWireTurnCostTakesPrecedenceOverUsageCost() {
        let usage = TurnUsage(costUSD: 0.5, contextUsedTokens: 50, contextWindowTokens: 100)
        XCTAssertEqual(SessionDetailUsageFormat.line(costUSD: 0.42, for: usage), "$0.42 · コンテキスト 50%")
    }
}
