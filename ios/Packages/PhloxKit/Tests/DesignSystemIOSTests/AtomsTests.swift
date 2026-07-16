import XCTest
import SwiftUI
import AgentDomain
@testable import DesignSystemIOS

// E2-3 検証。Atoms の判定ロジック（variant マッピング・6 状態分岐・表示名解決・タッチ寸法）を
// 純粋ヘルパー/プロパティ経由で検証する。レンダリング結果ではなく、各部品の「決定」を固定する。
// SwiftUI View は @MainActor のため、テストクラスも @MainActor で揃える。
@MainActor
final class AtomsTests: XCTestCase {

    // MARK: - DSButton

    func testButtonMinHeightMeetsTouchTarget() {
        XCTAssertEqual(DSButton.minHeight, DSTouch.minSize)
        XCTAssertGreaterThanOrEqual(DSButton.minHeight, 44)
    }

    func testButtonVariantRoles() {
        XCTAssertNil(DSButton.Variant.primary.role)
        XCTAssertNil(DSButton.Variant.secondary.role)
        XCTAssertEqual(DSButton.Variant.destructive.role, .destructive)
    }

    func testButtonStoresTitleForAccessibility() {
        let button = DSButton("送信", variant: .primary) {}
        XCTAssertEqual(button.title, "送信")
        XCTAssertEqual(button.variant, .primary)
        XCTAssertFalse(button.isLoading)
    }

    func testButtonHasFiveVariants() {
        XCTAssertEqual(DSButton.Variant.allCases.count, 5)
    }

    func testButtonApproveAndDeclineOutlineVariantsHaveNoDestructiveRole() {
        XCTAssertNil(DSButton.Variant.approve.role)
        XCTAssertNil(DSButton.Variant.declineOutline.role)
    }

    // MARK: - DSToggle

    func testToggleStoresTitleAndSubtitle() {
        let toggle = DSToggle(isOn: .constant(true), title: "生体認証", subtitle: "Face ID")
        XCTAssertEqual(toggle.title, "生体認証")
        XCTAssertEqual(toggle.subtitle, "Face ID")
    }

    func testToggleUsesCampStyleTokens() {
        XCTAssertEqual(DSToggle.titleForegroundToken, DSColor.textPrimary)
        XCTAssertEqual(DSToggle.onTintToken, DSColor.statusRunning)
    }

    func testSectionLabelUsesCampQuaternaryAndKerning() {
        XCTAssertEqual(DSSectionLabel.kerning, 0.8)
        let label = DSSectionLabel("実行中・その他")
        XCTAssertEqual(label.title, "実行中・その他")
    }

    func testApproveVariantUsesStatusRunningAndTextOnBrand() {
        XCTAssertEqual(DSButton.Variant.approve.backgroundToken, DSColor.statusRunning)
        XCTAssertEqual(DSButton.Variant.approve.foregroundToken, DSColor.textOnBrand)
    }

    func testDeclineOutlineVariantUsesCampAttentionBorder() {
        XCTAssertEqual(DSButton.Variant.declineOutline.foregroundToken, DSColor.campAttention)
        XCTAssertEqual(DSButton.Variant.declineOutline.backgroundToken, DSColor.surfaceElevated)
        XCTAssertEqual(DSButton.Variant.declineOutline.borderToken, DSColor.campAttention)
    }

    // MARK: - DSStatusChip（6 状態の三重符号化）

    func testStatusChipResolvesDistinctIconsForAllSixStates() {
        let locale = Locale(identifier: "ja_JP")
        let statuses: [SessionStatus] = [
            .starting, .idle, .running,
            .awaitingApproval(prompt: "p"), .completed(exitCode: 0), .error(message: "e"),
        ]
        let icons = statuses.map { DSStatusChip.content(for: $0, locale: locale).icon }
        XCTAssertEqual(Set(icons).count, 6, "6 状態は相異なるアイコンで符号化されること")
    }

    func testStatusChipLabelsAreLocalized() {
        let ja = Locale(identifier: "ja_JP")
        XCTAssertEqual(DSStatusChip.content(for: .running, locale: ja).label, "実行中")
        XCTAssertEqual(DSStatusChip.content(for: .awaitingApproval(prompt: ""), locale: ja).label, "承認待ち")

        let en = Locale(identifier: "en_US")
        XCTAssertEqual(DSStatusChip.content(for: .running, locale: en).label, "running")
        XCTAssertEqual(DSStatusChip.content(for: .awaitingApproval(prompt: ""), locale: en).label, "awaiting")
    }

    func testStatusChipDistinguishesCompletedExitCodes() {
        let en = Locale(identifier: "en_US")
        let ok = DSStatusChip.content(for: .completed(exitCode: 0), locale: en)
        let fail = DSStatusChip.content(for: .completed(exitCode: 1), locale: en)
        XCTAssertEqual(ok.label, "done")
        XCTAssertEqual(fail.label, "exited")
        XCTAssertNotEqual(ok.icon, fail.icon)
    }

    // MARK: - DSCampAgentBadge

    func testCampAgentBadgeAbbreviationsForPrimaryAgents() {
        XCTAssertEqual(DSCampAgentBadge.abbreviation(for: .claudeCode), "CC")
        XCTAssertEqual(DSCampAgentBadge.abbreviation(for: .codex), "Cx")
        XCTAssertEqual(DSCampAgentBadge.abbreviation(for: .cursor), "Cu")
    }

