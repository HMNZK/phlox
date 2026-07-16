import CoreGraphics
import Testing
@testable import SessionFeature

@Suite("SessionGridCellFrames white-box")
struct SessionGridCellFramesWhiteboxTests {
    private let tolerance: CGFloat = 0.001

    @Test func cellFrames_areRowMajorForRectangularBounds() {
        let frames = sessionGridCellFrames(
            size: 2,
            bounds: CGSize(width: 110, height: 70),
            spacing: 10
        )

        #expect(frames.count == 4)
        #expect(isApproximatelyEqual(frames[0], CGRect(x: 0, y: 0, width: 50, height: 30)))
        #expect(isApproximatelyEqual(frames[1], CGRect(x: 60, y: 0, width: 50, height: 30)))
        #expect(isApproximatelyEqual(frames[2], CGRect(x: 0, y: 40, width: 50, height: 30)))
        #expect(isApproximatelyEqual(frames[3], CGRect(x: 60, y: 40, width: 50, height: 30)))
    }

    @Test func regionRect_spansRowsAndColumnsFromInteriorAnchor() {
        let region = SessionGridArrangement.Region(anchor: 5, rowSpan: 2, colSpan: 2)
        let rect = sessionGridRegionRect(
            region: region,
            size: 4,
            bounds: CGSize(width: 430, height: 230),
            spacing: 10
        )

        #expect(isApproximatelyEqual(rect, CGRect(x: 110, y: 60, width: 210, height: 110)))
    }

    @Test func nonPositiveSize_hasNoCellsAndNoRegion() {
        let bounds = CGSize(width: 100, height: 100)
        let region = SessionGridArrangement.Region(anchor: 0, rowSpan: 1, colSpan: 1)

        #expect(sessionGridCellFrames(size: 0, bounds: bounds, spacing: 8).isEmpty)
        #expect(sessionGridCellFrames(size: -1, bounds: bounds, spacing: 8).isEmpty)
        #expect(sessionGridRegionRect(region: region, size: 0, bounds: bounds, spacing: 8) == .zero)
    }

    private func isApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }
}
