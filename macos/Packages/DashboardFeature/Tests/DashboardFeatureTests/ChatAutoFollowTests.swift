import AppKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@MainActor
@Suite("chat auto-follow white box")
struct ChatAutoFollowTests {

    @Test
    func geometryTreatsShortContentAsAtBottom() {
        let scrollView = makeScrollView(viewportHeight: 200, documentHeight: 120, visibleMinY: 0)

        #expect(ChatAutoFollowGeometry.isAtBottom(scrollView))
    }

    @Test
    func geometryUsesBottomThresholdBoundary() {
        let justOutside = makeScrollView(viewportHeight: 100, documentHeight: 300, visibleMinY: 119)
        let exactlyInside = makeScrollView(viewportHeight: 100, documentHeight: 300, visibleMinY: 120)

        #expect(!ChatAutoFollowGeometry.isAtBottom(justOutside))
        #expect(ChatAutoFollowGeometry.isAtBottom(exactlyInside))
    }

    @Test
    func adapterTranslatesLiveScrollNotificationsForAttachedScrollViewOnly() {
        let controller = ChatAutoFollowController()
        let observed = makeScrollView(viewportHeight: 100, documentHeight: 300, visibleMinY: 200)
        let other = makeScrollView(viewportHeight: 100, documentHeight: 300, visibleMinY: 0)
        let bridge = ChatAutoFollowScrollEventBridge(controller: controller)
        bridge.attach(to: observed)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: other)
        #expect(controller.isFollowing)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: observed)
        #expect(!controller.isFollowing)

        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: observed)
        #expect(controller.isFollowing)

        bridge.detach()
    }

    @Test
    func adapterTranslatesBoundsChangeToDetachedResumeOnly() {
        let controller = ChatAutoFollowController()
        let scrollView = makeScrollView(viewportHeight: 100, documentHeight: 300, visibleMinY: 0)
        let bridge = ChatAutoFollowScrollEventBridge(controller: controller)
        bridge.attach(to: scrollView)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        #expect(!controller.isFollowing)

        scrollView.contentView.bounds.origin.y = 200
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        #expect(controller.isFollowing)

        bridge.detach()
    }

    @Test
    func attachNilDetachesExistingObservers() {
        let controller = ChatAutoFollowController()
        let scrollView = makeScrollView(viewportHeight: 100, documentHeight: 300, visibleMinY: 0)
        let bridge = ChatAutoFollowScrollEventBridge(controller: controller)
        bridge.attach(to: scrollView)

        bridge.attach(to: nil)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        #expect(controller.isFollowing)

        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        #expect(controller.isFollowing)
    }

    private func makeScrollView(
        viewportHeight: CGFloat,
        documentHeight: CGFloat,
        visibleMinY: CGFloat
    ) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: viewportHeight))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: documentHeight))
        scrollView.documentView = documentView
        scrollView.contentView.frame = scrollView.bounds
        scrollView.contentView.bounds = NSRect(x: 0, y: visibleMinY, width: 100, height: viewportHeight)
        return scrollView
    }
}
