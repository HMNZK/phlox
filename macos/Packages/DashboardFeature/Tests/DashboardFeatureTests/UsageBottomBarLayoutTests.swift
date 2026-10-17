import AgentDomain
import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

private struct FixedUsageProvider: UsageProvider {
    let kind: AgentKind = .codex
    func fetch() async -> CLIUsage {
        CLIUsage(kind: .codex, state: .ok([
            UsageBucket(id: "5h", label: "5時間", usedPercent: 28),
            UsageBucket(id: "weekly", label: "週次", usedPercent: 85),
        ]), updatedAt: .now)
    }
}

extension ThemeRenderingTests {
@Suite("使用量バーの縦中央", .serialized)
@MainActor
struct UsageBottomBarLayoutTests {
    // 横棒（既定）と数値の両方で、ロゴと中身がバーの縦中央に来る。
    @Test(arguments: [720.0, 1440.0], [
        (false, UsageSettings.BottomBarStyle.bar), (true, .bar), (false, .percent), (true, .percent),
    ])
    func logoAndTextAreCentered(width: Double, appearance: (light: Bool, style: UsageSettings.BottomBarStyle)) async throws {
        let light = appearance.light
        // 他の描画が欠落画像を参照する前に、標準テスト入口で素材を準備する。
        let resources = try #require(AgentBrandIcon.assetBundle.resourceURL)
        try #require(FileManager.default.fileExists(atPath: resources.appendingPathComponent("Assets.car").path),
                     "macos/scripts/run-swift-tests.sh で描画前に画像素材を準備してください")
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = saved
        arguments[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
        arguments[UsageSettings.showInHeaderKey] = true
        arguments[UsageSettings.bottomBarStyleKey] = appearance.style.rawValue
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }

        let monitor = UsageMonitor(providers: [.codex: FixedUsageProvider()])
        await monitor.refresh()
        let host = NSHostingView(rootView: UsageBottomBarView(monitor: monitor)
            .environment(\.locale, Locale(identifier: "ja"))
            .environment(\.colorScheme, light ? .light : .dark))
        let bounds = NSRect(x: 0, y: 0, width: width, height: DSLayout.usageBarHeight)
        let window = NSWindow(contentRect: bounds.offsetBy(dx: -10000, dy: -10000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.frame = bounds
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: bounds))
        host.cacheDisplay(in: bounds, to: bitmap)
        let background = try #require(NSColor(DSColor.toolbarBackground).usingColorSpace(.deviceRGB))
        let scale = Double(bitmap.pixelsHigh) / DSLayout.usageBarHeight

        // ロゴと文字を別々に測り、バーの上端の区切り線は除く。
        for range in [12..<24, 32..<140] {
            var inkRows: [Int] = []
            for y in Int(2 * scale)..<Int(22 * scale) {
                for x in Int(Double(range.lowerBound) * scale)..<Int(Double(range.upperBound) * scale) {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let contrast = max(abs(color.redComponent - background.redComponent),
                                       abs(color.greenComponent - background.greenComponent),
                                       abs(color.blueComponent - background.blueComponent))
                    if contrast > 0.25 { inkRows.append(y); break }
                }
            }
            let top = try #require(inkRows.min())
            let bottom = try #require(inkRows.max())
            let center = Double(top + bottom + 1) / (2 * scale)
            #expect(abs(center - DSLayout.usageBarHeight / 2) <= 1.5,
                    "幅 \(width)、light=\(light)、\(appearance.style)、範囲 \(range): 描画の縦中央 \(center)")
        }
    }
}
}
