import XCTest
import SwiftUI
@testable import DesignSystemIOS

// E2-2 検証。iOS 固有トークン（DSTouch/DSMotion/DSIcon/DSFont 追加）と、共有 DesignSystem の
// 再エクスポート（@_exported import）が DesignSystemIOS 経由で到達できることを検証する。
final class TokensTests: XCTestCase {

    func testTouchMinSizeIs44() {
        XCTAssertEqual(DSTouch.minSize, 44)
    }

    func testRowMinHeightIsAtLeastTouchTarget() {
        XCTAssertGreaterThanOrEqual(DSTouch.rowMinHeight, DSTouch.minSize)
    }

    func testIconNamesAreNonEmpty() {
        let icons = [
            DSIcon.sessions, DSIcon.spawn, DSIcon.send, DSIcon.delete, DSIcon.settings,
            DSIcon.close, DSIcon.clear, DSIcon.chevron, DSIcon.reachable, DSIcon.unreachable,
            DSIcon.connectionTest, DSIcon.faceID, DSIcon.lock, DSIcon.approve, DSIcon.decline,
            DSIcon.empty, DSIcon.errorBadge,
        ]
        for name in icons {
            XCTAssertFalse(name.isEmpty, "icon name should not be empty")
        }
    }

    func testMotionTokensAreAccessible() {
        // Animation は Equatable 比較が安定しないため、参照可能であること（型解決）を確認する。
        let animations: [Animation] = [DSMotion.spring, DSMotion.easeOut, DSMotion.quick]
        XCTAssertEqual(animations.count, 3)
    }

    func testReExportsCoreSpacingAndRadius() {
        // DesignSystemIOS だけ import すれば共有コアトークンに到達できる（@_exported）。
        XCTAssertEqual(DSSpacing.l, 16)
        XCTAssertEqual(DSSpacing.s, 8)
        XCTAssertEqual(DSRadius.m, 8)
    }

    func testReExportsStatusVocabulary() {
        // 状態語彙（SSOT）も DesignSystemIOS から使える。
        XCTAssertEqual(StatusBadge.englishLabel(for: .running), "running")
        XCTAssertEqual(StatusBadge.englishLabel(for: .awaitingApproval(prompt: "")), "awaiting")
        // 12 Design System の語彙（完了に終了コードを付けない。4a58aa9 で変更）。
        XCTAssertEqual(StatusBadge.label(for: .completed(exitCode: 0)), "完了")
    }

    func testAddedDynamicTypeFontsAreAccessible() {
        let fonts: [Font] = [
            DSFont.title1, DSFont.title2, DSFont.headline, DSFont.subheadline,
            DSFont.footnote, DSFont.body, DSFont.caption, DSFont.displayDot(for: .large),
        ]
        XCTAssertEqual(fonts.count, 8)
    }

    func testDisplayDotSizesFollowDynamicTypeSpecification() {
        XCTAssertEqual(DSFont.displayDotSize(for: .large), 28)
        XCTAssertEqual(DSFont.displayDotSize(for: .xxxLarge), 34)
        XCTAssertEqual(DSFont.displayDotSize(for: .accessibility1), 34)
        XCTAssertEqual(DSFont.displayDotSize(for: .accessibility2), 34)
        XCTAssertEqual(DSFont.displayDotSize(for: .accessibility3), 34)
        XCTAssertEqual(DSFont.displayDotSize(for: .accessibility4), 34)
        XCTAssertEqual(DSFont.displayDotSize(for: .accessibility5), 44)
    }

    // MARK: - iOS redesign colors

    func testAccentAndAccentOnFillMatchDarkTheme() {
        withTheme(AppTheme.phlox.id) {
            expectColor(IOSColor.accent, 0xF2F2F4)
            expectColor(IOSColor.accentOnFill, 0x000000)
            XCTAssertNotEqual(IOSColor.accent, IOSColor.accentOnFill)
        }
    }

    func testIOSColorTokensMatchLightTheme() {
        withTheme(AppTheme.phloxLight.id) {
            expectColor(IOSColor.accent, 0x1D1D1F)
            expectColor(IOSColor.accentOnFill, 0xFFFFFF)
            expectColor(IOSColor.text.primary, 0x1D1D1F)
            expectColor(IOSColor.text.secondary, 0x56565E)
            expectColor(IOSColor.text.tertiary, 0x6B6B73)
            expectColor(IOSColor.stop, 0xD62F26)
            expectColor(IOSColor.badge, 0xD62F26)
            expectColor(IOSColor.status.approval, 0xA8430A)
            expectColor(IOSColor.status.approvalBackground, 0xFFEBD6)
            expectColor(IOSColor.status.question, 0x1555C0)
            expectColor(IOSColor.status.questionBackground, 0xE3EEFF)
            expectColor(IOSColor.status.error, 0xB8241C)
            expectColor(IOSColor.status.errorBackground, 0xFDE7E5)
            expectColor(IOSColor.status.stalled, 0x5B3FA8)
            expectColor(IOSColor.status.stalledBackground, 0xF1ECFB)
            expectColor(IOSColor.status.caution, 0x8A5300)
            expectColor(IOSColor.status.success, 0x1F7A3A)
            expectColor(IOSColor.status.neutral, 0x3A3A42)
            expectColor(IOSColor.bg.base, 0xF2F2F7)
            expectColor(IOSColor.bg.card, 0xFFFFFF)
            expectColor(IOSColor.bg.raised, 0xE4E4EB)
            expectColor(IOSColor.bg.code, 0xF7F6FA)
            expectColor(IOSColor.bg.fill, 0x767680, opacity: 0.12)
            expectColor(IOSColor.bg.separator, 0x3C3C43, opacity: 0.18)
            expectColor(IOSColor.bg.glass, 0xFFFFFF, opacity: 0.62)
            expectColor(IOSColor.bg.bar, 0xF9F9FB, opacity: 0.94)
            expectColor(IOSColor.bg.sheet, 0xF2F2F7, opacity: 0.97)
            expectColor(IOSColor.bg.menu, 0xFAFAFC, opacity: 0.94)
            XCTAssertEqual(IOSColor.bg.dim, Color.black.opacity(0.28))
        }
    }