    func testCampAgentBadgeSessionRowSizeMatchesCamp() {
        XCTAssertEqual(DSCampAgentBadge.sessionRowSize, 38)
        XCTAssertEqual(DSCampAgentBadge.sessionRowCornerRadius, 10)
    }

    func testCampAgentBadgeChatAvatarSizeMatchesCamp() {
        XCTAssertEqual(DSCampAgentBadge.chatAvatarSize, 28)
        XCTAssertEqual(DSCampAgentBadge.chatAvatarCornerRadius, 8)
    }

    func testCampAgentBadgeStoresKindAndSize() {
        let badge = DSCampAgentBadge(kind: .codex, size: .chatAvatar)
        XCTAssertEqual(badge.kind, .codex)
        XCTAssertEqual(badge.size, .chatAvatar)
    }

    func testCampAgentBadgeDefaultsToSessionRowSize() {
        let badge = DSCampAgentBadge(kind: .claudeCode)
        XCTAssertEqual(badge.size, .sessionRow)
    }

    // MARK: - DSAgentBadge

    func testAgentBadgeDisplayNames() {
        XCTAssertEqual(DSAgentBadge(kind: .claudeCode).displayName, "Claude Code")
        XCTAssertEqual(DSAgentBadge(kind: .codex).displayName, "Codex")
        XCTAssertEqual(DSAgentBadge(kind: .cursor).displayName, "Cursor")
    }

    func testAgentBadgeDisplayNamesNonEmptyForAllKinds() {
        for kind in AgentKind.allCases {
            XCTAssertFalse(DSAgentBadge(kind: kind).displayName.isEmpty)
        }
    }

    // MARK: - DSTextField

    func testTextFieldMinHeightMeetsTouchTarget() {
        XCTAssertEqual(DSTextField.minHeight, DSTouch.minSize)
    }

    func testTextFieldDefaultsToBodyFontAndNoVisibilityToggle() {
        let field = DSTextField(text: .constant(""), placeholder: "test")
        XCTAssertFalse(field.usesCampMono)
        XCTAssertFalse(field.showsVisibilityToggle)
        XCTAssertFalse(field.isSecure)
    }

    func testTextFieldSupportsCampMono() {
        let field = DSTextField(text: .constant(""), placeholder: "test", usesCampMono: true)
        XCTAssertTrue(field.usesCampMono)
    }

    func testTextFieldSupportsVisibilityToggle() {
        let field = DSTextField(
            text: .constant(""),
            placeholder: "token",
            showsVisibilityToggle: true
        )
        XCTAssertTrue(field.showsVisibilityToggle)
    }

    // MARK: - DSFAB

    func testFABSizeMeetsTouchTarget() {
        XCTAssertEqual(DSFAB.size, DSTouch.minSize)
        XCTAssertGreaterThanOrEqual(DSFAB.size, 44)
    }

    func testFABUsesIconOnlyStyleWithoutFilledBackground() {
        XCTAssertFalse(DSFAB.usesFilledCircleBackground)
    }

    func testFABUsesFullFrameContentShapeForHitTarget() {
        XCTAssertTrue(DSFAB.usesFullFrameContentShape)
        XCTAssertEqual(DSFAB.size, DSTouch.minSize)
    }

    func testFABIconForegroundUsesBrandGradient() {
        XCTAssertEqual(DSFAB.iconBrandGradientStart, DSGradient.brandStart.color)
        XCTAssertEqual(DSFAB.iconBrandGradientEnd, DSGradient.brandEnd.color)
    }

    func testFABIconIsPlus() {
        XCTAssertEqual(DSFAB.iconName, "plus")
    }

    func testFABStoresAccessibilityLabel() {
        let fab = DSFAB(accessibilityLabel: "新規タスク") {}
        XCTAssertEqual(fab.accessibilityLabel, "新規タスク")
    }

    // MARK: - DSGradientButton

    func testGradientButtonHeightMatchesCampPrimaryCTA() {
        XCTAssertEqual(DSGradientButton.height, 50)
    }

    func testGradientButtonUsesCtaGlowShadow() {
        XCTAssertEqual(DSGradientButton.shadowToken, DSShadow.ctaGlow)
    }

    func testGradientButtonCornerRadiusUsesCampToken() {
        XCTAssertEqual(DSGradientButton.cornerRadius, DSRadius.card)
    }

    func testGradientButtonStoresTitleForAccessibility() {
        let button = DSGradientButton("保存して接続", isEnabled: true) {}
        XCTAssertEqual(button.title, "保存して接続")
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(button.isLoading)
    }

    func testGradientButtonDisabledWhenNotEnabled() {
        let button = DSGradientButton("保存して接続", isEnabled: false) {}
        XCTAssertFalse(button.isEnabled)
    }

    // MARK: - DSConnectionIndicator (DP-2-4)

    func testConnectionIndicatorLabelIncludesHost() {
        XCTAssertEqual(DSConnectionIndicator.labelText(host: "100.64.0.1"), "接続済み · 100.64.0.1")
    }

    func testConnectionIndicatorDotDiameterMatchesCamp() {
        XCTAssertEqual(DSConnectionIndicator.dotDiameter, 6)
    }
}
