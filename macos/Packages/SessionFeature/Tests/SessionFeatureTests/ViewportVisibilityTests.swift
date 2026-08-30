import AppKit
import Testing
@testable import SessionFeature

@Test func visibilityRequiresActualIntersection() {
    let viewport = CGRect(x: 0, y: 100, width: 300, height: 400)

    #expect(ViewportVisibilityGeometry.isVisible(
        viewFrame: CGRect(x: 0, y: 499, width: 100, height: 20),
        viewport: viewport
    ))
    #expect(!ViewportVisibilityGeometry.isVisible(
        viewFrame: CGRect(x: 0, y: 500, width: 100, height: 20),
        viewport: viewport
    ))
    #expect(!ViewportVisibilityGeometry.isVisible(viewFrame: .zero, viewport: viewport))
}
