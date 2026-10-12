import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("使用量バーの縦中央", .serialized)
@MainActor
struct UsageBottomBarLayoutTests {
    @Test(arguments: [720.0, 1440.0], [false, true])
    func logoAndTextAreCentered(width: Double, light: Bool) async throws {
        // swift test は xcassets をコンパイルしないため、実ロゴを描く前に actool を通す。
        let resources = try #require(AgentBrandIcon.assetBundle.resourceURL)
        if !FileManager.default.fileExists(atPath: resources.appendingPathComponent("Assets.car").path) {
            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = ["actool", "--compile", resources.path, "--platform", "macosx",
                                  "--minimum-deployment-target", "14.0",
                                  resources.appendingPathComponent("Icons.xcassets").path]
            try compiler.run()
            compiler.waitUntilExit()
            try #require(compiler.terminationStatus == 0)
        }
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = saved
        arguments[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
        arguments[UsageSettings.showInHeaderKey] = true
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }

        let monitor = UsageMonitor(providers: [:])
        await monitor.refresh()
        let host = NSHostingView(rootView: UsageBottomBarView(monitor: monitor, router: AppRouter())
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
                    "幅 \(width)、light=\(light)、範囲 \(range): 描画の縦中央 \(center)")
        }
    }
}
