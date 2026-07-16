import Testing
import SwiftUI
@testable import DesignSystemIOS

/// task-2 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-2.md）。
/// 契約: チャットバブル配色を macOS デスクトップ版に揃える。
/// - ユーザー = `DSColor.userBubble`（ニュートラル淡面）＋前景 `textPrimary`
/// - エージェント = 背景なし
/// 出典: macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift:117 /
///       macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
@MainActor
@Suite struct Task2AcceptanceTests {
    @Test func userBubbleMatchesDesktopNeutralSurface() {
        #expect(DSChatBubble.backgroundColor(for: .user) == DSColor.userBubble)
        #expect(!DSChatBubble.usesBrandGradient(for: .user))
    }

    @Test func agentBubbleHasNoBackgroundLikeDesktop() {
        #expect(DSChatBubble.backgroundColor(for: .agent) == nil)
    }

    @Test func userMessageForegroundUsesPrimaryText() {
        #expect(DSChatBubble.userMessageForeground == DSColor.textPrimary)
    }

    /// 不変条件: 配置と角丸は変更しない（macOS も user 右寄せ / agent 左寄せ）。
    @Test func alignmentAndCornerRadiusUnchanged() {
        #expect(DSChatBubble.horizontalAlignment(for: .agent) == .leading)
        #expect(DSChatBubble.horizontalAlignment(for: .user) == .trailing)
        #expect(DSChatBubble.cornerRadius == DSRadius.card)
    }
}