    func testIOSColorTokensMatchDarkTheme() {
        withTheme(AppTheme.phlox.id) {
            expectColor(IOSColor.accent, 0xF2F2F4)
            expectColor(IOSColor.accentOnFill, 0x000000)
            expectColor(IOSColor.text.primary, 0xF2F2F4)
            expectColor(IOSColor.text.secondary, 0xAFAFB6)
            expectColor(IOSColor.text.tertiary, 0x9D9DA5)
            expectColor(IOSColor.stop, 0xE5483F)
            expectColor(IOSColor.badge, 0xE5483F)
            expectColor(IOSColor.status.approval, 0xFFB46E)
            expectColor(IOSColor.status.approvalBackground, 0xFF9F0A, opacity: 0.20)
            expectColor(IOSColor.status.question, 0x8DB9FF)
            expectColor(IOSColor.status.questionBackground, 0x0A84FF, opacity: 0.22)
            expectColor(IOSColor.status.error, 0xFF8C82)
            expectColor(IOSColor.status.errorBackground, 0xFF453A, opacity: 0.18)
            expectColor(IOSColor.status.stalled, 0xC9B6FF)
            expectColor(IOSColor.status.stalledBackground, 0x9678E6, opacity: 0.20)
            expectColor(IOSColor.status.caution, 0xF4BD68)
            expectColor(IOSColor.status.success, 0x6FD08C)
            expectColor(IOSColor.status.neutral, 0xD4D4DA)
            expectColor(IOSColor.bg.base, 0x000000)
            expectColor(IOSColor.bg.card, 0x1C1C1E)
            expectColor(IOSColor.bg.raised, 0x2C2C30)
            expectColor(IOSColor.bg.code, 0x141416)
            expectColor(IOSColor.bg.fill, 0x767680, opacity: 0.28)
            expectColor(IOSColor.bg.separator, 0x545458, opacity: 0.65)
            expectColor(IOSColor.bg.glass, 0x26262A, opacity: 0.60)
            expectColor(IOSColor.bg.bar, 0x161618, opacity: 0.94)
            expectColor(IOSColor.bg.sheet, 0x1C1C1E, opacity: 0.97)
            expectColor(IOSColor.bg.menu, 0x2C2C30, opacity: 0.94)
            XCTAssertEqual(IOSColor.bg.dim, Color.black.opacity(0.45))
        }
    }

    func testDialogShadowValuesMatchDesign() {
        XCTAssertEqual(DSShadow.dialog.y, 30)
        XCTAssertEqual(DSShadow.dialog.radius, 60)
        XCTAssertEqual(DSShadow.dialog.color, Color.black.opacity(0.7))
    }

    func testCampRadiusDialogAndActionSheet() {
        XCTAssertEqual(DSRadius.dialog, 22)
        XCTAssertEqual(DSRadius.actionSheet, 16)
        XCTAssertEqual(DSRadius.card, 14)
    }

    func testMonospacedFontsAreAccessible() {
        let fonts: [Font] = [DSFont.mono, DSFont.monoCaption, DSFont.campMono, DSFont.campMonoCaption]
        XCTAssertEqual(fonts.count, 4)
    }

    func testRedesignReplacesLegacyColorsWithSemanticTokens() {
        withTheme(AppTheme.phlox.id) {
            expectColor(IOSColor.status.approvalBackground, 0xFF9F0A, opacity: 0.20)
            expectColor(IOSColor.bg.menu, 0x2C2C30, opacity: 0.94)
            expectColor(IOSColor.bg.code, 0x141416)
            expectColor(IOSColor.text.tertiary, 0x9D9DA5)
            expectColor(IOSColor.accent, 0xF2F2F4)
            expectColor(IOSColor.status.error, 0xFF8C82)
            expectColor(IOSColor.accentOnFill, 0x000000)
        }
    }

    func testModalBackdropUsesRedesignDimToken() {
        withTheme(AppTheme.phlox.id) {
            XCTAssertEqual(IOSColor.bg.dim, Color.black.opacity(0.45))
        }
    }

    private func withTheme(_ id: String, assert: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defaults.set(id, forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }
        assert()
    }

    private func expectColor(
        _ actual: Color,
        _ hex: UInt32,
        opacity: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual,
            Color(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                opacity: opacity
            ),
            file: file,
            line: line
        )
    }
}
