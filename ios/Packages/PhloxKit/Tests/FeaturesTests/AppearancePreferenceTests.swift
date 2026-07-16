import SwiftUI
import Testing
@testable import Features

@Suite("外観設定")
struct AppearancePreferenceTests {
    @Test("3つの選択肢は永続化値と日本語ラベルを持つ")
    func casesExposeStableRawValuesAndLabels() {
        #expect(AppearancePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(AppearancePreference.allCases.map(\.label) == ["システム", "ライト", "ダーク"])
    }

    @Test("system は OS のライトとダークをテーマ ID に反映する")
    func systemTracksBothColorSchemes() {
        #expect(AppearancePreference.system.themeID(systemColorScheme: .light) == "phlox-light")
        #expect(AppearancePreference.system.themeID(systemColorScheme: .dark) == "phlox")
        #expect(AppearancePreference.system.preferredColorScheme == nil)
    }

    @Test("固定外観は OS の外観に依存しない")
    func fixedAppearancesIgnoreSystemColorScheme() {
        for colorScheme in [ColorScheme.light, .dark] {
            #expect(AppearancePreference.light.themeID(systemColorScheme: colorScheme) == "phlox-light")
            #expect(AppearancePreference.dark.themeID(systemColorScheme: colorScheme) == "phlox")
        }
        #expect(AppearancePreference.light.preferredColorScheme == .light)
        #expect(AppearancePreference.dark.preferredColorScheme == .dark)
    }
}
