import AppKit
import SwiftUI
import QuartzCore
import IOSurface
import SimulatorBridgeKit

public struct SimulatorScreenView: NSViewRepresentable {
    public let displayInfo: SimulatorDisplayInfo?

    public init(displayInfo: SimulatorDisplayInfo?) { self.displayInfo = displayInfo }

    public func makeNSView(context: Context) -> SimulatorScreenNSView { SimulatorScreenNSView() }
    public func updateNSView(_ view: SimulatorScreenNSView, context: Context) { view.update(displayInfo) }
    public static func dismantleNSView(_ view: SimulatorScreenNSView, coordinator: ()) { view.stop() }
}

public final class SimulatorScreenNSView: NSView {
    private let screen = CALayer()
    private var info: SimulatorDisplayInfo?
    private var lastSeed: UInt32 = 0
    private var displayLink: CADisplayLink?

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        screen.contentsGravity = .resizeAspect
        layer?.addSublayer(screen)
        setAccessibilityElement(true)
        setAccessibilityLabel("iOS シミュレーターの画面（表示のみ）")
    }

    required init?(coder: NSCoder) { nil }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screen.frame = bounds
        CATransaction.commit()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if window != nil {
            let link = displayLink(target: self, selector: #selector(refresh))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    public func update(_ next: SimulatorDisplayInfo?) {
        if let next, let info {
            guard next.connectionGeneration > info.connectionGeneration ||
                    next.isCurrent(udid: info.udid, connectionGeneration: info.connectionGeneration,
                                   minimumDisplayGeneration: info.displayGeneration) else { return }
        }
        info = next
        lastSeed = next.map { IOSurfaceGetSeed($0.surface) } ?? 0
        setContents(next?.surface)
    }

    @objc private func refresh() {
        guard let info else { return }
        let seed = IOSurfaceGetSeed(info.surface)
        guard seed != lastSeed else { return }
        lastSeed = seed
        setContents(info.surface)
    }

    private func setContents(_ surface: IOSurface?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 同じ surface の変更を Core Animation に通知する（試作で確認済み）。
        screen.contents = nil
        screen.contents = surface
        CATransaction.commit()
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        update(nil)
    }
}
