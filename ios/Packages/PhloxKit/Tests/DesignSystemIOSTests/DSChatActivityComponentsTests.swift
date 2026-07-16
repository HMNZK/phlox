import Testing
import Foundation
import SwiftUI
@testable import DesignSystemIOS

@Suite("DSThinkingAnimationModel 白箱")
struct DSThinkingAnimationModelWhiteboxTests {

    @Test("period は契約レンジ 1.0...1.6 に収まる")
    func periodIsWithinContractRange() {
        #expect(DSThinkingAnimationModel.period >= 1.0)
        #expect(DSThinkingAnimationModel.period <= 1.6)
    }

    @Test("dotCount は 3 固定")
    func dotCountIsThree() {
        #expect(DSThinkingAnimationModel.dotCount == 3)
    }

    @Test("正弦波位相によりドット 0 と 1 は同時刻で異なる不透明度になりうる")
    func adjacentDotsCanDifferAtSameTime() {
        let a = DSThinkingAnimationModel.opacity(dotIndex: 0, at: 0.25)
        let b = DSThinkingAnimationModel.opacity(dotIndex: 1, at: 0.25)
        #expect(abs(a - b) > 0.05)
    }

    @Test("wave の極値付近で 0.2 と 1.0 に近い値を取る")
    func opacityReachesExtremaNearBounds() {
        var sawLow = false
        var sawHigh = false
        for t in stride(from: 0.0, through: DSThinkingAnimationModel.period, by: 0.01) {
            for dot in 0..<DSThinkingAnimationModel.dotCount {
                let value = DSThinkingAnimationModel.opacity(dotIndex: dot, at: t)
                if value < 0.25 { sawLow = true }
                if value > 0.95 { sawHigh = true }
            }
        }
        #expect(sawLow)
        #expect(sawHigh)
    }
}

@Suite("DS チャット活動部品 白箱")
@MainActor
struct ChatActivityComponentsWhiteboxTests {

    @Test("DSThinkingIndicator は reasoningPreview なしでも body を構築できる")
    func thinkingIndicatorBuildsBody() {
        _ = DSThinkingIndicator().body
    }

    @Test("DSThinkingIndicator は reasoningPreview ありで body を構築できる")
    func thinkingIndicatorBuildsBodyWithPreview() {
        _ = DSThinkingIndicator(reasoningPreview: "方針検討").body
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
