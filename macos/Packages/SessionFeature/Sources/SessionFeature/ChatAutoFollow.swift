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

    /// 読み戻しで追従を外した状態（スクロール中は含めない）。「↓ 最新へ」を出す条件（04 B7）。
    var isDetached: Bool {
        state == .detached
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

    /// セッションを切り替えた（別セッションを開いた）。追従状態を初期状態へ戻す。
    ///
    /// 公開面は PM が凍結した契約面（task-3 の入出力契約）。振る舞いの実装は task-3 が行う。
    /// 契約の正本: Tests/SessionFeatureTests/ChatOpenAtBottomTests.swift
    func sessionDidChange() {
        state = .following
    }
}

/// 最下部へ寄せるかを、スクロールのきっかけと追従状態だけから決める。
/// 読み戻し中は新着イベント自体は届くが、いずれのきっかけでも引き戻さない。
enum ChatBottomScrollTrigger {
    case appear
    case transcript
    case status
}

enum ChatBottomScrollPolicy {
    static func shouldScrollToBottom(trigger: ChatBottomScrollTrigger, isFollowing: Bool) -> Bool {
        guard isFollowing else { return false }
        switch trigger {
        case .appear, .transcript, .status:
            return true
        }
    }

    static func shouldPerformDeferredScroll(
        generation: Int,
        currentGeneration: Int,
        isFollowing: Bool
    ) -> Bool {
        generation == currentGeneration && isFollowing
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
    /// ビューポート中央の Y（documentView 座標）。スクラバーの現在位置算出に使う。
    private var onViewportCenterChanged: (CGFloat) -> Void
    /// 追従を外しているか。スクロールの通知ごとに今の値を渡す（受け手は変化したときだけ書く）。
    private var onDetachedChanged: (Bool) -> Void
    private var onScrollPastTop: () -> Void
    private var onScrollPastBottom: () -> Void
    private var onScrollAwayFromEdge: () -> Void
    private var onScrollReleased: () -> Void
    /// 窓が新しい側を外しているか（ADR 0229）。外している間は下端で引けて、最下部でも追従に戻らない。
    private var hasNewerHidden: Bool
    private var scrollMonitor: Any?
    /// このジェスチャーで読み込みを要求した端。
    private var armedEdge: VerticalEdge?
    private var hasGestureBegan = false
    private var topPullDistance: CGFloat = 0
    private var bottomPullDistance: CGFloat = 0
    private var discreteScrollEndTask: Task<Void, Never>?
    private static let historyPullThreshold: CGFloat = 60
    private weak var scrollView: NSScrollView?
    private weak var observedClipView: NSClipView?

    init(
        controller: ChatAutoFollowController,
        onViewportCenterChanged: @escaping (CGFloat) -> Void = { _ in },
        onDetachedChanged: @escaping (Bool) -> Void = { _ in },
        onScrollPastTop: @escaping () -> Void = {},
        onScrollPastBottom: @escaping () -> Void = {},
        onScrollAwayFromEdge: @escaping () -> Void = {},
        onScrollReleased: @escaping () -> Void = {},
        hasNewerHidden: Bool = false
    ) {
        self.controller = controller
        self.onViewportCenterChanged = onViewportCenterChanged
        self.onDetachedChanged = onDetachedChanged
        self.onScrollPastTop = onScrollPastTop
        self.onScrollPastBottom = onScrollPastBottom
        self.onScrollAwayFromEdge = onScrollAwayFromEdge
        self.onScrollReleased = onScrollReleased
        self.hasNewerHidden = hasNewerHidden
    }

    func update(
        controller: ChatAutoFollowController,
        onViewportCenterChanged: @escaping (CGFloat) -> Void,
        onDetachedChanged: @escaping (Bool) -> Void = { _ in },
        onScrollPastTop: @escaping () -> Void = {},
        onScrollPastBottom: @escaping () -> Void = {},
        onScrollAwayFromEdge: @escaping () -> Void = {},
        onScrollReleased: @escaping () -> Void = {},
        hasNewerHidden: Bool = false
    ) {
        self.controller = controller
        self.onViewportCenterChanged = onViewportCenterChanged
        self.onDetachedChanged = onDetachedChanged
        self.onScrollPastTop = onScrollPastTop
        self.onScrollPastBottom = onScrollPastBottom
        self.onScrollAwayFromEdge = onScrollAwayFromEdge
        self.onScrollReleased = onScrollReleased
        self.hasNewerHidden = hasNewerHidden
    }

    private func reportDetachedIfChanged() {
        onDetachedChanged(controller.isDetached)
    }

    func attach(to scrollView: NSScrollView?) {
        guard let scrollView else {
            detach()
            return
        }
        guard self.scrollView !== scrollView else {
            return
        }

        detach()

        self.scrollView = scrollView
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event)
            return event
        }
        observedClipView = scrollView.contentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

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
        center.addObserver(
            self,
            selector: #selector(frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        onViewportCenterChanged(scrollView.documentVisibleRect.midY)
    }

