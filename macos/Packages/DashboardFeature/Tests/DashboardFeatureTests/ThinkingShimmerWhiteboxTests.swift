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
}
