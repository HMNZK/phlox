import XCTest
import SwiftUI
import DesignSystemIOS
@testable import Features

// DP-4-5 検証。カンプ⑤の文言・件数表示を View 層で保証する（中央アラート・単段確認）。
final class DeleteConfirmationViewTests: XCTestCase {

    func testTitleMatchesCamp() {
        XCTAssertEqual(DeleteConfirmationCopy.title, "セッションを削除しますか？")
    }

    func testCascadeBodyMentionsDescendantCount() {
        let body = DeleteConfirmationCopy.body(cascadeCount: 3)
        XCTAssertTrue(body.contains("子孫 3 件"))
        XCTAssertTrue(body.contains("Mac 側で削除されます"))
        XCTAssertTrue(body.contains("元に戻せません"))
    }

    func testZeroCascadeBodyOmitsDescendants() {
        let body = DeleteConfirmationCopy.body(cascadeCount: 0)
        XCTAssertFalse(body.contains("子孫"))
        XCTAssertTrue(body.contains("Mac 側で削除されます"))
    }

    func testDeleteButtonLabelIncludesTotalCount() {
        XCTAssertEqual(DeleteConfirmationCopy.deleteButtonLabel(totalCount: 4), "削除（4件）")
        XCTAssertEqual(DeleteConfirmationCopy.deleteButtonLabel(totalCount: 1), "削除（1件）")
    }

    func testBackdropMetricsMatchRedesignValuesInLightAndDarkThemes() {
        let previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: ThemeStore.themeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        XCTAssertEqual(DeleteConfirmationMetrics.backdropBrightness, 0.72, accuracy: 0.001)
        XCTAssertEqual(DeleteConfirmationMetrics.backdropOverlayOpacity, 0.28, accuracy: 0.001)

        UserDefaults.standard.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
        XCTAssertEqual(DeleteConfirmationMetrics.backdropBrightness, 0.55, accuracy: 0.001)
        XCTAssertEqual(DeleteConfirmationMetrics.backdropOverlayOpacity, 0.45, accuracy: 0.001)
    }

    func testBackdropMetricsUseIOSDimTokenInLightAndDarkThemes() {
        let previousTheme = UserDefaults.standard.object(forKey: ThemeStore.themeKey)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: ThemeStore.themeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        UserDefaults.standard.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        XCTAssertEqual(IOSColor.bg.dim, Color.black.opacity(DeleteConfirmationMetrics.backdropOverlayOpacity))
        UserDefaults.standard.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
        XCTAssertEqual(IOSColor.bg.dim, Color.black.opacity(DeleteConfirmationMetrics.backdropOverlayOpacity))
    }
}
