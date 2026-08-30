import CoreGraphics
import Testing
@testable import SessionFeature

@Test
func thinkingIndicatorRemainsActiveWhenVisibleAwayFromTranscriptBottom() {
    let viewport = CGRect(x: 0, y: 200, width: 600, height: 500)
    let visibleIndicator = CGRect(x: 20, y: 240, width: 300, height: 60)

    #expect(ViewportVisibilityGeometry.isVisible(
        viewFrame: visibleIndicator,
        viewport: viewport
    ))
}

@Test
func thinkingIndicatorStopsOnlyAfterLeavingViewportCompletely() {
    let viewport = CGRect(x: 0, y: 200, width: 600, height: 500)

    #expect(ViewportVisibilityGeometry.isVisible(
        viewFrame: CGRect(x: 20, y: 190, width: 300, height: 20),
        viewport: viewport
    ))
    #expect(!ViewportVisibilityGeometry.isVisible(
        viewFrame: CGRect(x: 20, y: 179, width: 300, height: 20),
        viewport: viewport
    ))
}
