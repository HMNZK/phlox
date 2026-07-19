import Foundation
import Testing
@testable import SessionFeature

// task-3 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約: ThinkingAnimationModel の shimmerPhase / shimmerBrightness 純関数仕様（tasks/task-3.md）。
//   位相: 決定論・[0,1)・周期的・時間とともに前進（左→右）
//   明度: 決定論・[shimmerMinBrightness, 1.0] で有界・phase 位置で最大・離れるほど減衰

@Suite("Acceptance: Thinking シマー（task-3）")
struct AcceptanceThinkingShimmerTests {
    private let period = ThinkingAnimationModel.shimmerPeriod
    private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }

    @Test func 位相は決定論() {
        #expect(ThinkingAnimationModel.shimmerPhase(date: date(123.4))
            == ThinkingAnimationModel.shimmerPhase(date: date(123.4)))
    }

    @Test func 位相は0以上1未満() {
        for t in stride(from: 0.0, through: period * 3, by: period / 10) {
            let p = ThinkingAnimationModel.shimmerPhase(date: date(t))
            #expect(p >= 0.0 && p < 1.0)
        }
    }

    @Test func 位相は周期的() {
        let base = 50.0
        let a = ThinkingAnimationModel.shimmerPhase(date: date(base))
        let b = ThinkingAnimationModel.shimmerPhase(date: date(base + period))
        #expect(abs(a - b) < 1e-6)
    }

    @Test func 位相は時間とともに前進する_左から右() {
        // 1/4 周期進めると位相は前方（左→右）へ約 0.25 進む（wrap を +1 で畳んで判定）。
        let t1 = 10.0
        let t2 = t1 + period / 4
        let p1 = ThinkingAnimationModel.shimmerPhase(date: date(t1))
        let p2 = ThinkingAnimationModel.shimmerPhase(date: date(t2))
        let advance = (p2 - p1 + 1.0).truncatingRemainder(dividingBy: 1.0)
        #expect(abs(advance - 0.25) < 0.05)
    }

    @Test func 明度は下限と1の間で有界() {
        let minB = ThinkingAnimationModel.shimmerMinBrightness
        for phase in stride(from: 0.0, through: 1.0, by: 0.1) {
            for pos in stride(from: 0.0, through: 1.0, by: 0.1) {
                let b = ThinkingAnimationModel.shimmerBrightness(position: pos, phase: phase)
                #expect(!b.isNaN)
                #expect(b >= minB - 1e-9 && b <= 1.0 + 1e-9)
            }
        }
    }

    @Test func 明度はphase位置で最大() {
        let phase = 0.5
        let peak = ThinkingAnimationModel.shimmerBrightness(position: phase, phase: phase)
        #expect(abs(peak - 1.0) < 1e-6)
        #expect(peak >= ThinkingAnimationModel.shimmerBrightness(position: 0.1, phase: phase) - 1e-9)
        #expect(peak >= ThinkingAnimationModel.shimmerBrightness(position: 0.9, phase: phase) - 1e-9)
    }

    @Test func 明度はphaseから離れるほど減衰() {
        let phase = 0.5
        let near = ThinkingAnimationModel.shimmerBrightness(position: 0.5, phase: phase)
        let mid = ThinkingAnimationModel.shimmerBrightness(position: 0.7, phase: phase)
        let far = ThinkingAnimationModel.shimmerBrightness(position: 0.9, phase: phase)
        #expect(near >= mid - 1e-9)
        #expect(mid >= far - 1e-9)
    }
}
