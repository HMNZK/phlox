import AppKit
import SwiftUI

final class ChatAutoFollowController {
    private enum State {
        case following
        case userScrolling
        case detached
    }

    private var state: State = .following

    var isFollowing: Bool {
        state == .following
    }

    func userScrollBegan() {
        state = .userScrolling
    }

    func userScrollEnded(isAtBottom: Bool) {
        state = isAtBottom ? .following : .detached
    }

    func scrollPositionChanged(isAtBottom: Bool) {
        guard state == .detached, isAtBottom else { return }
        state = .following
    }

    func userInitiatedJump() {
        state = .detached
    }

    func contentDidChange() -> Bool {
        isFollowing
    }
}

enum ChatAutoFollowGeometry {
    private static let bottomFollowThreshold: CGFloat = 80

    @MainActor
    static func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }

        let visibleRect = scrollView.documentVisibleRect
        let documentFrame = documentView.frame
        guard documentFrame.height > visibleRect.height else { return true }

        return visibleRect.maxY >= documentFrame.maxY - bottomFollowThreshold
    }
}

@MainActor
final class ChatAutoFollowScrollEventBridge: NSObject {
    private var controller: ChatAutoFollowController
    private var onViewportVisibilityChanged: (Bool) -> Void
    private weak var scrollView: NSScrollView?
    private weak var observedClipView: NSClipView?
    private var lastViewportVisibility: Bool?

    init(
        controller: ChatAutoFollowController,
        onViewportVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.controller = controller
        self.onViewportVisibilityChanged = onViewportVisibilityChanged
    }

    func update(
        controller: ChatAutoFollowController,
        onViewportVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.controller = controller
        self.onViewportVisibilityChanged = onViewportVisibilityChanged
    }

    func attach(to scrollView: NSScrollView?) {
        guard let scrollView else {
            detach()
            return
        }
        guard self.scrollView !== scrollView else { return }

        detach()

        self.scrollView = scrollView
        observedClipView = scrollView.contentView
        scrollView.contentView.postsBoundsChangedNotifications = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(willStartLiveScroll(_:)),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(didEndLiveScroll(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        updateViewportVisibility(isAtBottom: ChatAutoFollowGeometry.isAtBottom(scrollView))
    }

    func detach() {
        let center = NotificationCenter.default
        if let scrollView {
            center.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
            center.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
        if let observedClipView {
            center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        scrollView = nil
        observedClipView = nil
        lastViewportVisibility = nil
    }

    @objc private func willStartLiveScroll(_ notification: Notification) {
        controller.userScrollBegan()
    }

    @objc private func didEndLiveScroll(_ notification: Notification) {
        guard let scrollView else { return }
        let isAtBottom = ChatAutoFollowGeometry.isAtBottom(scrollView)
        controller.userScrollEnded(isAtBottom: isAtBottom)
        updateViewportVisibility(isAtBottom: isAtBottom)
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        guard let scrollView else { return }
        let isAtBottom = ChatAutoFollowGeometry.isAtBottom(scrollView)
        controller.scrollPositionChanged(isAtBottom: isAtBottom)
        updateViewportVisibility(isAtBottom: isAtBottom)
    }

    private func updateViewportVisibility(isAtBottom: Bool) {
        guard lastViewportVisibility != isAtBottom else { return }
        lastViewportVisibility = isAtBottom
        onViewportVisibilityChanged(isAtBottom)
    }
}

struct ChatAutoFollowScrollObserver: NSViewRepresentable {
    let controller: ChatAutoFollowController
    let onViewportVisibilityChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            onViewportVisibilityChanged: onViewportVisibilityChanged
        )
    }

    func makeNSView(context: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = { [weak coordinator = context.coordinator] view in
            coordinator?.resolve(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: ResolverView, context: Context) {
        context.coordinator.update(
            controller: controller,
            onViewportVisibilityChanged: onViewportVisibilityChanged
        )
        nsView.onResolve = { [weak coordinator = context.coordinator] view in
            coordinator?.resolve(from: view)
        }
        nsView.resolveOnNextRunLoop()
    }

    static func dismantleNSView(_ nsView: ResolverView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private let bridge: ChatAutoFollowScrollEventBridge

        init(
            controller: ChatAutoFollowController,
            onViewportVisibilityChanged: @escaping (Bool) -> Void
        ) {
            bridge = ChatAutoFollowScrollEventBridge(
                controller: controller,
                onViewportVisibilityChanged: onViewportVisibilityChanged
            )
        }

        func update(
            controller: ChatAutoFollowController,
            onViewportVisibilityChanged: @escaping (Bool) -> Void
        ) {
            bridge.update(
                controller: controller,
                onViewportVisibilityChanged: onViewportVisibilityChanged
            )
        }

        func resolve(from view: NSView) {
            bridge.attach(to: view.enclosingScrollView)
        }

        func detach() {
            bridge.detach()
        }
    }

    final class ResolverView: NSView {
        var onResolve: ((NSView) -> Void)?

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
                self.onResolve?(self)
            }
        }
    }
}
