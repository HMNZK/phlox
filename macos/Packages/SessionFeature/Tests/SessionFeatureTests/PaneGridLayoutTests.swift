import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

@Suite("PaneGridLayout")
struct PaneGridLayoutTests {
    private func ids(_ count: Int) -> [SessionID] {
        (0..<count).map { SessionID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))!) }
    }

    @Test(arguments: [0, 1, 3, 4, 5, 6, 7, 11])
    func automaticMaintainsMinimumAndReadingOrder(count: Int) {
        let sessions = ids(count)
        let layout = PaneGridLayout.automatic(sessions: sessions, viewport: CGSize(width: 1643, height: 903))
        let tiles = layout.tree.frames(in: layout.canvasSize, spacing: 8).tiles
        #expect(tiles.count == count)
        #expect(tiles.allSatisfy { $0.rect.width >= 540 - 0.001 && $0.rect.height >= 440 - 0.001 })
        #expect(layout.tree.readingOrder(in: layout.canvasSize, spacing: 8) == sessions)
        #expect(layout == PaneGridLayout.automatic(sessions: sessions, viewport: CGSize(width: 1643, height: 903)))
    }

    @Test(arguments: [539.0, 540, 1087.9, 1088, 1635.9, 1636])
    func columnThresholds(width: Double) {
        let layout = PaneGridLayout.automatic(sessions: ids(6), viewport: CGSize(width: width, height: 500))
        let frames = layout.tree.frames(in: layout.canvasSize, spacing: 8).tiles
        let expectedColumns = width < 1088 ? 1 : width < 1636 ? 2 : 3
        #expect(Set(frames.map { round($0.rect.minX * 1000) }).count == expectedColumns)
        #expect(layout.canvasSize.width == CGFloat(max(width, 540)))
        #expect(frames.allSatisfy { $0.rect.width >= 540 - 0.001 && $0.rect.height >= 440 - 0.001 })
    }

    @Test(arguments: [5, 6, 7])
    func finalRowExtendsOnlyMissingColumns(count: Int) throws {
        let sessions = ids(count)
        let layout = PaneGridLayout.automatic(sessions: sessions, viewport: CGSize(width: 1643, height: 903))
        let frames = Dictionary(uniqueKeysWithValues: layout.tree.frames(in: layout.canvasSize, spacing: 8).tiles.map { ($0.session, $0.rect) })
        if count == 5 {
            #expect(frames[sessions[2]]?.height == 903)
            #expect(frames[sessions[0]]?.height == 447.5)
        } else if count == 6 {
            #expect(frames.values.allSatisfy { abs($0.width - 542.3333333333) < 0.001 && $0.height == 447.5 })
        } else {
            let fourth = try #require(frames[sessions[3]])
            let fifth = try #require(frames[sessions[4]])
            let sixth = try #require(frames[sessions[5]])
            #expect(abs(fourth.minY - fifth.minY) < 0.001)
            #expect(abs(fourth.minY - sixth.minY) < 0.001)
            #expect(abs(fifth.maxY - layout.canvasSize.height) < 0.001)
            #expect(abs(sixth.height - 888) < 0.001)
            #expect(layout.tree.neighbor(of: sessions[3], toward: .right, in: layout.canvasSize, spacing: 8) == sessions[4])
            #expect(layout.tree.nudgedDivider(of: sessions[3], toward: .right, in: layout.canvasSize, spacing: 8) != nil)
        }
    }

    @Test func retainingHiddenPreservesVisibleTreeAndDividerIDs() {
        let sessions = ids(5)
        let layout = PaneGridLayout.automatic(sessions: Array(sessions.prefix(2)), viewport: CGSize(width: 1643, height: 903))
        let old = PaneLayoutPreset.grid2x2.tree(for: sessions)
        let retained = layout.tree.retainingHidden(from: old, allSessions: sessions, bounds: layout.canvasSize, spacing: 8)
        #expect(Set(retained.sessions) == Set(sessions))
        #expect(retained.pruned(visible: Set(sessions.prefix(2))) == layout.tree)
        let divider = layout.tree.frames(in: layout.canvasSize, spacing: 8).dividers[0]
        let adjusted = retained.settingDivider(divider.id, leadingFraction: 0.65).pruned(visible: Set(sessions.prefix(2)))
        #expect(adjusted == layout.tree.settingDivider(divider.id, leadingFraction: 0.65))
    }
}
