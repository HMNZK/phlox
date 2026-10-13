import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct AppThemePaletteTests {
    @Test func allThemesUseTheirTextColorAsAccent() {
        for theme in ThemeStore.all {
            #expect(theme.accent == theme.textPrimary, "\(theme.id) accent must be monochrome (ADR 0189)")
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

    /// 再設計の確定値を持つ Phlox / Phlox Light（#1E1E20 など）だけは青みがわずかに入るため彩度差 4 以内、
    /// ほかの 8 テーマは従来どおり厳密な無彩色。
    @Test func uiChromeIsNeutralGrayForEveryTheme() {
        for theme in ThemeStore.all {
            let tolerance = [AppTheme.phlox.id, AppTheme.phloxLight.id].contains(theme.id) ? 4 : 0
            func isNeutral(_ c: RGB) -> Bool { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) <= tolerance }
            for face in [theme.background, theme.surface, theme.surfaceElevated,
                         theme.palette.sidebar, theme.palette.toolbar, theme.palette.card, theme.palette.tabBar] {
                #expect(isNeutral(face), "\(theme.id): \(face)")
            }
        }
    }
}
