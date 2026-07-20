import Testing
import Foundation
import SwiftUI
@testable import DesignSystemIOS

// task-2 受け入れテスト（PM 著・凍結）。契約: tasks/task-2.md
// iOS の Thinking インジケータを macOS と同じ「明度が左→右へ流れるシマー」に揃える。
// 点滅ドットは廃止。DSThinkingAnimationModel はシマー純関数のみを提供する（macOS
// ThinkingAnimationModel のシマー関数と同一セマンティクス。ただし iOS 慣習に合わせ
// 時刻入力は TimeInterval を取る）。実装役はこのテストを満たす本体を埋める（本ファイルは不変）。

@Suite("DSThinkingAnimationModel シマー受け入れ（純関数・macOS パリティ）")
struct ThinkingShimmerAcceptanceTests {

    @Test("shimmerPhase は [0,1) に収まり周期 shimmerPeriod で反復する")
    func phaseNormalizedAndPeriodic() {
        let period = DSThinkingAnimationModel.shimmerPeriod
        #expect(period > 0)
        for t in stride(from: -3.0, through: 6.0, by: 0.037) {
            let p = DSThinkingAnimationModel.shimmerPhase(at: t)
            #expect(p >= 0 && p < 1, "t=\(t) phase=\(p)")
            let q = DSThinkingAnimationModel.shimmerPhase(at: t + period)
            #expect(abs(p - q) < 1e-9, "t=\(t) 非周期")
        }
    }

    @Test("帯中心は画面外余白まで線形写像される")
    func bandCenterMapsToOffscreenMargins() {
        let margin = DSThinkingAnimationModel.shimmerMargin
        #expect(abs(DSThinkingAnimationModel.shimmerBandCenter(phase: 0) - (-margin)) < 1e-9)
        #expect(abs(DSThinkingAnimationModel.shimmerBandCenter(phase: 1) - (1 + margin)) < 1e-9)
        #expect(abs(DSThinkingAnimationModel.shimmerBandCenter(phase: 0.5) - 0.5) < 1e-9)
    }

    @Test("明度は [shimmerMinBrightness, 1] に収まり決定的")
    func brightnessRangeAndDeterministic() {
        let minB = DSThinkingAnimationModel.shimmerMinBrightness
        for center in stride(from: -0.6, through: 1.6, by: 0.05) {
            for step in 0...20 {
                let position = Double(step) / 20
                let b = DSThinkingAnimationModel.shimmerBrightness(position: position, phase: center)
                #expect(b >= minB - 1e-9 && b <= 1 + 1e-9, "center=\(center) pos=\(position) b=\(b)")
                let b2 = DSThinkingAnimationModel.shimmerBrightness(position: position, phase: center)
                #expect(b == b2)
            }
        }
    }

    @Test("帯が画面内に来ると明度はピーク 1.0 に達する")
    func brightnessPeaksWhenBandOnScreen() {
        let center = DSThinkingAnimationModel.shimmerBandCenter(phase: 0.5)
        #expect(center >= 0 && center <= 1)
        let peak = DSThinkingAnimationModel.shimmerBrightness(position: center, phase: center)
        #expect(abs(peak - 1.0) < 1e-6)
    }

    @Test("明度はピークを中心に対称かつ距離とともに減衰する")
    func brightnessSymmetricDecay() {
        let center = 0.5
        let near = DSThinkingAnimationModel.shimmerBrightness(position: 0.55, phase: center)
        let far = DSThinkingAnimationModel.shimmerBrightness(position: 0.75, phase: center)
        let nearLeft = DSThinkingAnimationModel.shimmerBrightness(position: 0.45, phase: center)
        #expect(abs(near - nearLeft) < 1e-9, "ピーク中心で対称でない")
        #expect(near > far, "距離が増えて明度が減衰しない")
    }

    @Test("折返し時は帯が画面外にあり継ぎ目（かくつき）が見えない")
    func foldingSeamInvisible() {
        let minB = DSThinkingAnimationModel.shimmerMinBrightness
        let centerHigh = DSThinkingAnimationModel.shimmerBandCenter(phase: 0.999)
        let centerLow = DSThinkingAnimationModel.shimmerBandCenter(phase: 0.0)
        for step in 0...20 {
            let position = Double(step) / 20
            let high = DSThinkingAnimationModel.shimmerBrightness(position: position, phase: centerHigh)
            let low = DSThinkingAnimationModel.shimmerBrightness(position: position, phase: centerLow)
            #expect(high <= minB + 0.05, "折返し直前に画面内が光っている pos=\(position)")
            #expect(low <= minB + 0.05, "折返し直後に画面内が光っている pos=\(position)")
            #expect(abs(high - low) < 0.05, "折返し前後が不連続 pos=\(position)")
        }
    }
}

@Suite("DS チャット活動部品 受け入れ（存在・初期化）")
@MainActor
struct ChatActivityComponentsAcceptanceTests {

    @Test("DSThinkingIndicator が reasoningPreview の有無どちらでも初期化できる")
    func thinkingIndicatorInitializes() {
        _ = DSThinkingIndicator()
        _ = DSThinkingIndicator(reasoningPreview: "実装方針を検討中")
    }

    @Test("DSSubAgentRow がテキストで初期化できる")
    func subAgentRowInitializes() {
        _ = DSSubAgentRow(text: "Sub-agent explore-map running: コードベース調査")
    }

    @Test("DSReasoningText がテキストで初期化できる")
    func reasoningTextInitializes() {
        _ = DSReasoningText(text: "ユーザーの意図はチャット UI のパリティ改善")
    }
}
