import AgentDomain
import Testing
import Foundation
import SwiftUI
@testable import DesignSystemIOS

@Suite("DS チャット活動部品 白箱")
@MainActor
struct ChatActivityComponentsWhiteboxTests {

    @Test("DSThinkingIndicator は全状態で body を構築できる", arguments: AgentActivityState.allCases)
    func thinkingIndicatorBuildsBody(state: AgentActivityState) {
        _ = DSThinkingIndicator(state: state).body
    }

    @Test("DSThinkingIndicator は reasoningPreview ありで body を構築できる")
    func thinkingIndicatorBuildsBodyWithPreview() {
        _ = DSThinkingIndicator(state: .searching, reasoningPreview: "方針検討").body
    }

    @Test("DSSubAgentRow は平文 wire をそのまま body に載せられる")
    func subAgentRowBuildsBody() {
        _ = DSSubAgentRow(text: "Sub-agent explore-map running: 調査").body
    }

    @Test("DSReasoningText は本文テキストで body を構築できる")
    func reasoningTextBuildsBody() {
        _ = DSReasoningText(text: "パリティ改善の意図を整理").body
    }
}
