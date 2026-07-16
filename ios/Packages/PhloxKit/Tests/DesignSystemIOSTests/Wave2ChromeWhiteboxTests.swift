import SwiftUI
import Testing
@testable import DesignSystemIOS

@MainActor
struct Wave2ChromeWhiteboxTests {
    @Test("空のテーマ id は dark にフォールバックする")
    func emptyThemeIDFallsBackToDark() {
        #expect(DSNavigationChrome.barColorScheme(for: "") == .dark)
    }

    @Test("テーマ id は完全一致で判定する")
    func themeIDMatchingIsExact() {
        #expect(DSNavigationChrome.barColorScheme(for: "PHLOX-LIGHT") == .dark)
        #expect(DSNavigationChrome.barColorScheme(for: " phlox-light ") == .dark)
    }
}
