import Foundation
import Testing
@testable import DesignSystem

// ADR 0067 が凍結したシマー純関数の契約。旧 SessionFeature `ThinkingAnimationModel.shimmer*` /
// 旧 iOS `DSThinkingAnimationModel` の受け入れ・白箱テストを共有モデルへ移したもの。
//   位相: 決定論・[0,1)・周期的・時間とともに前進（左→右）
//   明度: 決定論・[minBrightness, 1.0] で有界・phase 位置で最大・離れるほど減衰
@Suite("シマー帯の純関数（ADR 0067 凍結仕様）")
struct ShimmerBandModelTests {
    private let period = ShimmerBandModel.period
    private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }

    @Test func 位相は決定論() {
        #expect(ShimmerBandModel.phase(date: date(123.4)) == ShimmerBandModel.phase(date: date(123.4)))
    }

    @Test func 位相は0以上1未満() {
        for t in stride(from: 0.0, through: period * 3, by: period / 10) {
            let p = ShimmerBandModel.phase(date: date(t))
            #expect(p >= 0.0 && p < 1.0)
        }
    }

    @Test func 位相は周期的() {
        let base = 50.0
        let a = ShimmerBandModel.phase(date: date(base))
        let b = ShimmerBandModel.phase(date: date(base + period))
        #expect(abs(a - b) < 1e-6)
    }

    @Test func 位相は時間とともに前進する_左から右() {
        let t1 = 10.0
        let t2 = t1 + period / 4
        let p1 = ShimmerBandModel.phase(date: date(t1))
        let p2 = ShimmerBandModel.phase(date: date(t2))
        let advance = (p2 - p1 + 1.0).truncatingRemainder(dividingBy: 1.0)
        #expect(abs(advance - 0.25) < 0.05)
    }

    @Test func 基準日より前でも位相は正規化される() {
        #expect(abs(ShimmerBandModel.phase(date: date(-period / 4)) - 0.75) < 1e-9)
    }

    @Test func 明度は下限と1の間で有界() {
        let minB = ShimmerBandModel.minBrightness
        for phase in stride(from: 0.0, through: 1.0, by: 0.1) {
            for pos in stride(from: 0.0, through: 1.0, by: 0.1) {
                let b = ShimmerBandModel.brightness(position: pos, phase: phase)
                #expect(!b.isNaN)
                #expect(b >= minB - 1e-9 && b <= 1.0 + 1e-9)
            }
        }
    }

    @Test func 明度はphase位置で最大かつ離れるほど減衰() {
        let phase = 0.5
        let peak = ShimmerBandModel.brightness(position: phase, phase: phase)
        #expect(abs(peak - 1.0) < 1e-6)
        let mid = ShimmerBandModel.brightness(position: 0.7, phase: phase)
        let far = ShimmerBandModel.brightness(position: 0.9, phase: phase)
        #expect(peak >= mid - 1e-9)
        #expect(mid >= far - 1e-9)
    }

    @Test func 明度はピークを中心に対称() {
        let phase = 0.5
        let left = ShimmerBandModel.brightness(position: 0.4, phase: phase)
        let right = ShimmerBandModel.brightness(position: 0.6, phase: phase)
        #expect(abs(left - right) < 1e-9)
        #expect(right > ShimmerBandModel.brightness(position: 0.8, phase: phase))
    }

    // MARK: - 折返しの継ぎ目が見えないこと（かくつき回帰）

    @Test func 帯中心は画面外余白まで写像される() {
        let margin = ShimmerBandModel.margin
        #expect(abs(ShimmerBandModel.bandCenter(phase: 0) - (-margin)) < 1e-9)
        #expect(abs(ShimmerBandModel.bandCenter(phase: 1) - (1 + margin)) < 1e-9)
        #expect(abs(ShimmerBandModel.bandCenter(phase: 0.5) - 0.5) < 1e-9)
    }

    @Test func 折返し時は帯が画面外にあり継ぎ目が見えない() {
        let minB = ShimmerBandModel.minBrightness
        let centerHigh = ShimmerBandModel.bandCenter(phase: 0.999)
        let centerLow = ShimmerBandModel.bandCenter(phase: 0.0)
        for step in 0...20 {
            let position = Double(step) / 20
            let high = ShimmerBandModel.brightness(position: position, phase: centerHigh)
            let low = ShimmerBandModel.brightness(position: position, phase: centerLow)
            #expect(high <= minB + 0.05)
            #expect(low <= minB + 0.05)
            #expect(abs(high - low) < 0.05)
        }
    }

    @Test func 帯が画面内に来ると明度は最大に達する() {
        let center = ShimmerBandModel.bandCenter(phase: 0.5)
        #expect(center >= 0 && center <= 1)
        #expect(abs(ShimmerBandModel.brightness(position: center, phase: center) - 1.0) < 1e-6)
    }
}
