import AppKit
import Testing
@testable import SessionFeature

@Suite("ThinkingShimmerView white-box")
@MainActor
struct ThinkingShimmerViewWhiteboxTests {
    @Test("勾配の明度 stop は凍結純関数を host 幅換算位置で評価した値と一致する（帯を原寸に保つ）")
    func brightnessStopsUseFrozenShimmerFunction() {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor,
            scale: 1,
            visible: true
        )
        // 勾配は被覆のため host 幅の widthInHostWidths 倍あるので、stop 位置(0..1)を host 幅換算へ
        // 写像してから凍結 falloff を評価する。勾配全幅にバンプを張ると帯が広がりシマーが消えるため、
        // この写像で原実装と同じ帯幅（host 幅ぶん）に保つ。
        let center = ThinkingAnimationModel.shimmerBandCenter(phase: 0.5)
        let widthInHostWidths = host.shimmerGradientWidthInHostWidthsForTesting
        let expected = (0..<21).map { index -> Double in
            let location = Double(index) / 20
            let hostPosition = 0.5 + (location - 0.5) * widthInHostWidths
            return ThinkingAnimationModel.shimmerBrightness(position: hostPosition, phase: center)
        }

        #expect(host.shimmerBandBrightnessesForTesting.count == expected.count)
        for (actual, expected) in zip(host.shimmerBandBrightnessesForTesting, expected) {
            #expect(abs(actual - expected) < 1e-12)
        }
        // 帯が原寸に戻っていること（端は下限近く・中央は最大）＝コントラストが残る回帰ガード。
        let stops = host.shimmerBandBrightnessesForTesting
        #expect(stops.first! <= ThinkingAnimationModel.shimmerMinBrightness + 0.1)
        #expect(stops[10] >= 0.99)
    }

    @Test("可視性の切替は既存の CA アニメを保ったまま停止・再開する")
    func visibilityToggleKeepsSingleAnimation() {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor,
            scale: 1,
            visible: true
        )
        let originalDuration = host.shimmerAnimationDurationForTesting

        host.setVisibleForTesting(false)
        #expect(!host.isShimmerAnimatingForTesting)
        host.setVisibleForTesting(true)

        #expect(host.isShimmerAnimatingForTesting)
        #expect(host.shimmerAnimationDurationForTesting == originalDuration)
    }

    @Test("勾配 locations は常に 0...1 の昇順で固定される")
    func gradientLocationsStayWithinUnitInterval() {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor,
            scale: 1,
            visible: true
        )
        let locations = host.shimmerGradientLocationsForTesting

        #expect(locations.count == 21)
        #expect(locations.first == 0)
        #expect(locations.last == 1)
        for (left, right) in zip(locations, locations.dropFirst()) {
            #expect(left >= 0 && right <= 1)
            #expect(left < right)
        }
    }

    @Test("並進アニメは帯を両端の画面外へ出しても勾配でホスト全域を覆う")
    func translatingBandLeavesBothEdgesWithoutExposingHost() throws {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor,
            scale: 1,
            visible: true
        )
        let positions = try #require(host.shimmerBandCenterPositionsForTesting)
        let margin = ThinkingAnimationModel.shimmerMargin
        let halfWidth = host.shimmerGradientWidthInHostWidthsForTesting / 2

        #expect(positions.from <= -margin)
        #expect(positions.to >= 1 + margin)
        #expect(positions.from - halfWidth <= 0)
        #expect(positions.from + halfWidth >= 1)
        #expect(positions.to - halfWidth <= 0)
        #expect(positions.to + halfWidth >= 1)
    }
}