    func detach() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        resetHistoryPull()
        hasGestureBegan = false
        let center = NotificationCenter.default
        if let scrollView {
            center.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
            center.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
        if let observedClipView {
            center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
            center.removeObserver(self, name: NSView.frameDidChangeNotification, object: observedClipView)
        }
        scrollView = nil
        observedClipView = nil
    }

    func handleScrollWheel(_ event: NSEvent) {
        guard let scrollView, let window = scrollView.window, event.window === window,
              let contentView = window.contentView else { return }
        if event.phase.contains(.cancelled) {
            resetHistoryPull()
            hasGestureBegan = false
            onScrollAwayFromEdge()
            return
        }
        if event.phase.contains(.ended) {
            finishHistoryPull()
            return
        }
        guard event.momentumPhase.isEmpty else { return }
        let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        let hit = contentView.hitTest(point)
        guard (hit as? NSScrollView ?? hit?.enclosingScrollView) === scrollView else { return }
        if event.phase.contains(.began) {
            if armedEdge != nil { onScrollAwayFromEdge() }
            resetHistoryPull()
            hasGestureBegan = true
        }
        guard event.phase.isEmpty || hasGestureBegan else { return }
        guard let edges = pullableEdges(scrollView), !edges.isEmpty,
              armedEdge.map(edges.contains) ?? true else {
            resetHistoryPull()
            onScrollAwayFromEdge()
            return
        }
        let unit = event.hasPreciseScrollingDeltas ? 1 : scrollView.verticalLineScroll
        let delta = event.scrollingDeltaY * unit
        topPullDistance = edges.contains(.top) ? max(0, topPullDistance + delta) : 0
        bottomPullDistance = edges.contains(.bottom) ? max(0, bottomPullDistance - delta) : 0
        if armedEdge == nil, topPullDistance >= Self.historyPullThreshold {
            armedEdge = .top
            onScrollPastTop()
        } else if armedEdge == nil, bottomPullDistance >= Self.historyPullThreshold {
            armedEdge = .bottom
            onScrollPastBottom()
        }
        if event.phase.isEmpty {
            discreteScrollEndTask?.cancel()
            discreteScrollEndTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.finishHistoryPull()
            }
        }
    }

    /// いまビューポートが接している、引いて読み込める端。下端は新しい側を外しているときだけ。
    private func pullableEdges(_ scrollView: NSScrollView) -> Set<VerticalEdge>? {
        guard let document = scrollView.documentView else { return nil }
        let visible = scrollView.documentVisibleRect
        var edges: Set<VerticalEdge> = []
        if visible.minY <= document.frame.minY + 1 { edges.insert(.top) }
        if hasNewerHidden, visible.maxY >= document.frame.maxY - 1 { edges.insert(.bottom) }
        return edges
    }

    private func isFollowableBottom(_ scrollView: NSScrollView) -> Bool {
        !hasNewerHidden && ChatAutoFollowGeometry.isAtBottom(scrollView)
    }

    private func resetHistoryPull() {
        discreteScrollEndTask?.cancel()
        discreteScrollEndTask = nil
        topPullDistance = 0
        bottomPullDistance = 0
        armedEdge = nil
    }

    private func finishHistoryPull() {
        let shouldLoad = armedEdge != nil
        resetHistoryPull()
        hasGestureBegan = false
        if shouldLoad { onScrollReleased() }
    }

    @objc private func willStartLiveScroll(_ notification: Notification) {
        controller.userScrollBegan()
    }

    @objc private func didEndLiveScroll(_ notification: Notification) {
        guard let scrollView else { return }
        finishHistoryPull()
        let isAtBottom = isFollowableBottom(scrollView)
        controller.userScrollEnded(isAtBottom: isAtBottom && !controller.isDetached)
        reportDetachedIfChanged()
        onViewportCenterChanged(scrollView.documentVisibleRect.midY)
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        guard let scrollView else { return }
        if let edges = pullableEdges(scrollView), !(armedEdge.map(edges.contains) ?? !edges.isEmpty) {
            resetHistoryPull()
            onScrollAwayFromEdge()
        }
        let isAtBottom = isFollowableBottom(scrollView)
        if armedEdge == nil {
            controller.scrollPositionChanged(isAtBottom: isAtBottom)
        }
        reportDetachedIfChanged()
        onViewportCenterChanged(scrollView.documentVisibleRect.midY)
    }

    @objc private func frameDidChange(_ notification: Notification) {
        guard let scrollView else { return }
        onViewportCenterChanged(scrollView.documentVisibleRect.midY)
    }

}

