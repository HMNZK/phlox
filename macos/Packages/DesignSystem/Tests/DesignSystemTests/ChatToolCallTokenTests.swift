import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("DSColor.chatToolCallText", .serialized)
struct ChatToolCallTokenTests {
    @Test("ライト／ダークテーマで半透明かつ無彩色") @MainActor
    func chatToolCallTextIsTranslucentNeutralInLightAndDarkThemes() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        for theme in [AppTheme.phlox, .githubLight] {
            defaults.set(theme.id, forKey: ThemeStore.themeKey)
            let color = try #require(NSColor(DSColor.chatToolCallText).usingColorSpace(.sRGB))
            #expect(color.alphaComponent < 1.0, "\(theme.name) では半透明であること")
            #expect(
                max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent) <= 1.0 / 255.0,
                "\(theme.name) では無彩色であること"
            )
        }
    }
}
