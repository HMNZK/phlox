#if os(macOS)
import AppKit
import Foundation
import QuartzCore
import Testing
@testable import DesignSystem

// ADR 0117 の契約（Core Animation 駆動・非表示で停止・帯は凍結 falloff 由来）を、
// 任意ラベルへ一般化した `ShimmerTextView` で維持することを符号化する。
// 旧 SessionFeature `AcceptanceThinkingShimmerViewTests` / `ThinkingShimmerViewWhiteboxTests` の後継。
@Suite("シマーテキスト（Core Animation 駆動）")
@MainActor
struct ShimmerTextViewTests {
    private func makeHost(
        text: String = "Thinking...",
        pointSize: CGFloat = 13,
        color: NSColor = .secondaryLabelColor,
        visible: Bool = true
    ) -> ShimmerTextHostView {
        let host = ShimmerTextView.makeHostViewForTesting(
            text: text,
            pointSize: pointSize,
            color: color,
            visible: visible
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test("シマーは Core Animation の無限反復アニメで周期 period で回る")
    func shimmerRunsInfiniteCoreAnimationAtPeriod() throws {
        let host = makeHost()

        let duration = try #require(host.shimmerAnimationDurationForTesting)
        #expect(abs(duration - ShimmerBandModel.period) < 1e-6)
        #expect(host.shimmerAnimationRepeatsForeverForTesting)
        #expect(host.isShimmerAnimatingForTesting)
    }

    @Test("非表示ではシマーアニメが停止し、再表示で同じアニメのまま再開する")
    func shimmerPausesWhenNotVisibleAndResumes() {
        let host = makeHost(visible: false)
        #expect(!host.isShimmerAnimatingForTesting)
        let duration = host.shimmerAnimationDurationForTesting

        host.setVisibleForTesting(true)
        #expect(host.isShimmerAnimatingForTesting)
        #expect(host.shimmerAnimationDurationForTesting == duration)
    }

    @Test("帯の明度は凍結 minBrightness を下限に有界で、明暗差（bump）を持つ")
    func bandBrightnessBoundedByFrozenFalloff() throws {
        let host = makeHost()
        let brightnesses = host.shimmerBandBrightnessesForTesting
        #expect(!brightnesses.isEmpty)

        let minB = ShimmerBandModel.minBrightness
        for b in brightnesses {
            #expect(!b.isNaN)
            #expect(b >= minB - 1e-6 && b <= 1.0 + 1e-6)
        }
        let peak = try #require(brightnesses.max())
        let floor = try #require(brightnesses.min())
        // 帯の明暗差は取り得る幅（1 − 下限）のほぼ全部を使う＝平坦な塗りではなくシマー帯であること。
        #expect(peak - floor >= (1 - minB) * 0.8)
    }

    @Test("勾配の明度 stop は凍結純関数を host 幅換算位置で評価した値と一致する")
    func brightnessStopsUseFrozenShimmerFunction() {
        let host = makeHost()
        let center = ShimmerBandModel.bandCenter(phase: 0.5)
        let widthInHostWidths = host.shimmerGradientWidthInHostWidthsForTesting
        let expected = (0..<21).map { index -> Double in
            let location = Double(index) / 20
            let hostPosition = 0.5 + (location - 0.5) * widthInHostWidths
            return ShimmerBandModel.brightness(position: hostPosition, phase: center)
        }

        let stops = host.shimmerBandBrightnessesForTesting
        #expect(stops.count == expected.count)
        for (actual, want) in zip(stops, expected) {
            #expect(abs(actual - want) < 1e-12)
        }
        #expect(stops.first! <= ShimmerBandModel.minBrightness + 0.1)
        #expect(stops[10] >= 0.99)
    }

    @Test("勾配 locations は常に 0...1 の昇順で固定される")
    func gradientLocationsStayWithinUnitInterval() {
        let locations = makeHost().shimmerGradientLocationsForTesting

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
        let host = makeHost()
        let positions = try #require(host.shimmerBandCenterPositionsForTesting)
        let margin = ShimmerBandModel.margin
        let halfWidth = host.shimmerGradientWidthInHostWidthsForTesting / 2

        #expect(positions.from <= -margin)
        #expect(positions.to >= 1 + margin)
        #expect(positions.from - halfWidth <= 0)
        #expect(positions.from + halfWidth >= 1)
        #expect(positions.to - halfWidth <= 0)
        #expect(positions.to + halfWidth >= 1)
    }

    @Test("テーマ色の更新がテキスト色へ反映される")
    func colorUpdateReflectsIntoText() throws {
        let host = makeHost()

        host.updateColorForTesting(.systemRed)
        let applied = try #require(host.appliedTextColorForTesting)
        let a = try #require(applied.usingColorSpace(.sRGB))
        let b = try #require(NSColor.systemRed.usingColorSpace(.sRGB))
        #expect(abs(a.redComponent - b.redComponent) < 0.02)
        #expect(abs(a.greenComponent - b.greenComponent) < 0.02)
        #expect(abs(a.blueComponent - b.blueComponent) < 0.02)
    }

    // MARK: - 任意ラベルへの一般化（活動状態で文字列が変わる）

    @Test("マスクは渡した文字列をイタリックの指定実寸で描く")
    func maskUsesGivenTextItalicAndPointSize() {
        let host = makeHost(text: "Searching...", pointSize: 16)

        #expect(host.maskedTextForTesting == "Searching...")
        #expect(host.maskFontIsItalicForTesting)
        #expect(host.maskFontPointSizeForTesting == 16)
    }

    @Test("状態語が変わってもアニメは追加し直されず文字列だけ差し替わる")
    func textUpdateKeepsSingleAnimation() {
        let host = makeHost(text: "Thinking...")
        let duration = host.shimmerAnimationDurationForTesting
        let width = host.intrinsicContentSize.width

        host.updateTextForTesting("Editing...")

        #expect(host.maskedTextForTesting == "Editing...")
        #expect(host.shimmerAnimationDurationForTesting == duration)
        #expect(host.isShimmerAnimatingForTesting)
        #expect(host.intrinsicContentSize.width != width, "実寸が文字列に追従すること")
    }

    @Test("全活動状態のラベルでマスクが構成できる")
    func allActivityLabelsRender() {
        for label in ["Thinking...", "Searching...", "Running...", "Editing...", "Writing...", "Waiting..."] {
            let host = makeHost(text: label)
            #expect(host.maskedTextForTesting == label)
            #expect(host.intrinsicContentSize.width > 0)
        }
    }
}
#endif
