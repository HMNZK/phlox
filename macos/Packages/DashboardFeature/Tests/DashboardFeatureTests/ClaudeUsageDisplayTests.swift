import AgentDomain
import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@MainActor
struct ClaudeUsageDisplayTests {
    @Test(arguments: [1100.0, 800.0, 500.0], [0, 1, 2])
    func validAndExpiredWindows(width: Double, expiredCount: Int) async throws {
        let now = Date(timeIntervalSince1970: 2000000000)
        let buckets = [
            UsageBucket(id: "5h", label: "5時間", usedPercent: 9, resetsAt: now.addingTimeInterval(expiredCount > 0 ? -1 : 3600)),
            UsageBucket(id: "weekly", label: "週次", usedPercent: 39, resetsAt: now.addingTimeInterval(expiredCount > 1 ? -1 : 86400)),
        ]
        let monitor = UsageMonitor(providers: [.claudeCode: DisplayProvider(buckets: buckets, date: now)], now: { now })
        await monitor.refresh(kinds: [.claudeCode])
        let groups = UsageDisplay.bottomBarGroups(usages: monitor.usages, showUnavailable: false)
        let group = try #require(groups.first)
        #expect(group.buckets?.count == (expiredCount == 2 ? nil : 2 - expiredCount))
        let locale = Locale(identifier: "ja")
        let spoken = UsageDisplay.bottomBarAccessibilityLabel(groups: groups, now: now, locale: locale)
        #expect(!spoken.contains("100%"))
        if expiredCount == 0 { #expect(spoken.contains("91%")) }
        if expiredCount < 2 { #expect(spoken.contains("61%")) }
        else { #expect(spoken.contains("取得できません")) }
        let stage = UsageDisplay.bottomBarStage(forWidth: width)
        for bucket in group.buckets ?? [] {
            let text = UsageDisplay.bottomBarBucketText(bucket, showsLabel: stage != .percentageOnly,
                showsReset: stage == .full, now: now, locale: locale)
            #expect(text.contains(bucket.id == "5h" ? "91%" : "61%"))
        }
        try await render(monitor, width: width, name: "expired\(expiredCount)")
    }

    @Test func previousValueIsDisclosedToSightedAndVoiceOverUsers() async throws {
        let now = Date(timeIntervalSince1970: 2000000000)
        let provider = PreviousDisplayProvider(date: now)
        let monitor = UsageMonitor(providers: [.claudeCode: provider], now: { now })
        await monitor.refresh(kinds: [.claudeCode])
        await monitor.refresh(kinds: [.claudeCode])
        #expect(monitor.failures[.claudeCode] != nil)
        let groups = UsageDisplay.bottomBarGroups(usages: monitor.usages, showUnavailable: false)
        let spoken = UsageDisplay.bottomBarAccessibilityLabel(groups: groups, now: now, locale: Locale(identifier: "ja"), staleKinds: [.claudeCode])
        #expect(spoken.contains("前回値"))
        #expect(spoken.contains("91%"))
        guard case .unavailable = monitor.syncedUsages[.claudeCode]?.state else { Issue.record("cache must not sync as fresh"); return }
        try await render(monitor, width: 500, name: "previous")
    }

    private func render(_ monitor: UsageMonitor, width: Double, name: String) async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        let locale = Locale(identifier: "ja")
        let suite = "phlox-usage-render-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UsageSettings.showInHeaderKey)
        for style in UsageSettings.BottomBarStyle.allCases {
            defaults.set(style.rawValue, forKey: UsageSettings.bottomBarStyleKey)
            let host = NSHostingView(rootView: UsageBottomBarView(monitor: monitor).defaultAppStorage(defaults)
                .environment(\.locale, locale).environment(\.colorScheme, .dark))
            let bounds = NSRect(x: 0, y: 0, width: width, height: DSLayout.usageBarHeight)
            let window = NSWindow(contentRect: bounds.offsetBy(dx: -10000, dy: -10000), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.frame = bounds
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: bounds))
            host.cacheDisplay(in: bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<6 { root.deleteLastPathComponent() }
            let output = root.appendingPathComponent(".build/design-snapshots/claude-usage")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("\(Int(width))-\(name)-\(style.rawValue).png"))
            window.contentView = nil
            window.close()
        }
    }
}

private struct DisplayProvider: UsageProvider {
    let kind: AgentKind = .claudeCode
    let buckets: [UsageBucket]
    let date: Date
    func fetch() async -> CLIUsage { .init(kind: kind, state: .ok(buckets), updatedAt: date) }
}

private actor PreviousDisplayProvider: UsageProvider {
    nonisolated let kind: AgentKind = .claudeCode
    let date: Date
    var fetched = false
    init(date: Date) { self.date = date }
    func fetch() async -> CLIUsage {
        defer { fetched = true }
        return CLIUsage(kind: kind, state: fetched ? .unavailable(reason: "offline") : .ok([
            UsageBucket(id: "5h", label: "5時間", usedPercent: 9, resetsAt: date.addingTimeInterval(3600))
        ]), updatedAt: date, dataAsOf: date)
    }
}
