import AppKit
import Testing
@testable import SessionFeature

@MainActor
@Test
func autoFollowBridgeReportsViewportCenterOnAttachAndScroll() {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1_000))
    var centers: [CGFloat] = []
    let bridge = ChatAutoFollowScrollEventBridge(
        controller: ChatAutoFollowController(),
        onViewportCenterChanged: { centers.append($0) }
    )

    bridge.attach(to: scrollView)
    let initialCenter = centers.last
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 300))
    defer { bridge.detach() }

    #expect(centers.last != initialCenter)
    #expect(centers.last == scrollView.documentVisibleRect.midY)
}
