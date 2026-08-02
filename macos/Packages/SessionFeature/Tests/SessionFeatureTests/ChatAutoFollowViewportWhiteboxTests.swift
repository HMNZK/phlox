import AppKit
import Testing
@testable import SessionFeature

@MainActor
private final class ViewportVisibilityRecorder {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}

@MainActor
private func makeBottomScrollView() -> (NSScrollView, NSView) {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1_000))
    scrollView.documentView = documentView
    scrollView.layoutSubtreeIfNeeded()
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 600))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    return (scrollView, documentView)
}

@MainActor
private func makeBridge(_ recorder: ViewportVisibilityRecorder) -> ChatAutoFollowScrollEventBridge {
    ChatAutoFollowScrollEventBridge(
        controller: ChatAutoFollowController(),
        onViewportVisibilityChanged: recorder.record,
        onViewportCenterChanged: { _ in }
    )
}

@MainActor
@Test
func viewportBridge_doesNotRecalculateScrubberCenterForFrameOnlyChanges() {
    let recorder = ViewportVisibilityRecorder()
    var centers: [CGFloat] = []
    let bridge = ChatAutoFollowScrollEventBridge(
        controller: ChatAutoFollowController(),
        onViewportVisibilityChanged: recorder.record,
        onViewportCenterChanged: { centers.append($0) }
    )
    let (scrollView, documentView) = makeBottomScrollView()
    bridge.attach(to: scrollView)
    defer { bridge.detach() }

    documentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2_000)

    #expect(recorder.values == [true, false])
    #expect(centers.count == 1)
}

@MainActor
@Test
func viewportBridge_tracksDocumentViewReplacementAndStopsAfterDetach() {
    let recorder = ViewportVisibilityRecorder()
    let bridge = makeBridge(recorder)
    let (scrollView, oldDocumentView) = makeBottomScrollView()
    bridge.attach(to: scrollView)
    scrollView.contentView.postsBoundsChangedNotifications = false
    scrollView.contentView.postsFrameChangedNotifications = false

    let replacementDocumentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1_000))
    scrollView.documentView = replacementDocumentView
    replacementDocumentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2_000)

    #expect(recorder.values == [true, false])

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1_600))
    oldDocumentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2_000)

    #expect(recorder.values == [true, false])

    replacementDocumentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2_001)
    #expect(recorder.values == [true, false, true])

    bridge.detach()
    replacementDocumentView.frame = NSRect(x: 0, y: 0, width: 400, height: 3_000)

    #expect(recorder.values == [true, false, true])
}
