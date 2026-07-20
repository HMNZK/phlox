import Testing
import Foundation
import SwiftUI
@testable import DesignSystemIOS

@Suite("DSThinkingAnimationModel 白箱")
struct DSThinkingAnimationModelWhiteboxTests {

    @Test("shimmerPeriod は macOS パリティの 1.6")
    func shimmerPeriodMatchesContract() {
        #expect(DSThinkingAnimationModel.shimmerPeriod == 1.6)
    }

    @Test("shimmerMinBrightness と shimmerMargin は契約定数")
    func shimmerConstantsMatchContract() {
        #expect(DSThinkingAnimationModel.shimmerMinBrightness == 0.45)
        #expect(DSThinkingAnimationModel.shimmerMargin == 0.6)
    }

    @Test("shimmerPhase は負の時刻も [0,1) に正規化する")
    func shimmerPhaseNormalizesNegativeTime() {
        let period = DSThinkingAnimationModel.shimmerPeriod
        let phase = DSThinkingAnimationModel.shimmerPhase(at: -0.1)
        #expect(phase >= 0 && phase < 1)
        let expected = (period - 0.1) / period
        #expect(abs(phase - expected) < 1e-9)
    }

    @Test("帯中心が画面内にあるときピーク明度は 1.0")
    func brightnessPeaksAtBandCenter() {
        let center = DSThinkingAnimationModel.shimmerBandCenter(phase: 0.5)
        let peak = DSThinkingAnimationModel.shimmerBrightness(position: center, phase: center)
        #expect(abs(peak - 1.0) < 1e-6)
    }

    @Test("帯が画面外のとき全位置の明度は下限付近")
    func brightnessNearFloorWhenBandOffscreen() {
        let minB = DSThinkingAnimationModel.shimmerMinBrightness
        let center = DSThinkingAnimationModel.shimmerBandCenter(phase: 0.0)
        for step in 0...20 {
            let position = Double(step) / 20
            let b = DSThinkingAnimationModel.shimmerBrightness(position: position, phase: center)
            #expect(b <= minB + 0.05)
        }
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
