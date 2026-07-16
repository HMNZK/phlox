import XCTest
import SwiftUI
import AgentDomain
import PhloxCore
@testable import DesignSystemIOS

// E2-4 検証。Molecules の決定ロジック（attention アクセント・プロンプト抽出・送信可否・
// 提示する承認決定・バナーのアイコン）を純粋ヘルパー/プロパティで検証する。
@MainActor
final class MoleculesTests: XCTestCase {

    private func makeSession(status: SessionStatus, subtitle: String = "") -> Session {
        Session(id: "s", name: "Rose", agent: .claudeCode, status: status,
                subtitle: subtitle, updatedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - DSSessionRow (DP-2-4 camp)

    func testSessionRowCampAbbreviationsDelegateToCampAgentBadge() {
        XCTAssertEqual(DSSessionRow.campAbbreviation(for: .claudeCode), DSCampAgentBadge.abbreviation(for: .claudeCode))
        XCTAssertEqual(DSSessionRow.campAbbreviation(for: .codex), DSCampAgentBadge.abbreviation(for: .codex))
        XCTAssertEqual(DSSessionRow.campAbbreviation(for: .cursor), DSCampAgentBadge.abbreviation(for: .cursor))
    }

    func testSessionRowCampDetailLineCombinesSubtitleAndTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let updated = now.addingTimeInterval(-120)
        let line = DSSessionRow.campDetailLine(
            subtitle: "出力中",
            statusLabel: "実行中",
            updatedAt: updated,
            now: now
        )
        XCTAssertEqual(line, "出力中 · 2分前")
    }

    func testSessionRowCampDetailLineFallsBackToStatusLabel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let updated = now.addingTimeInterval(-300)
        let line = DSSessionRow.campDetailLine(
            subtitle: "",
            statusLabel: "完了",
            updatedAt: updated,
            now: now
        )
        XCTAssertEqual(line, "完了 · 5分前")
    }

