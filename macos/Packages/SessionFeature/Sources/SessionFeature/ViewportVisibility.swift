import AppKit
import SwiftUI

/// View 自身がスクロール領域へ少しでも現れているかを報告する。
/// 自動スクロールの「最下部付近」判定とは独立した、描画更新の休止専用シグナル。
public extension View {
    func onViewportVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(ViewportVisibilityObserver(action: action))
    }
}

enum ViewportVisibilityGeometry {
    static func isVisible(viewFrame: CGRect, viewport: CGRect) -> Bool {
        !viewFrame.isEmpty && viewFrame.intersects(viewport)
    }
}

@MainActor
final class ViewportVisibilityBridge: NSObject {
    private var action: (Bool) -> Void
    private weak var probe: NSView?
    private weak var scrollView: NSScrollView?
    private weak var clipView: NSClipView?
    private var lastValue: Bool?

    init(action: @escaping (Bool) -> Void) {
        self.action = action
    }

    func update(action: @escaping (Bool) -> Void) {
        self.action = action
    }

    func attach(probe: NSView) {
        detach()
        self.probe = probe
        scrollView = probe.enclosingScrollView
        clipView = scrollView?.contentView

        probe.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(geometryDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: probe
        )
        if let clipView {
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(geometryDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(geometryDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: clipView
            )
        }
        publishVisibility()
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        probe = nil
        scrollView = nil
        clipView = nil
        lastValue = nil
    }

    @objc private func geometryDidChange(_ notification: Notification) {
        publishVisibility()
    }

    func publishVisibility() {
        guard let probe else { return }
        let isVisible: Bool
        if probe.window == nil || probe.isHiddenOrHasHiddenAncestor {
            isVisible = false
        } else if let scrollView, let documentView = scrollView.documentView {
            let frame = probe.convert(probe.bounds, to: documentView)
            isVisible = ViewportVisibilityGeometry.isVisible(
                viewFrame: frame,
                viewport: scrollView.documentVisibleRect
            )
        } else {
            isVisible = true
        }
        guard lastValue != isVisible else { return }
        lastValue = isVisible
        action(isVisible)
    }
}

private struct ViewportVisibilityObserver: NSViewRepresentable {
    let action: (Bool) -> Void

    func makeCoordinator() -> ViewportVisibilityBridge {
        ViewportVisibilityBridge(action: action)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onHierarchyChange = { [weak bridge = context.coordinator] view in
            bridge?.attach(probe: view)
        }
        view.resolveOnNextRunLoop()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.update(action: action)
        nsView.resolveOnNextRunLoop()
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ViewportVisibilityBridge) {
        coordinator.detach()
    }

    final class ProbeView: NSView {
        var onHierarchyChange: ((NSView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveOnNextRunLoop()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolveOnNextRunLoop()
        }

        func resolveOnNextRunLoop() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onHierarchyChange?(self)
            }
        }
    }
}
