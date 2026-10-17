import XCTest
import SwiftUI
import AgentDomain
import PhloxCore
@testable import DesignSystemIOS

// E2-4 検証。Molecules の決定ロジック（attention アクセント・プロンプト抽出・送信可否・
// 提示する承認決定・バナーのアイコン）を純粋ヘルパー/プロパティで検証する。
@MainActor
final class MoleculesTests: XCTestCase {

    func testThinkingIndicatorUsesCanonicalPendingStatusWords() {
        let locale = Locale(identifier: "ja_JP")
        let approval = DSThinkingIndicator(
            state: .waiting,
            status: .awaitingApproval(prompt: "")
        )
        let question = DSThinkingIndicator(state: .waiting, status: .awaitingUserQuestion)

        XCTAssertEqual(approval.displayLabel(locale: locale), "承認待ち")
        XCTAssertEqual(question.displayLabel(locale: locale), "質問あり")
    }

    // MARK: - DSInputBar

    func testInputBarCannotSubmitWhenEmptyOrWhitespace() {
        XCTAssertFalse(DSInputBar.canSubmit(text: "", isLoading: false))
        XCTAssertFalse(DSInputBar.canSubmit(text: "   \n", isLoading: false))
    }

    func testInputBarCannotSubmitWhileLoading() {
        XCTAssertFalse(DSInputBar.canSubmit(text: "hello", isLoading: true))
    }

    func testInputBarCanSubmitWithText() {
        XCTAssertTrue(DSInputBar.canSubmit(text: "hello", isLoading: false))
    }

    func testInputBarMinHeightMeetsTouchTarget() {
        XCTAssertEqual(DSInputBar.minHeight, DSTouch.minSize)
    }

    // MARK: - DSApprovalBar

    func testApprovalBarOffersAcceptAndDecline() {
        XCTAssertEqual(Set(DSApprovalBar.offeredDecisions), [.accept, .decline])
        XCTAssertEqual(DSApprovalBar.offeredDecisions.count, 2)
    }

    func testApprovalBarAcceptButtonUsesApproveVariant() {
        XCTAssertEqual(DSApprovalBar.acceptButtonVariant, .approve)
    }

    func testApprovalBarDeclineButtonUsesDeclineOutlineVariant() {
        XCTAssertEqual(DSApprovalBar.declineButtonVariant, .declineOutline)
    }

    func testApprovalBarDoesNotUseLegacyPrimaryDestructiveVariants() {
        XCTAssertNotEqual(DSApprovalBar.acceptButtonVariant, .primary)
        XCTAssertNotEqual(DSApprovalBar.declineButtonVariant, .destructive)
    }

    // MARK: - DSApprovalRequestCard (DP-2-5)

    func testApprovalRequestCardLabelMatchesCamp() {
        XCTAssertEqual(DSApprovalRequestCard.labelText, "承認リクエスト")
    }

    func testApprovalRequestCardExtractsLeadingFileName() {
        XCTAssertEqual(
            DSApprovalRequestCard.extractEmphasizedFileName(
                from: "ControlServer.swift を削除して続行しますか？"
            ),
            "ControlServer.swift"
        )
        XCTAssertNil(DSApprovalRequestCard.extractEmphasizedFileName(from: "削除しますか？"))
    }

