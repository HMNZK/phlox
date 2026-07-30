import AgentDomain
import QuartzCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 点描の思考インジケータ（thinking-orbs の移植）。
/// 描画は下層のプラットフォームビュー内で display link から行い、
/// アニメーション中に SwiftUI の表示木を再評価しない（ADR 0117 と同じ方針）。
/// `accessibilityReduceMotion` 有効時は静止フレームを 1 枚だけ描く。
public struct ThinkingOrbView: View {
    private let state: AgentActivityState
    private let size: OrbSizePreset
    private let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public init(state: AgentActivityState, size: OrbSizePreset = .inline, isVisible: Bool = true) {
        self.state = state
        self.size = size
        self.isVisible = isVisible
    }

    public var body: some View {
        ThinkingOrbCanvas(
            state: state,
            size: size,
            isAnimating: isVisible && !reduceMotion,
            dark: colorScheme == .dark
        )
        .frame(width: CGFloat(size.rawValue), height: CGFloat(size.rawValue))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.orbLabel)
    }
}

#if canImport(AppKit)
struct ThinkingOrbCanvas: NSViewRepresentable {
    let state: AgentActivityState
    let size: OrbSizePreset
    let isAnimating: Bool
    let dark: Bool

    func makeNSView(context: Context) -> ThinkingOrbHostView {
        ThinkingOrbHostView(state: state, size: size, isAnimating: isAnimating, dark: dark)
    }

    func updateNSView(_ nsView: ThinkingOrbHostView, context: Context) {
        nsView.update(state: state, size: size, isAnimating: isAnimating, dark: dark)
    }

    static func dismantleNSView(_ nsView: ThinkingOrbHostView, coordinator: ()) {
        nsView.stopDisplayLink()
    }
}
#elseif canImport(UIKit)
struct ThinkingOrbCanvas: UIViewRepresentable {
    let state: AgentActivityState
    let size: OrbSizePreset
    let isAnimating: Bool
    let dark: Bool

    func makeUIView(context: Context) -> ThinkingOrbHostView {
        ThinkingOrbHostView(state: state, size: size, isAnimating: isAnimating, dark: dark)
    }

    func updateUIView(_ uiView: ThinkingOrbHostView, context: Context) {
        uiView.update(state: state, size: size, isAnimating: isAnimating, dark: dark)
    }

    static func dismantleUIView(_ uiView: ThinkingOrbHostView, coordinator: ()) {
        uiView.stopDisplayLink()
    }
}
#endif

#if canImport(AppKit)
public typealias ThinkingOrbPlatformView = NSView
#elseif canImport(UIKit)
public typealias ThinkingOrbPlatformView = UIView
#endif

/// display link で 1 フレームずつ点群を描くビュー。SwiftUI の状態には触れない。
public final class ThinkingOrbHostView: ThinkingOrbPlatformView {
    /// ReduceMotion 時に描く静止フレームの時刻（原実装と同じ代表フレーム）。
    static let staticFrameTime: Double = 0.6

    private var state: AgentActivityState
    private var sizePreset: OrbSizePreset
    private var isAnimating: Bool
    private var dark: Bool
    private var preset: OrbPreset
    private var displayLink: CADisplayLink?

    init(state: AgentActivityState, size: OrbSizePreset, isAnimating: Bool, dark: Bool) {
        self.state = state
        self.sizePreset = size
        self.isAnimating = isAnimating
        self.dark = dark
        self.preset = OrbPresets.resolve(state: state, size: size)
        super.init(frame: CGRect(x: 0, y: 0, width: CGFloat(size.rawValue), height: CGFloat(size.rawValue)))
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: AgentActivityState, size: OrbSizePreset, isAnimating: Bool, dark: Bool) {
        var needsRedraw = false
        if self.state != state || self.sizePreset != size {
            self.state = state
            self.sizePreset = size
            self.preset = OrbPresets.resolve(state: state, size: size)
            needsRedraw = true
        }
        if self.dark != dark {
            self.dark = dark
            needsRedraw = true
        }
        if self.isAnimating != isAnimating {
            self.isAnimating = isAnimating
            syncDisplayLink()
            needsRedraw = true
        }
        if needsRedraw { setNeedsRedraw() }
    }

    /// 描画時刻。全 orb が同じ時計を共有し、位相が揃う。
    func frameTime(now: CFTimeInterval) -> Double {
        isAnimating ? now * preset.speed : Self.staticFrameTime
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func syncDisplayLink() {
        if isAnimating {
            guard displayLink == nil else { return }
            let link = makeDisplayLink()
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            stopDisplayLink()
        }
    }

    @objc private func tick() {
        setNeedsRedraw()
    }

    private func render(in context: CGContext, now: CFTimeInterval) {
        let side = Double(sizePreset.rawValue)
        let dots = OrbModeRenderer.dots(
            mode: preset.mode,
            size: side,
            time: frameTime(now: now),
            options: preset.options
        )
        OrbPainter.paint(dots, into: context, dark: dark, minRadius: preset.options.rMin ?? 0.3)
    }

    #if canImport(AppKit)
    public override var isFlipped: Bool { true }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(sizePreset.rawValue), height: CGFloat(sizePreset.rawValue))
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        syncDisplayLink()
    }

    private func makeDisplayLink() -> CADisplayLink {
        displayLink(target: self, selector: #selector(tick))
    }

    private func setNeedsRedraw() {
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        render(in: context, now: CACurrentMediaTime())
    }
    #elseif canImport(UIKit)
    public override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(sizePreset.rawValue), height: CGFloat(sizePreset.rawValue))
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        syncDisplayLink()
    }

    private func makeDisplayLink() -> CADisplayLink {
        CADisplayLink(target: self, selector: #selector(tick))
    }

    private func setNeedsRedraw() {
        setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        render(in: context, now: CACurrentMediaTime())
    }
    #endif
}

#if DEBUG
public extension ThinkingOrbHostView {
    /// テスト専用: makeNSView / makeUIView と同じ初期化で下層ビューを構築する。
    static func makeForTesting(
        state: AgentActivityState,
        size: OrbSizePreset,
        isAnimating: Bool,
        dark: Bool
    ) -> ThinkingOrbHostView {
        ThinkingOrbHostView(state: state, size: size, isAnimating: isAnimating, dark: dark)
    }

    var isDisplayLinkRunningForTesting: Bool { displayLink != nil }

    var resolvedPresetForTesting: OrbPreset { preset }

    func setAnimatingForTesting(_ animating: Bool) {
        update(state: state, size: sizePreset, isAnimating: animating, dark: dark)
    }

    func frameTimeForTesting(now: CFTimeInterval) -> Double { frameTime(now: now) }
}
#endif
