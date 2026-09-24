import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

// 07 インスペクタとツール: 取得失敗の記録・チップから「使用量」へ・変更の種類の文字・リセットまでの文言。

private final class SwitchingUsageProvider: UsageProvider, @unchecked Sendable {
    let kind: AgentKind = .codex
    var next: CLIUsage

    init(_ usage: CLIUsage) { next = usage }

    func fetch() async -> CLIUsage { next }
}

@Suite("Inspector redesign (07)")
struct InspectorRedesignTests {

    @Test @MainActor func usageFailure_isRecordedWhilePreviousValueIsShown_andClearedOnSuccess() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let ok = CLIUsage(kind: .codex, state: .ok([UsageBucket(id: "5h", label: "5時間", usedPercent: 40)]), updatedAt: clock)
        let provider = SwitchingUsageProvider(ok)
        let monitor = UsageMonitor(providers: [.codex: provider], now: { clock })

        await monitor.refresh(kinds: [.codex])
        #expect(monitor.failures.isEmpty)
        #expect(monitor.lastSucceededAt == clock)

        clock = clock.addingTimeInterval(60)
        provider.next = CLIUsage(kind: .codex, state: .unavailable(reason: "ネットワークに接続できません"), updatedAt: clock)
        await monitor.refresh(kinds: [.codex])
        // 前回の値を出し続け、失敗は理由と時刻で残す。
        if case .ok = monitor.usages[.codex]?.state {} else { Issue.record("前回の値が残っていない") }
        #expect(monitor.failures[.codex] == UsageFailure(reason: "ネットワークに接続できません", at: clock))
        #expect(monitor.lastSucceededAt == Date(timeIntervalSince1970: 1_000))

        provider.next = ok
        await monitor.refresh(kinds: [.codex])
        #expect(monitor.failures.isEmpty)
    }

    @Test @MainActor func usageFailure_isNotRecordedWhenNoPreviousValueIsShown() async {
        let provider = SwitchingUsageProvider(CLIUsage(kind: .codex, state: .unavailable(reason: "未設定"), updatedAt: .now))
        let monitor = UsageMonitor(providers: [.codex: provider])
        await monitor.refresh(kinds: [.codex])
        // 理由はカードにそのまま出るので、失敗の記録（前回の値の注記）は付けない。
        #expect(monitor.failures.isEmpty)
    }

    @Test @MainActor func usageChip_opensTheUsageTab() {
        let router = AppRouter()
        router.inspectorTab = .session
        router.showUsageInInspector()
        #expect(router.inspectorVisible)
        #expect(router.inspectorTab == .usage)
    }

    @Test func changeLetters_followTheKind_andBinaryIsB() {
        let letters = [WorkingTreeChange.Kind.modified, .added, .renamed, .deleted, .untracked].map {
            editorChangeLetter(for: WorkingTreeChange(path: "a.swift", kind: $0, isBinary: false))
        }
        #expect(letters == ["M", "A", "R", "D", "U"])
        #expect(editorChangeLetter(for: WorkingTreeChange(path: "a.png", kind: .added, isBinary: true)) == "B")
    }

    @Test func resetText_usesDaysOnlyFromOneDay() {
        let now = Date(timeIntervalSince1970: 0)
        let ja = Locale(identifier: "ja")
        #expect(UsageText.resetsIn(now.addingTimeInterval(3 * 86_400 + 3_600), now: now, locale: ja) == "3日後にリセット")
        #expect(UsageText.resetsIn(now.addingTimeInterval(6_120), now: now, locale: ja) == "1時間 42分後にリセット")
    }
}
