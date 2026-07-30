import QuartzCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// イタリック体の短いラベルに、明度帯が左→右へ流れるシマーをかけて表示する（macOS / iOS 共有）。
/// 帯の形状・周期は `ShimmerBandModel`（ADR 0067 の凍結仕様）から算出する。
///
/// 駆動方式はプラットフォームで分ける:
/// - macOS: Core Animation（`CATextLayer` マスク + `CAGradientLayer` の並進）。SwiftUI の表示木を
///   毎フレーム再評価しない（ADR 0117 が実測した AttributeGraph / アクセシビリティ木の毎フレーム
///   再構築＝グリッドでの CPU 暴走を避けるため）。
/// - iOS: `TimelineView(.animation)` + `LinearGradient`。Dynamic Type（`Font` 指定）をそのまま活かす。
///   1 画面に 1 個しか出ないため macOS の病理は問題にならない。
///
/// `accessibilityReduceMotion` 有効時はどちらも静止テキストを描く。
public struct ShimmerTextView: View {
    private let text: String
    private let font: Font
    private let pointSize: CGFloat
    private let color: Color
    private let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - text: 表示文字列（イタリックは本ビューが付ける）。
    ///   - font: SwiftUI 経路（iOS / 静止時）で使うフォント。イタリック指定は不要。
    ///   - pointSize: Core Animation 経路（macOS）で `CATextLayer` に渡す実寸。`font` と同じ大きさを渡す。
    ///   - color: 帯の基準色。明度で不透明度を変調する。
    ///   - isVisible: false の間はアニメーションを止める（オフスクリーンで CPU/GPU を焼かない）。
    public init(
        text: String,
        font: Font,
        pointSize: CGFloat,
        color: Color,
        isVisible: Bool = true
    ) {
        self.text = text
        self.font = font
        self.pointSize = pointSize
        self.color = color
        self.isVisible = isVisible
    }

