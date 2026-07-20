import Foundation
import Testing
@testable import SessionFeature

@Suite("Thinking シマー白箱テスト")
struct ThinkingShimmerWhiteboxTests {
    @Test func 基準日より前でも位相は正規化される() {
        let date = Date(timeIntervalSinceReferenceDate: -ThinkingAnimationModel.shimmerPeriod / 4)

        let phase = ThinkingAnimationModel.shimmerPhase(date: date)

        #expect(abs(phase - 0.75) < 1e-9)
    }

    @Test func 明度はピークを中心に対称かつ滑らかに減衰する() {
        let phase = 0.5
        let nearLeft = ThinkingAnimationModel.shimmerBrightness(position: 0.4, phase: phase)
        let nearRight = ThinkingAnimationModel.shimmerBrightness(position: 0.6, phase: phase)
        let farRight = ThinkingAnimationModel.shimmerBrightness(position: 0.8, phase: phase)

        #expect(abs(nearLeft - nearRight) < 1e-9)
        #expect(nearRight > farRight)
        #expect(farRight > ThinkingAnimationModel.shimmerMinBrightness)
    }

    // MARK: - 折返しの継ぎ目が見えないこと（かくつき回帰）

    @Test func 帯中心は画面外余白まで写像される() {
        let margin = ThinkingAnimationModel.shimmerMargin
        #expect(abs(ThinkingAnimationModel.shimmerBandCenter(phase: 0) - (-margin)) < 1e-9)
        #expect(abs(ThinkingAnimationModel.shimmerBandCenter(phase: 1) - (1 + margin)) < 1e-9)
        #expect(abs(ThinkingAnimationModel.shimmerBandCenter(phase: 0.5) - 0.5) < 1e-9)
    }

    @Test func 折返し時は帯が画面外にあり継ぎ目が見えない() {
        // phase の折返し直前(→1)と直後(=0)で、画面内(position∈[0,1])の明度は全域ほぼ下限＝
        // 帯は画面外にある。かつ両者は連続で、右端→左端の瞬間移動（かくつき）が起きない。
        let minB = ThinkingAnimationModel.shimmerMinBrightness
        let centerHigh = ThinkingAnimationModel.shimmerBandCenter(phase: 0.999)
        let centerLow = ThinkingAnimationModel.shimmerBandCenter(phase: 0.0)
        for step in 0...20 {
            let position = Double(step) / 20
            let high = ThinkingAnimationModel.shimmerBrightness(position: position, phase: centerHigh)
            let low = ThinkingAnimationModel.shimmerBrightness(position: position, phase: centerLow)
            #expect(high <= minB + 0.05)
            #expect(low <= minB + 0.05)
            #expect(abs(high - low) < 0.05)
        }
    }

    @Test func 帯が画面内に来ると明度は最大に達する() {
        // 周期のどこかで帯中心が画面内へ入り、その位置の明度が 1.0 に達する（実際に光る）。
        let center = ThinkingAnimationModel.shimmerBandCenter(phase: 0.5)
        #expect(center >= 0 && center <= 1)
        let peak = ThinkingAnimationModel.shimmerBrightness(position: center, phase: center)
        #expect(abs(peak - 1.0) < 1e-6)
    }
}
