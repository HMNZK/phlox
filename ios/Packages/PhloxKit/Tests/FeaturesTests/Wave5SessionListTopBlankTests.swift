import Foundation
import Testing
import DesignSystemIOS

@Suite("wave-5 セッション一覧上端の回帰", .serialized)
struct Wave5SessionListTopBlankTests {
    @Test("同じテーマは一度だけ適用し、テーマ変更時だけ再適用する")
    func navigationAppearanceInstallationIsIdempotent() {
        let themeID = "wave5-idempotence-\(UUID().uuidString)"
        let changedThemeID = "\(themeID)-changed"
        let before = DSNavigationChrome.appearanceInstallationState

        DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
        let afterFirstInstallation = DSNavigationChrome.appearanceInstallationState

        DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
        let afterRepeatedInstallation = DSNavigationChrome.appearanceInstallationState

        #expect(afterFirstInstallation.themeID == themeID)
        #expect(afterFirstInstallation.installationCount == before.installationCount + 1)
        #expect(afterRepeatedInstallation == afterFirstInstallation)

        DSNavigationChrome.installUIKitAppearanceIfNeeded(for: changedThemeID)
        let afterThemeChange = DSNavigationChrome.appearanceInstallationState

        #expect(afterThemeChange.themeID == changedThemeID)
        #expect(afterThemeChange.installationCount == afterFirstInstallation.installationCount + 1)
    }
}
