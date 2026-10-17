import Testing
import SwiftUI
@testable import DesignSystemIOS

/// チャットバブルの配色が macOS 版と揃う（ユーザー=淡面+通常文字色、エージェント=背景なし）。
/// 配色が変わると落ちる。配置・角丸は MoleculesTests が守る。
@Suite("DSChat bubble style") @MainActor struct DSChatBubbleStyleTests {
    @Test func userBubbleUsesNeutralSurfaceAndAgentHasNoBackground() {
        #expect(DSChatBubble.backgroundColor(for: .user) == IOSColor.bg.raised)
        #expect(DSChatBubble.backgroundColor(for: .agent) == nil)
    }

    @Test(arguments: [DSChatBubble.Role.user, .agent])
    func messageHighlightUsesNoAgentSpecificColor(role: DSChatBubble.Role) {
        if role == .agent {
            #expect(DSChatBubble.highlightColor(for: role) == IOSColor.text.secondary)
        } else {
            #expect(DSChatBubble.highlightColor(for: role) == nil)
        }
    }

    @Test func userForegroundUsesPrimaryText() {
        #expect(DSChatBubble.userMessageForeground == IOSColor.text.primary)
    }
}