    func testSessionRowCampTimeShowsSecondsUnderOneMinute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DSSessionRow.campRelativeTime(from: now.addingTimeInterval(-12), now: now), "12秒前")
        XCTAssertEqual(DSSessionRow.campRelativeTime(from: now.addingTimeInterval(-3), now: now), "今")
    }

    func testSessionRowOpacityReflectsIdleAndCompleted() {
        XCTAssertEqual(DSSessionRow.rowOpacity(for: .idle), 0.7, accuracy: 0.001)
        XCTAssertEqual(DSSessionRow.rowOpacity(for: .completed(exitCode: 0)), 0.82, accuracy: 0.001)
        XCTAssertEqual(DSSessionRow.rowOpacity(for: .running), 1.0, accuracy: 0.001)
    }

    func testSessionRowAgentBadgeSizeDelegatesToCampAgentBadge() {
        XCTAssertEqual(DSSessionRow.agentBadgeSize, DSCampAgentBadge.sessionRowSize)
        XCTAssertEqual(DSSessionRow.agentBadgeCornerRadius, DSCampAgentBadge.sessionRowCornerRadius)
    }

    // MARK: - DSSkeletonRow (DP-2-4)

    func testSkeletonRowDefaultBarWidthRatios() {
        let row = DSSkeletonRow(agentKind: .claudeCode)
        XCTAssertEqual(row.primaryBarWidthRatio, 0.6, accuracy: 0.001)
        XCTAssertEqual(row.secondaryBarWidthRatio, 0.4, accuracy: 0.001)
    }

    func testSkeletonRowUsesAgentBadgeSizeFromSessionRow() {
        XCTAssertEqual(DSSkeletonRow.agentBadgeSize, DSSessionRow.agentBadgeSize)
    }

    // MARK: - DSAttentionRow

    func testAttentionRowUsesPromptWhenAwaiting() {
        let row = DSAttentionRow(session: makeSession(status: .awaitingApproval(prompt: "削除しますか？"))) {}
        XCTAssertEqual(row.promptPreview, "削除しますか？")
    }

    func testAttentionRowFallsBackToSubtitleWhenNoPrompt() {
        let row = DSAttentionRow(session: makeSession(status: .running, subtitle: "実行中の補足")) {}
        XCTAssertEqual(row.promptPreview, "実行中の補足")
    }

    func testAttentionRowCampTokensMatchDesign() {
        XCTAssertEqual(DSAttentionRow.accentBarWidth, DSSpacing.xs)
        XCTAssertEqual(DSAttentionRow.cornerRadius, DSRadius.card)
        XCTAssertEqual(DSAttentionRow.accentColor, DSColor.campAttention)
        XCTAssertEqual(DSAttentionRow.surfaceColor, DSColor.campSurfaceEmphasis)
        XCTAssertEqual(DSAttentionRow.borderColor, DSColor.campAttention.opacity(0.32))
    }

    func testAttentionRowSubtitleAppendsRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let session = Session(
            id: "s",
            name: "Rose",
            agent: .claudeCode,
            status: .awaitingApproval(prompt: ""),
            subtitle: "ファイル削除の承認待ち",
            updatedAt: now.addingTimeInterval(-120)
        )
        let row = DSAttentionRow(session: session, now: now) {}
        XCTAssertEqual(row.subtitleLine, "ファイル削除の承認待ち · 2分前")
    }

    func testAttentionRowSubtitlePreservesQuestionFormat() {
        let session = makeSession(
            status: .awaitingApproval(prompt: "v2 契約で進めますか？"),
            subtitle: "回答待ち: 「v2 契約で進めますか？」"
        )
        let row = DSAttentionRow(session: session) {}
        XCTAssertEqual(row.subtitleLine, "回答待ち: 「v2 契約で進めますか？」")
        XCTAssertEqual(DSAttentionRow.attentionKind(for: session), .question)
    }

    func testAttentionRowChipLabelsDistinguishApprovalAndQuestion() {
        let ja = Locale(identifier: "ja_JP")
        let approval = makeSession(
            status: .awaitingApproval(prompt: "削除?"),
            subtitle: "ファイル削除の承認待ち"
        )
        let question = makeSession(
            status: .awaitingApproval(prompt: "v2?"),
            subtitle: "回答待ち: 「v2?」"
        )
        XCTAssertEqual(DSAttentionRow.chipLabel(for: approval, locale: ja), "承認待ち")
        XCTAssertEqual(DSAttentionRow.chipLabel(for: question, locale: ja), "質問待ち")
    }

    func testAttentionRowChipUsesAwaitingTint() {
        XCTAssertEqual(DSAttentionRow.chipTint, DSColor.statusAwaitingApproval)
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

    func testCampRelativeTimeDelegatesToCompact() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let date = now.addingTimeInterval(-12)
        XCTAssertEqual(DSSessionRow.campRelativeTime(from: date, now: now), DSRelativeTime.compact(from: date, now: now))
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
    // Task2AcceptanceTests へ移管した（旧: グラデ背景・campSurfaceEmphasis・textOnBrand）。

    func testChatBubbleAlignmentReflectsRole() {
        XCTAssertEqual(DSChatBubble.horizontalAlignment(for: .agent), .leading)
        XCTAssertEqual(DSChatBubble.horizontalAlignment(for: .user), .trailing)
    }

    func testChatBubbleAccessibilitySpeakerLabels() {
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .agent), "エージェント")
        XCTAssertEqual(DSChatBubble.accessibilitySpeakerLabel(for: .user), "あなた")
    }

    func testChatBubbleCornerRadiusUsesCampCardToken() {
        XCTAssertEqual(DSChatBubble.cornerRadius, DSRadius.card)
    }

    func testChatBubbleAgentAvatarSizeDelegatesToCampAgentBadge() {
        XCTAssertEqual(DSChatBubble.agentAvatarSize, DSCampAgentBadge.chatAvatarSize)
        XCTAssertEqual(DSChatBubble.agentAvatarCornerRadius, DSCampAgentBadge.chatAvatarCornerRadius)
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

    // MARK: - DSFixedBottomCTA

    func testFixedBottomCTAUsesScreenHorizontalInset() {
        XCTAssertEqual(DSFixedBottomCTA.horizontalInset, DSSpacing.l)
    }

    func testFixedBottomCTAStoresTitleAndEnabledState() {
        let cta = DSFixedBottomCTA("保存して接続", isEnabled: false) {}
        XCTAssertEqual(cta.title, "保存して接続")
        XCTAssertFalse(cta.isEnabled)
    }

    func testFixedBottomCTADefaultsToEnabled() {
        let cta = DSFixedBottomCTA("起動して送信") {}
        XCTAssertTrue(cta.isEnabled)
    }
}
