// 実装役の白箱テスト（task-1）。契約の正本は tasks/task-1.md。
// 受け入れテスト(HeaderUsageVisibilityAcceptanceTests)がカバーしない内部分岐を補う。

import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("ヘッダー使用量 whitebox（task-1）")
struct HeaderUsageWhiteboxTests {
    private static let now = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - UsageSettings

    @Test func showInHeaderKeyは契約どおりの文字列() {
        #expect(UsageSettings.showInHeaderKey == "phlox.usage.showInHeader")
    }

    // MARK: - showsTopBarUsage

    @Test func 設定オフかつインスペクター表示中でもヘッダーに使用量を出さない() {
        #expect(!UsageDisplay.showsTopBarUsage(showInHeader: false, inspectorVisible: true))
    }

    // MARK: - topBarChips: staleNote（ADR 0099）

    @Test func Claudeの実データが新鮮なら注記を出さない() throws {
        let usages: [AgentKind: CLIUsage] = [
            .claudeCode: CLIUsage(
                kind: .claudeCode,
                state: .ok([UsageBucket(id: "weekly", label: "週次", usedPercent: 10)]),
                updatedAt: Self.now,
                dataAsOf: Self.now.addingTimeInterval(-60) // 1分前=新鮮
            ),
        ]

        let chips = UsageDisplay.topBarChips(usages: usages, showUnavailable: false, now: Self.now)

        let claude = try #require(chips.first { $0.kind == .claudeCode })
        #expect(claude.staleNote == nil)
    }

    @Test func Claudeの実データが古いと注記を出す() throws {
        let usages: [AgentKind: CLIUsage] = [
            .claudeCode: CLIUsage(
                kind: .claudeCode,
                state: .ok([UsageBucket(id: "weekly", label: "週次", usedPercent: 10)]),
                updatedAt: Self.now,
                dataAsOf: Self.now.addingTimeInterval(-3600) // 1時間前=stale
            ),
        ]

        let chips = UsageDisplay.topBarChips(usages: usages, showUnavailable: false, now: Self.now)

        let claude = try #require(chips.first { $0.kind == .claudeCode })
        #expect(claude.staleNote == "1時間前の値")
    }

    @Test func ClaudeのdataAsOfが無いと実データでも注記を出さない() throws {
        let usages: [AgentKind: CLIUsage] = [
            .claudeCode: CLIUsage(
                kind: .claudeCode,
                state: .ok([UsageBucket(id: "weekly", label: "週次", usedPercent: 10)]),
                updatedAt: Self.now,
                dataAsOf: nil
            ),
        ]

        let chips = UsageDisplay.topBarChips(usages: usages, showUnavailable: false, now: Self.now)

        let claude = try #require(chips.first { $0.kind == .claudeCode })
        #expect(claude.staleNote == nil)
    }

    @Test func Claude以外の実データは常に注記を持たない() throws {
        let usages: [AgentKind: CLIUsage] = [
            .codex: CLIUsage(
                kind: .codex,
                state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 10)]),
                updatedAt: Self.now,
                dataAsOf: Self.now.addingTimeInterval(-3600)
            ),
        ]

        let chips = UsageDisplay.topBarChips(usages: usages, showUnavailable: false, now: Self.now)

        let codex = try #require(chips.first { $0.kind == .codex })
        #expect(codex.staleNote == nil)
    }

    // MARK: - topBarChips: 空バケットの除外

    @Test func バケットが空ならokでもチップを作らない() {
        let usages: [AgentKind: CLIUsage] = [
            .cursor: CLIUsage(kind: .cursor, state: .ok([]), updatedAt: Self.now),
        ]

        let chips = UsageDisplay.topBarChips(usages: usages, showUnavailable: true, now: Self.now)

        #expect(chips.isEmpty)
    }
}
