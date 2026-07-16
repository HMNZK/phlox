import XCTest
import DesignSystemIOS
@testable import Features

// ナビゲーション chrome 検証。セッション一覧ツールバーが DS トークン準拠であることを保証する。
final class SessionListViewTests: XCTestCase {

    func testNavigationChromeUsesSurfaceAndDarkScheme() {
        XCTAssertEqual(DSNavigationChrome.barBackground, DSColor.surface)
        XCTAssertEqual(DSNavigationChrome.barColorScheme, .dark)
        XCTAssertEqual(DSNavigationChrome.accentTint, DSColor.campAccentBright)
    }

    func testNavigationChromeInstallsUIKitAppearanceWithoutCrashing() {
        DSNavigationChrome.installUIKitAppearanceIfNeeded()
    }
}
