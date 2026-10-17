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

    func testToggleUsesRedesignTextAndSuccessTokens() {
        XCTAssertEqual(DSToggle.titleForegroundToken, IOSColor.text.primary)
        XCTAssertEqual(DSToggle.onTintToken, IOSColor.status.success)
    }

    func testSectionLabelUsesCampQuaternaryAndKerning() {
        XCTAssertEqual(DSSectionLabel.kerning, 0.8)
        let label = DSSectionLabel("実行中・その他")
        XCTAssertEqual(label.title, "実行中・その他")
    }

    func testApproveVariantUsesAccentFillAndContrastText() {
        XCTAssertEqual(DSButton.Variant.approve.backgroundToken, IOSColor.accent)
        XCTAssertEqual(DSButton.Variant.approve.foregroundToken, IOSColor.accentOnFill)
    }

    func testDeclineOutlineVariantUsesErrorTextAndBorder() {
        XCTAssertEqual(DSButton.Variant.declineOutline.foregroundToken, IOSColor.status.error)
        XCTAssertEqual(DSButton.Variant.declineOutline.backgroundToken, IOSColor.bg.fill)
        XCTAssertEqual(DSButton.Variant.declineOutline.borderToken, IOSColor.status.error)
    }

    // MARK: - DSStatusChip

    func testStatusChipUsesCanonicalWordsAndOmitsWaiting() {
        let locale = Locale(identifier: "ja_JP")
        let statuses: [SessionStatus] = [
            .starting, .idle, .running,
            .awaitingApproval(prompt: "p"), .awaitingUserQuestion,
            .completed(exitCode: 0), .error(message: "e"),
        ]
        let labels = statuses.map { DSStatusChip.presentation(for: $0, locale: locale).label }
        XCTAssertEqual(labels, ["起動中", nil, "実行中", "承認待ち", "質問あり", "完了", "エラー"])
        XCTAssertEqual(Set(labels.compactMap { $0 }).count, 6)
    }

    func testStatusChipLabelsAreLocalized() {
        let ja = Locale(identifier: "ja_JP")
        XCTAssertEqual(DSStatusChip.presentation(for: .running, locale: ja).label, "実行中")
        XCTAssertEqual(DSStatusChip.presentation(for: .awaitingApproval(prompt: ""), locale: ja).label, "承認待ち")
        XCTAssertEqual(DSStatusChip.presentation(for: .awaitingUserQuestion, locale: ja).label, "質問あり")

        let en = Locale(identifier: "en_US")
        XCTAssertEqual(DSStatusChip.presentation(for: .running, locale: en).label, "running")
        XCTAssertEqual(DSStatusChip.presentation(for: .awaitingApproval(prompt: ""), locale: en).label, "awaiting")
        XCTAssertEqual(DSStatusChip.presentation(for: .awaitingUserQuestion, locale: en).label, "question")
    }

    func testStatusChipUsesTheSameCompletedStyleForAllExitCodes() {
        let en = Locale(identifier: "en_US")
        let ok = DSStatusChip.presentation(for: .completed(exitCode: 0), locale: en)
        let fail = DSStatusChip.presentation(for: .completed(exitCode: 1), locale: en)
        XCTAssertEqual(ok.label, "done")
        XCTAssertEqual(fail.label, "done")
        XCTAssertEqual(ok.color, fail.color)
        XCTAssertEqual(ok.weight, fail.weight)
    }

    func testStatusVocabularyDefinesWordColorAndWeightForEveryCurrentState() {
        let ja = Locale(identifier: "ja_JP")
        let cases: [(SessionStatus, String?, Color?, IOSStatusWeight?)] = [
            (.idle, nil, nil, nil),
            (.starting, "起動中", IOSColor.text.tertiary, .regular),
            (.running, "実行中", IOSColor.text.secondary, .medium),
            (.awaitingApproval(prompt: ""), "承認待ち", IOSColor.status.approval, .semibold),
            (.awaitingUserQuestion, "質問あり", IOSColor.status.question, .semibold),
            (.error(message: ""), "エラー", IOSColor.status.error, .semibold),
            (.completed(exitCode: 0), "完了", IOSColor.text.tertiary, .regular),
        ]

        for (status, label, color, weight) in cases {
            let presentation = IOSStatusVocabulary.presentation(for: status, locale: ja)
            XCTAssertEqual(presentation.label, label)
            XCTAssertEqual(presentation.color, color)
            XCTAssertEqual(presentation.weight, weight)
        }
    }

    // MARK: - AgentBrandIcon

    func testBrandIconsUseRegistryDisplayNames() {
        XCTAssertEqual(AgentBrandIcon(kind: .claudeCode, size: 32).descriptor.displayName, "Claude Code")
        XCTAssertEqual(AgentBrandIcon(kind: .codex, size: 32).descriptor.displayName, "Codex")
        XCTAssertEqual(AgentBrandIcon(kind: .cursor, size: 32).descriptor.displayName, "Cursor")
    }

    func testSessionAgentLogoSizeMatchesRowsAndSkeletons() {
        XCTAssertEqual(DSSessionRow.agentLogoSize, 38)
        XCTAssertEqual(DSSkeletonRow.agentLogoSize, 38)
    }

    func testChatAgentLogoUsesTwentyEightPointSize() {
        XCTAssertEqual(DSChatBubble.agentLogoSize, 28)
    }

    func testBrandIconStoresRegistryDescriptorAndSize() {
        let icon = AgentBrandIcon(kind: .codex, size: 28)
        XCTAssertEqual(icon.descriptor.displayName, "Codex")
        XCTAssertEqual(icon.size, 28)
    }

    func testBrandIconUsesDesignSystemAssetBundle() {
        XCTAssertNotEqual(AgentBrandIcon.assetBundle.bundleURL, Bundle.main.bundleURL)
    }

    // MARK: - Agent display names

    func testAgentNamesMatchTheSharedRegistry() {
        XCTAssertEqual(AgentBrandIcon(kind: .claudeCode, size: 24).descriptor.displayName, AgentRegistry.descriptor(for: .claudeCode).displayName)
        XCTAssertEqual(AgentBrandIcon(kind: .codex, size: 24).descriptor.displayName, AgentRegistry.descriptor(for: .codex).displayName)
        XCTAssertEqual(AgentBrandIcon(kind: .cursor, size: 24).descriptor.displayName, AgentRegistry.descriptor(for: .cursor).displayName)
    }

    func testAgentNamesAreNonEmptyForAllKinds() {
        for kind in AgentKind.allCases {
            XCTAssertFalse(AgentBrandIcon(kind: kind, size: 24).descriptor.displayName.isEmpty)
        }
    }

    // MARK: - Primary button

    func testPrimaryButtonMeetsTouchTarget() {
        XCTAssertEqual(DSButton.minHeight, DSTouch.minSize)
        XCTAssertGreaterThanOrEqual(DSButton.minHeight, 44)
    }

    func testPrimaryButtonUsesAccentAndContrastText() {
        XCTAssertEqual(DSButton.Variant.primary.backgroundToken, IOSColor.accent)
        XCTAssertEqual(DSButton.Variant.primary.foregroundToken, IOSColor.accentOnFill)
    }

    func testPrimaryButtonUsesSharedCornerRadius() {
        XCTAssertEqual(DSButton.cornerRadius, DSRadius.m)
    }

    func testPrimaryButtonStoresTitleForAccessibility() {
        let button = DSButton("保存して接続", variant: .primary) {}
        XCTAssertEqual(button.title, "保存して接続")
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.variant, .primary)
        XCTAssertFalse(button.isLoading)
    }

    func testPrimaryButtonStoresLoadingState() {
        let button = DSButton("保存して接続", variant: .primary, isLoading: true) {}
        XCTAssertTrue(button.isLoading)
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.title, "保存して接続")
    }

}
