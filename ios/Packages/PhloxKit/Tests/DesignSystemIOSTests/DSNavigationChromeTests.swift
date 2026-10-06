import Testing
import SwiftUI
@testable import DesignSystemIOS

/// ナビバー chrome の配色はテーマ id 連動（ライトモードで「ナビバーだけダーク」にならない）。
@MainActor
@Suite("DSNavigation chrome") struct DSNavigationChromeTests {
    @Test("ナビバー chrome の配色はテーマ id 連動（phlox-light→light / phlox→dark）")
    func barColorSchemeFollowsThemeID() {
        #expect(DSNavigationChrome.barColorScheme(for: "phlox-light") == .light)
        #expect(DSNavigationChrome.barColorScheme(for: "phlox") == .dark)
    }

    @Test("未知・空のテーマ id は既定（dark）にフォールバックする")
    func barColorSchemeUnknownFallsBackToDark() {
        #expect(DSNavigationChrome.barColorScheme(for: "unknown-theme-xyz") == .dark)
        #expect(DSNavigationChrome.barColorScheme(for: "") == .dark)
    }

    @Test("テーマ id は完全一致で判定する")
    func themeIDMatchingIsExact() {
        #expect(DSNavigationChrome.barColorScheme(for: "PHLOX-LIGHT") == .dark)
        #expect(DSNavigationChrome.barColorScheme(for: " phlox-light ") == .dark)
    }
}