struct ChatAutoFollowScrollObserver: NSViewRepresentable {
    let controller: ChatAutoFollowController
    var onViewportCenterChanged: (CGFloat) -> Void = { _ in }
    var onDetachedChanged: (Bool) -> Void = { _ in }
    var onScrollPastTop: () -> Void = {}
    var onScrollPastBottom: () -> Void = {}
    var onScrollAwayFromEdge: () -> Void = {}
    var onScrollReleased: () -> Void = {}
    var hasNewerHidden = false

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            onViewportCenterChanged: onViewportCenterChanged,
            onDetachedChanged: onDetachedChanged,
            onScrollPastTop: onScrollPastTop,
            onScrollPastBottom: onScrollPastBottom,
            onScrollAwayFromEdge: onScrollAwayFromEdge,
            onScrollReleased: onScrollReleased,
            hasNewerHidden: hasNewerHidden
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
            onViewportCenterChanged: onViewportCenterChanged,
            onDetachedChanged: onDetachedChanged,
            onScrollPastTop: onScrollPastTop,
            onScrollPastBottom: onScrollPastBottom,
            onScrollAwayFromEdge: onScrollAwayFromEdge,
            onScrollReleased: onScrollReleased,
            hasNewerHidden: hasNewerHidden
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
            onViewportCenterChanged: @escaping (CGFloat) -> Void,
            onDetachedChanged: @escaping (Bool) -> Void,
            onScrollPastTop: @escaping () -> Void,
            onScrollPastBottom: @escaping () -> Void,
            onScrollAwayFromEdge: @escaping () -> Void,
            onScrollReleased: @escaping () -> Void,
            hasNewerHidden: Bool
        ) {
            bridge = ChatAutoFollowScrollEventBridge(
                controller: controller,
                onViewportCenterChanged: onViewportCenterChanged,
                onDetachedChanged: onDetachedChanged,
                onScrollPastTop: onScrollPastTop,
                onScrollPastBottom: onScrollPastBottom,
                onScrollAwayFromEdge: onScrollAwayFromEdge,
                onScrollReleased: onScrollReleased,
                hasNewerHidden: hasNewerHidden
            )
        }

        func update(
            controller: ChatAutoFollowController,
            onViewportCenterChanged: @escaping (CGFloat) -> Void,
            onDetachedChanged: @escaping (Bool) -> Void,
            onScrollPastTop: @escaping () -> Void,
            onScrollPastBottom: @escaping () -> Void,
            onScrollAwayFromEdge: @escaping () -> Void,
            onScrollReleased: @escaping () -> Void,
            hasNewerHidden: Bool
        ) {
            bridge.update(
                controller: controller,
                onViewportCenterChanged: onViewportCenterChanged,
                onDetachedChanged: onDetachedChanged,
                onScrollPastTop: onScrollPastTop,
                onScrollPastBottom: onScrollPastBottom,
                onScrollAwayFromEdge: onScrollAwayFromEdge,
                onScrollReleased: onScrollReleased,
                hasNewerHidden: hasNewerHidden
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
