// 契約の正本: tasks/task-1.md — ヘッダー（トップバー）使用量の表示制御。
// このファイルは PM が凍結する受け入れテスト。実装役は編集禁止
// （ハーネス欠陥を見つけた場合のみ、PM へ報告し承認を得てハーネス部分だけ修理可）。

import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: ヘッダー使用量の表示制御（task-1）")
struct HeaderUsageVisibilityAcceptanceTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    /// Codex は実データあり、Cursor は未取得、Claude は未取得（ADR 0039 で行を残す対象）。
    private static var mixedUsages: [AgentKind: CLIUsage] {
        [
            .codex: CLIUsage(
                kind: .codex,
                state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 42)]),
                updatedAt: now
            ),
            .cursor: CLIUsage(
                kind: .cursor,
                state: .unavailable(reason: "Cursorアプリ未検出"),
                updatedAt: now
            ),
            .claudeCode: CLIUsage(
                kind: .claudeCode,
                state: .unavailable(reason: "未取得"),
                updatedAt: now
            ),
        ]
    }

    // MARK: - 設定によるヘッダー表示の ON/OFF

    @Test func 設定オンかつインスペクター非表示ならヘッダーに使用量を出す() {
        #expect(UsageDisplay.showsTopBarUsage(showInHeader: true, inspectorVisible: false))
    }

    @Test func 設定オフならインスペクター非表示でもヘッダーに使用量を出さない() {
        #expect(!UsageDisplay.showsTopBarUsage(showInHeader: false, inspectorVisible: false))
    }

    @Test func インスペクター表示中は設定オンでもヘッダーに使用量を出さない() {
        #expect(!UsageDisplay.showsTopBarUsage(showInHeader: true, inspectorVisible: true))
    }

    @Test func ヘッダー表示設定の既定はオン() throws {
        let value = try #require(
            UsageSettings.defaultsDictionary[UsageSettings.showInHeaderKey] as? Bool
        )
        #expect(value)
    }

    // MARK: - 「未取得のCLIも表示」のヘッダーへの反映

    @Test func 未取得を表示しない設定ではヘッダーに未取得のCursorを出さない() {
        let chips = UsageDisplay.topBarChips(
            usages: Self.mixedUsages,
            showUnavailable: false,
            now: Self.now
        )

        #expect(!chips.contains { $0.kind == .cursor })
    }

    @Test func 未取得を表示しない設定でもヘッダーのClaude行は理由つきで残る() throws {
        let chips = UsageDisplay.topBarChips(
            usages: Self.mixedUsages,
            showUnavailable: false,
            now: Self.now
        )

        let claude = try #require(chips.first { $0.kind == .claudeCode })
        #expect(claude.unavailableReason == "未取得")
    }

    @Test func 未取得を表示する設定ならヘッダーに未取得のCursorを理由つきで出す() throws {
        let chips = UsageDisplay.topBarChips(
            usages: Self.mixedUsages,
            showUnavailable: true,
            now: Self.now
        )

        let cursor = try #require(chips.first { $0.kind == .cursor })
        #expect(cursor.unavailableReason == "Cursorアプリ未検出")
    }

    @Test func ヘッダーのチップはAgentKindの定義順に並ぶ() {
        let chips = UsageDisplay.topBarChips(
            usages: Self.mixedUsages,
            showUnavailable: true,
            now: Self.now
        )

        #expect(chips.map(\.kind) == [.claudeCode, .codex, .cursor])
    }

    @Test func 使用量が取得できていないCLIはチップを作らない() {
        let usages: [AgentKind: CLIUsage] = [
            .codex: CLIUsage(
                kind: .codex,
                state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 42)]),
                updatedAt: Self.now
            ),
        ]

        let chips = UsageDisplay.topBarChips(usages: usages, showUnavailable: true, now: Self.now)

        #expect(chips.map(\.kind) == [.codex])
    }

    @Test func 実データのチップは理由を持たず表示バケットを持つ() throws {
        let chips = UsageDisplay.topBarChips(
            usages: Self.mixedUsages,
            showUnavailable: false,
            now: Self.now
        )

        let codex = try #require(chips.first { $0.kind == .codex })
        #expect(codex.unavailableReason == nil)
        #expect(codex.shownBuckets.map(\.id) == ["5h"])
    }
}
