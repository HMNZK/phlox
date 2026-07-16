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
        XCTAssertEqual(StatusBadge.label(for: .completed(exitCode: 0)), "完了 (0)")
    }

    func testAddedDynamicTypeFontsAreAccessible() {
        let fonts: [Font] = [DSFont.title1, DSFont.title2, DSFont.headline, DSFont.subheadline, DSFont.footnote, DSFont.body, DSFont.caption]
        XCTAssertEqual(fonts.count, 7)
    }

    // MARK: - DP-2-1 Camp tokens (design.md §2)

    func testBrandGradientUsesCampRGBValues() {
        XCTAssertEqual(DSGradient.brandStart, RGB(0xA8, 0x55, 0xF7))
        XCTAssertEqual(DSGradient.brandEnd, RGB(0xF4, 0x72, 0xB6))
        XCTAssertEqual(DSGradient.brandAngleDegrees, 135, accuracy: 0.001)
        let gradient: LinearGradient = DSGradient.brand
        XCTAssertNotNil(gradient)
    }

    func testCampShadowGlowValuesMatchDesign() {
        XCTAssertEqual(DSShadow.ctaGlow.x, 0)
        XCTAssertEqual(DSShadow.ctaGlow.y, 8)
        XCTAssertEqual(DSShadow.ctaGlow.radius, 24)
        XCTAssertEqual(DSShadow.fabGlow.y, 6)
        XCTAssertEqual(DSShadow.fabGlow.radius, 16)
        XCTAssertEqual(DSShadow.dialog.y, 30)
        XCTAssertEqual(DSShadow.dialog.radius, 60)
        XCTAssertEqual(DSShadow.ctaGlow.color, RGB(0xA8, 0x55, 0xF7).color.opacity(0.6))
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

    func testCampColorAliasesMatchDesign() {
        XCTAssertEqual(DSColor.campSurfaceEmphasis, RGB(0x22, 0x1A, 0x33).color)
        XCTAssertEqual(DSColor.campSurfaceDialog, RGB(0x1F, 0x18, 0x30).color)
        XCTAssertEqual(DSColor.campOutputBackground, RGB(0x0C, 0x0A, 0x14).color)
        XCTAssertEqual(DSColor.campTextQuaternary, RGB(0xB0, 0xA8, 0xBE).color)
        XCTAssertEqual(DSColor.campAccentBright, RGB(0xC0, 0x84, 0xFC).color)
        XCTAssertEqual(DSColor.campAttention, RGB(0xF4, 0x72, 0xB6).color)
        XCTAssertEqual(DSColor.textOnBrand, RGB(0xFF, 0xFF, 0xFF).color)
    }

    func testCampModalBackdropMatchesDesignBrightness() {
        XCTAssertEqual(DSColor.campModalBackdropBrightness, 0.45, accuracy: 0.001)
        XCTAssertEqual(DSColor.campModalBackdropOpacity, 0.55, accuracy: 0.001)
        XCTAssertEqual(DSColor.campModalBackdrop, Color.black.opacity(0.55))
    }
}
