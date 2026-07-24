import AppKit
import QuartzCore
import SwiftUI

/// 「Thinking...」の明度帯を Core Animation 側だけで移動させる表示。
/// SwiftUI の TimelineView を使わないため、アニメーション中に SwiftUI の表示木は再評価されない。
public struct ThinkingShimmerView: NSViewRepresentable {
    private let color: NSColor
    private let scale: CGFloat
    private let isVisible: Bool

    public init(color: Color, scale: CGFloat, isVisible: Bool) {
        self.color = NSColor(color)
        self.scale = scale
        self.isVisible = isVisible
    }

    public func makeNSView(context: Context) -> ThinkingShimmerHostView {
        ThinkingShimmerHostView(color: color, scale: scale, visible: isVisible)
    }

    public func updateNSView(_ nsView: ThinkingShimmerHostView, context: Context) {
        // 離散的な入力だけを反映する。ここでアニメを追加し直さないことが重要。
        nsView.update(color: color, scale: scale, visible: isVisible)
    }
}

/// Core Animation のレイヤーとテキストマスクを保持する AppKit ビュー。
public final class ThinkingShimmerHostView: NSView {
    private static let shimmerAnimationKey = "phlox.thinking.shimmer.position"
    private static let stopCount = 21

    /// 1×1 の論理座標をホストの実寸へ拡大する。これによりリサイズ時にも
    /// アニメーションの値を追加し直さず、帯の移動量を正規化座標で保てる。
    private let gradientContainer = CALayer()
    private let gradient = CAGradientLayer()
    private let textMask = CATextLayer()
    private var color: NSColor
    private var scale: CGFloat
    private var isVisible: Bool
    private var textSize: NSSize = .zero
    private var brightnesses: [Double] = []

