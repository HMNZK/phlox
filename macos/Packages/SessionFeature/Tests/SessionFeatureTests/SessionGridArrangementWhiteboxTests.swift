import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

@Suite("SessionGridArrangement invariants")
struct SessionGridArrangementWhiteboxTests {
    private func sid(_ n: Int) -> SessionID {
        SessionID(
            rawValue: UUID(
                uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))"
            )!
        )
    }

    private func expectValid(
        _ arrangement: SessionGridArrangement,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var occupiedCells = Set<Int>()

        for region in arrangement.placements.values {
            let anchorRow = region.anchor / arrangement.size
            let anchorColumn = region.anchor % arrangement.size

            #expect(region.anchor >= 0, sourceLocation: sourceLocation)
            #expect(region.rowSpan >= 1, sourceLocation: sourceLocation)
            #expect(region.colSpan >= 1, sourceLocation: sourceLocation)
            #expect(anchorRow + region.rowSpan <= arrangement.size, sourceLocation: sourceLocation)
            #expect(anchorColumn + region.colSpan <= arrangement.size, sourceLocation: sourceLocation)

            for row in anchorRow..<(anchorRow + region.rowSpan) {
                for column in anchorColumn..<(anchorColumn + region.colSpan) {
                    #expect(
                        occupiedCells.insert(row * arrangement.size + column).inserted,
                        sourceLocation: sourceLocation
                    )
                }
            }
        }
    }

    @Test func composedOperationsKeepRegionsInBoundsAndDisjoint() throws {
        let initial = SessionGridArrangement(size: 3)
            .reconciled(with: [sid(0), sid(1), sid(2), sid(3)])
        let mergedDown = try #require(initial.mergeDown(sid(0)))
        let mergedRight = try #require(mergedDown.mergeRight(sid(0)))
        let reconciled = mergedRight.reconciled(with: [sid(0), sid(1), sid(2), sid(4)])
        let swapped = try #require(reconciled.swap(sid(0), sid(4)))
        let unmerged = try #require(swapped.unmerge(sid(4)))

        for arrangement in [initial, mergedDown, mergedRight, reconciled, swapped, unmerged] {
            expectValid(arrangement)
        }
    }

    @Test func mergeRelocationUsesOccupantAnchorThenCellIndexOrder() throws {
        let base = SessionGridArrangement(size: 3)
            .reconciled(with: [sid(0), sid(1), sid(2)])
        let moved = try #require(base.move(sid(2), toCell: 4))
        let tall = try #require(moved.mergeDown(sid(0)))

        let first = try #require(tall.mergeRight(sid(0)))
        let second = try #require(tall.mergeRight(sid(0)))

        #expect(first == second)
        #expect(first.placements[sid(1)]?.anchor == 2)
        #expect(first.placements[sid(2)]?.anchor == 5)
        expectValid(first)
    }

    @Test func rejectedBoundaryOperationsLeaveNoInvalidResult() throws {
        let arrangement = SessionGridArrangement(size: 1).reconciled(with: [sid(0)])

        #expect(arrangement.move(sid(0), toCell: -1) == nil)
        #expect(arrangement.move(sid(0), toCell: 1) == nil)
        #expect(arrangement.mergeRight(sid(0)) == nil)
        #expect(arrangement.mergeDown(sid(0)) == nil)
        expectValid(arrangement)
    }
}
