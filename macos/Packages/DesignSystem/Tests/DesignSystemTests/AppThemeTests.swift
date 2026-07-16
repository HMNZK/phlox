import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct AppThemePaletteTests {
    private let claudeCoral = RGB(0xD9, 0x77, 0x57)

    @Test func allThemesUseClaudeCoralAccent() {
        for theme in ThemeStore.all {
            #expect(theme.accent == claudeCoral, "\(theme.id) must use the shared Claude coral accent")
        }
    }

    @Test func lightThemesAreRegistered() {
        let ids = Set(ThemeStore.all.map(\.id))
        #expect(ids.contains("catppuccin-latte"))
        #expect(ids.contains("solarized-light"))
        #expect(ids.contains("github-light"))
    }

    @Test func preferredColorSchemeTracksThemeBrightness() {
        #expect(AppTheme.phlox.preferredColorScheme == .dark)
        #expect(AppTheme.tokyoNight.preferredColorScheme == .dark)
        #expect(AppTheme.catppuccinLatte.preferredColorScheme == .light)
        #expect(AppTheme.solarizedLight.preferredColorScheme == .light)
        #expect(AppTheme.githubLight.preferredColorScheme == .light)
    }

    @Test func uiChromeIsNeutralGrayForEveryTheme() {
        for theme in ThemeStore.all {
            #expect(theme.background.r == theme.background.g)
            #expect(theme.background.g == theme.background.b)
            #expect(theme.surface.r == theme.surface.g)
            #expect(theme.surface.g == theme.surface.b)
            #expect(theme.surfaceElevated.r == theme.surfaceElevated.g)
            #expect(theme.surfaceElevated.g == theme.surfaceElevated.b)
        }
    }
}
