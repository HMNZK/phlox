import Testing
import SwiftUI
@testable import DesignSystemIOS

/// task-2 白箱テスト（実装役著）。`backgroundColor(for:)` が body の単一の正である契約を補強する。
@Suite @MainActor struct Task2ChatBubbleParityTests {
    @Test func backgroundColorContractMatchesDesktopParity() {
        #expect(DSChatBubble.backgroundColor(for: .user) == DSColor.userBubble)
        #expect(DSChatBubble.backgroundColor(for: .agent) == nil)
    }

    @Test(arguments: [DSChatBubble.Role.user, .agent])
    func brandGradientDisabledForAllRoles(role: DSChatBubble.Role) {
        #expect(!DSChatBubble.usesBrandGradient(for: role))
    }

    @Test func userForegroundReadableOnNeutralSurface() {
        #expect(DSChatBubble.userMessageForeground == DSColor.textPrimary)
        #expect(DSChatBubble.userMessageForeground != DSColor.textOnBrand)
    }

    @Test func agentBubbleBackgroundTokenRemovedFromContract() {
        // `agentBubbleBackground` は廃止。エージェント背景は `backgroundColor(for:)` が nil を返す。
        #expect(DSChatBubble.backgroundColor(for: .agent) == nil)
    }
}
