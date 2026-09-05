import CoreGraphics
import Testing
@testable import SessionFeature

@Suite("UI-02 continuous composer width")
struct UIUXComposerWidthTests {
    @Test
    func wideningTheColumnNeverShrinksItsContent() throws {
        var widths: [CGFloat] = [0]
        for column in 1...2000 {
            let width = try #require(ComposerLayout.maxWidth(mainColumnWidth: CGFloat(column)))
            #expect(ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: CGFloat(column)) == width)
            widths.append(width)
        }
        let changes = zip(widths.dropFirst(), widths).map { $0 - $1 }
        let smallestChange = try #require(changes.min())
        let largestChange = try #require(changes.max())
        let largestWidth = try #require(widths.max())
        #expect(smallestChange >= 0)
        #expect(largestChange <= 1)
        #expect(largestWidth <= 800)
    }

    @Test(arguments: [500.0, 800 / 0.9, 1000.0, 1333.0, 1334.0, 2000.0])
    func marginsAndMaximumHaveOneContinuousRule(column: Double) throws {
        let width = try #require(ComposerLayout.maxWidth(mainColumnWidth: column))
        #expect(abs(width - min(column * 0.9, 800)) < 0.001)
    }

    @Test
    func unresolvedWidthAndFooterBoundariesRemainStable() {
        #expect(ComposerLayout.maxWidth(mainColumnWidth: 0) == nil)
        #expect(ComposerLayout.maxWidth(mainColumnWidth: -1) == nil)
        #expect(ComposerLayout.maxWidth(mainColumnWidth: .nan) == nil)
        #expect(ComposerLayout.controlsLayout(proposedWidth: 489) == .minimal)
        #expect(ComposerLayout.controlsLayout(proposedWidth: 490) == .compact)
        #expect(ComposerLayout.controlsLayout(proposedWidth: 599) == .compact)
        #expect(ComposerLayout.controlsLayout(proposedWidth: 600) == .standard)
        #expect(ComposerLayout.scrollerCorridorWidth == 16)
    }
}