    init(color: NSColor, scale: CGFloat, visible: Bool) {
        self.color = color
        self.scale = scale
        self.isVisible = visible
        super.init(frame: .zero)
        wantsLayer = true
        configureLayers()
        updateTextMetrics()
        configureGradientStops()
        addShimmerAnimation()
        applyVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: NSSize { textSize }

    public override func layout() {
        super.layout()
        textMask.frame = bounds
        gradientContainer.setAffineTransform(
            CGAffineTransform(scaleX: bounds.width, y: bounds.height)
        )
    }

    func update(color: NSColor, scale: CGFloat, visible: Bool) {
        if !self.color.isEqual(color) {
            self.color = color
            updateGradientColors()
        }
        if self.scale != scale {
            self.scale = scale
            updateTextMetrics()
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
        if self.isVisible != visible {
            self.isVisible = visible
            applyVisibility()
        }
    }

    private func configureLayers() {
        gradientContainer.anchorPoint = .zero
        gradientContainer.position = .zero
        gradientContainer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer?.addSublayer(gradientContainer)

        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.bounds = CGRect(
            x: 0,
            y: 0,
            width: Self.gradientWidthInHostWidths,
            height: 1
        )
        gradient.position = CGPoint(x: 0.5, y: 0.5)
        gradientContainer.addSublayer(gradient)

        textMask.string = "Thinking..."
        textMask.alignmentMode = .left
        textMask.foregroundColor = NSColor.white.cgColor
        textMask.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.mask = textMask
    }

    private func updateTextMetrics() {
        let font = italicSystemFont(size: 13 * scale)
        textMask.font = font
        textMask.fontSize = font.pointSize
        textSize = ("Thinking..." as NSString).size(withAttributes: [.font: font])
    }

    private func configureGradientStops() {
        // 帯（明度バンプ）は原実装と同じ「host 幅」ぶんの広がりにする。勾配は両端被覆のため
        // host 幅の gradientWidthInHostWidths 倍あるので、各 stop の勾配内位置(0..1)を host 幅換算
        // 位置へ写像してから凍結 falloff を評価する。勾配全幅にバンプを張るとシマーのコントラスト
        // が失われる（帯が約 gradientWidthInHostWidths 倍に広がる）ため、この写像でバンプを原寸へ戻す。
        let center = ThinkingAnimationModel.shimmerBandCenter(phase: 0.5)
        let widthInHostWidths = Double(Self.gradientWidthInHostWidths)
        brightnesses = (0..<Self.stopCount).map { index in
            let location = Double(index) / Double(Self.stopCount - 1)
            let hostPosition = 0.5 + (location - 0.5) * widthInHostWidths
            return ThinkingAnimationModel.shimmerBrightness(position: hostPosition, phase: center)
        }
        gradient.locations = (0..<Self.stopCount).map {
            NSNumber(value: Double($0) / Double(Self.stopCount - 1))
        }
        updateGradientColors()
    }

    private func updateGradientColors() {
        gradient.colors = brightnesses.map { brightness in
            color.withAlphaComponent(brightness).cgColor
        }
    }

    private func addShimmerAnimation() {
        // locations は常に [0, 1]。幅広い勾配を正規化座標で並進する。
        // 両端では勾配がホスト全域を覆ったまま帯の中心だけが画面外へ抜けるため、
        // 周期末の右端→左端への瞬間移動はテキスト内に現れない。
        let shimmer = CABasicAnimation(keyPath: "position.x")
        shimmer.fromValue = -ThinkingAnimationModel.shimmerMargin
        shimmer.toValue = 1 + ThinkingAnimationModel.shimmerMargin
        shimmer.duration = ThinkingAnimationModel.shimmerPeriod
        shimmer.repeatCount = .infinity
        shimmer.timingFunction = CAMediaTimingFunction(name: .linear)
        shimmer.isRemovedOnCompletion = false
        gradient.add(shimmer, forKey: Self.shimmerAnimationKey)
    }

    /// 帯の中心を -margin...1+margin へ動かしても、ホスト [0, 1] を常に覆う最小幅。
    private static var gradientWidthInHostWidths: CGFloat {
        CGFloat(2 + 2 * ThinkingAnimationModel.shimmerMargin)
    }

    private func applyVisibility() {
        guard let shimmer = gradient.animation(forKey: Self.shimmerAnimationKey) else { return }
        if isVisible {
            resume(layer: gradient)
        } else {
            pause(layer: gradient)
        }
        // animation を保持していることを明示し、可視性更新で再追加しない。
        _ = shimmer
    }

    private func pause(layer: CALayer) {
        guard layer.speed != 0 else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
    }

    private func resume(layer: CALayer) {
        guard layer.speed == 0 else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    private func italicSystemFont(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        return NSFontManager.shared.convert(system, toHaveTrait: .italicFontMask)
    }
}

#if DEBUG
public extension ThinkingShimmerView {
    /// テスト専用: makeNSView と同じ初期化で下層 NSView を直接構築する。
    static func makeHostViewForTesting(
        color: NSColor,
        scale: CGFloat,
        visible: Bool
    ) -> ThinkingShimmerHostView {
        ThinkingShimmerHostView(color: color, scale: scale, visible: visible)
    }
}

public extension ThinkingShimmerHostView {
    var shimmerAnimationDurationForTesting: CFTimeInterval? {
        (gradient.animation(forKey: Self.shimmerAnimationKey) as? CABasicAnimation)?.duration
    }

    var shimmerAnimationRepeatsForeverForTesting: Bool {
        (gradient.animation(forKey: Self.shimmerAnimationKey) as? CABasicAnimation)?.repeatCount == .infinity
    }

    var isShimmerAnimatingForTesting: Bool {
        isVisible && gradient.speed != 0 && gradient.animation(forKey: Self.shimmerAnimationKey) != nil
    }

    var shimmerBandBrightnessesForTesting: [Double] { brightnesses }

    var shimmerGradientLocationsForTesting: [Double] {
        (gradient.locations ?? []).map(\.doubleValue)
    }

    var shimmerBandCenterPositionsForTesting: (from: Double, to: Double)? {
        guard let shimmer = gradient.animation(forKey: Self.shimmerAnimationKey) as? CABasicAnimation,
              let from = shimmer.fromValue as? Double,
              let to = shimmer.toValue as? Double else {
            return nil
        }
        return (from, to)
    }

    var shimmerGradientWidthInHostWidthsForTesting: Double {
        Double(Self.gradientWidthInHostWidths)
    }

    func setVisibleForTesting(_ visible: Bool) {
        update(color: color, scale: scale, visible: visible)
    }

    func updateColorForTesting(_ color: NSColor) {
        update(color: color, scale: scale, visible: isVisible)
    }

    var appliedTextColorForTesting: NSColor? { color }
}
#endif