    func testApprovalRequestCardPromptSegmentsEmphasizeFileName() {
        let segments = DSApprovalRequestCard.promptSegments(
            prompt: "ControlServer.swift を削除し続行しますか？",
            emphasizedFileName: "ControlServer.swift"
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].isEmphasized)
        XCTAssertEqual(segments[0].text, "ControlServer.swift")
        XCTAssertFalse(segments[1].isEmphasized)
        XCTAssertEqual(segments[1].text, " を削除し続行しますか？")
    }

    func testApprovalRequestCardPromptSegmentsWithoutEmphasis() {
        let segments = DSApprovalRequestCard.promptSegments(
            prompt: "削除しますか？",
            emphasizedFileName: ""
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertFalse(segments[0].isEmphasized)
        XCTAssertEqual(segments[0].text, "削除しますか？")
    }

    func testApprovalRequestCardBorderOpacityMatchesCamp() {
        XCTAssertEqual(DSApprovalRequestCard.borderOpacity, 0.3, accuracy: 0.001)
    }

    // MARK: - DSResultBanner

    func testResultBannerIconReflectsError() {
        XCTAssertEqual(DSResultBanner.iconName(isError: true), DSIcon.errorBadge)
        XCTAssertNotEqual(DSResultBanner.iconName(isError: false), DSResultBanner.iconName(isError: true))
    }

    // MARK: - DSRelativeTime

    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-3), now: now), "今")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-30), now: now), "30秒前")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-120), now: now), "2分前")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-7200), now: now), "2時間前")
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(-172800), now: now), "2日前")
    }

    func testSubmitBarLogicSharedBetweenInputBars() {
        XCTAssertTrue(DSSubmitBarLogic.canSubmit(text: "hello", isLoading: false))
        XCTAssertFalse(DSSubmitBarLogic.canSubmit(text: "", isLoading: false))
        XCTAssertEqual(
            DSInputBar.canSubmit(text: "x", isLoading: false),
            DSChatInputBar.canSubmit(text: "x", isLoading: false)
        )
    }

    func testInputBarFocusAndSendAccessibilityContract() {
        XCTAssertTrue(DSInputBar.usesFocusState)
        XCTAssertEqual(DSInputBar.sendAccessibilityLabel, "送信")
    }

    func testRelativeTimeClampsFutureToNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DSRelativeTime.compact(from: now.addingTimeInterval(60), now: now), "今")
    }

    // MARK: - DSChatBubble (DP-2-6 / カンプ⑦)
    // 配色（背景・前景）の契約は task-2 で macOS 揃えに仕様変更され、
    // DSChatBubbleStyleTests へ移管した（エージェント印の強調表示）。

    func testChatBubbleAlignmentReflectsRole() {
        XCTAssertEqual(DSChatBubble.horizontalAlignment(for: .agent), .leading)
        XCTAssertEqual(DSChatBubble.horizontalAlignment(for: .user), .trailing)
    }

    func testChatBubbleAccessibilitySpeakerLabelsIncludeAgentName() {
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .agent), "エージェント")
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .agent, agentKind: .claudeCode), "Claude Code")
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .agent, agentKind: .codex), "Codex")
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .agent, agentKind: .cursor), "Cursor")
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .user), "あなた")
    }

    func testChatBubbleCornerRadiusUsesCampCardToken() {
        XCTAssertEqual(DSChatBubble.cornerRadius, DSRadius.card)
    }

    func testChatBubbleAgentLogoUsesTwentyEightPointSize() {
        XCTAssertEqual(DSChatBubble.agentLogoSize, 28)
    }

    // MARK: - DSChatInputBar (DP-2-6 / カンプ⑦)

    func testChatInputBarCannotSubmitWhenEmptyOrWhitespace() {
        XCTAssertFalse(DSChatInputBar.canSubmit(text: "", isLoading: false))
        XCTAssertFalse(DSChatInputBar.canSubmit(text: "   \n", isLoading: false))
    }

    func testChatInputBarCannotSubmitWhileLoading() {
        XCTAssertFalse(DSChatInputBar.canSubmit(text: "hello", isLoading: true))
    }

    func testChatInputBarCanSubmitWithText() {
        XCTAssertTrue(DSChatInputBar.canSubmit(text: "hello", isLoading: false))
    }

    func testChatInputBarMinHeightMeetsTouchTarget() {
        XCTAssertEqual(DSChatInputBar.minHeight, DSTouch.minSize)
    }

    func testChatInputBarFieldCornerRadiusMatchesCampPill() {
        XCTAssertEqual(DSChatInputBar.fieldCornerRadius, DSRadius.dialog)
    }

    func testChatInputBarSendButtonUsesArrowUpIcon() {
        XCTAssertEqual(DSChatInputBar.sendButtonIconName, "arrow.up")
    }

}