    public var body: some View {
        Group {
            if reduceMotion {
                staticText
            } else {
                animatedText
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var staticText: some View {
        Text(text)
            .font(font.italic())
            .foregroundStyle(color)
    }

    #if canImport(AppKit)
    private var animatedText: some View {
        ShimmerTextCanvas(
            text: text,
            pointSize: pointSize,
            color: color,
            isVisible: isVisible
        )
        .fixedSize()
    }
    #else
    private var animatedText: some View {
        TimelineView(ShimmerTimelineSchedule(isVisible: isVisible)) { context in
            Text(text)
                .font(font.italic())
                .foregroundStyle(
                    LinearGradient(
                        stops: Self.gradientStops(date: context.date, color: color),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    /// 帯中心を画面外余白まで逃がしたうえで、21 stop の明度を凍結 falloff から作る。
    static func gradientStops(date: Date, color: Color) -> [Gradient.Stop] {
        let center = ShimmerBandModel.bandCenter(phase: ShimmerBandModel.phase(date: date))
        return (0...20).map { index in
            let position = Double(index) / 20
            let brightness = ShimmerBandModel.brightness(position: position, phase: center)
            return Gradient.Stop(color: color.opacity(brightness), location: CGFloat(position))
        }
    }
    #endif
}

#if !canImport(AppKit)
/// 非表示時はエントリ列を空にして更新停止を保証する（`AnimationTimelineSchedule(paused:)` は
/// 初期描画用のエントリを返すことがあるため）。
private struct ShimmerTimelineSchedule: TimelineSchedule {
    private let isVisible: Bool
    private let animationSchedule: AnimationTimelineSchedule

    init(isVisible: Bool) {
        self.isVisible = isVisible
        self.animationSchedule = AnimationTimelineSchedule(
            minimumInterval: 1.0 / 30.0,
            paused: !isVisible
        )
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(animationEntries: isVisible ? animationSchedule.entries(from: startDate, mode: mode) : nil)
    }

    struct Entries: Sequence, IteratorProtocol {
        private var animationEntries: AnimationTimelineSchedule.Entries?

        fileprivate init(animationEntries: AnimationTimelineSchedule.Entries?) {
            self.animationEntries = animationEntries
        }

        mutating func next() -> Date? {
            animationEntries?.next()
        }
    }
}
#endif

#if canImport(AppKit)
struct ShimmerTextCanvas: NSViewRepresentable {
    let text: String
    let pointSize: CGFloat
    let color: Color
    let isVisible: Bool

    func makeNSView(context: Context) -> ShimmerTextHostView {
        ShimmerTextHostView(
            text: text,
            pointSize: pointSize,
            color: NSColor(color),
            visible: isVisible
        )
    }

    func updateNSView(_ nsView: ShimmerTextHostView, context: Context) {
        // 離散的な入力だけを反映する。ここでアニメを追加し直さないことが重要。
        nsView.update(text: text, pointSize: pointSize, color: NSColor(color), visible: isVisible)
    }
}

/// Core Animation のレイヤーとテキストマスクを保持する AppKit ビュー。
public final class ShimmerTextHostView: NSView {
    private static let shimmerAnimationKey = "phlox.shimmer.text.position"
    private static let stopCount = 21

    /// 1×1 の論理座標をホストの実寸へ拡大する。これによりリサイズ時にも
    /// アニメーションの値を追加し直さず、帯の移動量を正規化座標で保てる。
    private let gradientContainer = CALayer()
    private let gradient = CAGradientLayer()
    private let textMask = CATextLayer()
    private var text: String
    private var pointSize: CGFloat
    private var color: NSColor
    private var isVisible: Bool
    private var textSize: NSSize = .zero
    private var brightnesses: [Double] = []

    init(text: String, pointSize: CGFloat, color: NSColor, visible: Bool) {
        self.text = text
        self.pointSize = pointSize
        self.color = color
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

    func update(text: String, pointSize: CGFloat, color: NSColor, visible: Bool) {
        if !self.color.isEqual(color) {
            self.color = color
            updateGradientColors()
        }
        if self.text != text || self.pointSize != pointSize {
            self.text = text
            self.pointSize = pointSize
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

        textMask.alignmentMode = .left
        textMask.foregroundColor = NSColor.white.cgColor
        textMask.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.mask = textMask
    }

    private func updateTextMetrics() {
        let font = italicSystemFont(size: pointSize)
        textMask.string = text
        textMask.font = font
        textMask.fontSize = font.pointSize
        textSize = (text as NSString).size(withAttributes: [.font: font])
    }

    private func configureGradientStops() {
        // 帯（明度バンプ）は原実装と同じ「host 幅」ぶんの広がりにする。勾配は両端被覆のため
        // host 幅の gradientWidthInHostWidths 倍あるので、各 stop の勾配内位置(0..1)を host 幅換算
        // 位置へ写像してから凍結 falloff を評価する。勾配全幅にバンプを張るとシマーのコントラスト
        // が失われる（帯が約 gradientWidthInHostWidths 倍に広がる）ため、この写像でバンプを原寸へ戻す。
        let center = ShimmerBandModel.bandCenter(phase: 0.5)
        let widthInHostWidths = Double(Self.gradientWidthInHostWidths)
        brightnesses = (0..<Self.stopCount).map { index in
            let location = Double(index) / Double(Self.stopCount - 1)
            let hostPosition = 0.5 + (location - 0.5) * widthInHostWidths
            return ShimmerBandModel.brightness(position: hostPosition, phase: center)
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
        shimmer.fromValue = -ShimmerBandModel.margin
        shimmer.toValue = 1 + ShimmerBandModel.margin
        shimmer.duration = ShimmerBandModel.period
        shimmer.repeatCount = .infinity
        shimmer.timingFunction = CAMediaTimingFunction(name: .linear)
        shimmer.isRemovedOnCompletion = false
        gradient.add(shimmer, forKey: Self.shimmerAnimationKey)
    }

    /// 帯の中心を -margin...1+margin へ動かしても、ホスト [0, 1] を常に覆う最小幅。
    private static var gradientWidthInHostWidths: CGFloat {
        CGFloat(2 + 2 * ShimmerBandModel.margin)
    }

    private func applyVisibility() {
        guard gradient.animation(forKey: Self.shimmerAnimationKey) != nil else { return }
        if isVisible {
            resume(layer: gradient)
        } else {
            pause(layer: gradient)
        }
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
public extension ShimmerTextView {
    /// テスト専用: makeNSView と同じ初期化で下層 NSView を直接構築する。
    static func makeHostViewForTesting(
        text: String,
        pointSize: CGFloat,
        color: NSColor,
        visible: Bool
    ) -> ShimmerTextHostView {
        ShimmerTextHostView(text: text, pointSize: pointSize, color: color, visible: visible)
    }
}

public extension ShimmerTextHostView {
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

    var maskedTextForTesting: String? { textMask.string as? String }

    var maskFontIsItalicForTesting: Bool {
        guard let font = textMask.font as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    var maskFontPointSizeForTesting: CGFloat { textMask.fontSize }

    func setVisibleForTesting(_ visible: Bool) {
        update(text: text, pointSize: pointSize, color: color, visible: visible)
    }

    func updateColorForTesting(_ color: NSColor) {
        update(text: text, pointSize: pointSize, color: color, visible: isVisible)
    }

    func updateTextForTesting(_ text: String) {
        update(text: text, pointSize: pointSize, color: color, visible: isVisible)
    }

    var appliedTextColorForTesting: NSColor? { color }
}
#endif
#endif
