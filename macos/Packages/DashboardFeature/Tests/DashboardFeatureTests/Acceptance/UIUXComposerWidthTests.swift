import CoreGraphics
import Testing
@testable import SessionFeature

// 2026-09-24 ユーザー承認（「両方モックに合わせる」）で上限を 800 → 760（PhloxChat.dc.html）へ更新。
// 2026-09-26 ユーザー決定で「上限なしで 80%」へ更新。
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
        #expect(largestWidth <= 2000 * 0.8)
    }

    @Test(arguments: [500.0, 760 / 0.9, 1000.0, 1333.0, 1334.0, 2000.0])
    func marginsAndMaximumHaveOneContinuousRule(column: Double) throws {
        let width = try #require(ComposerLayout.maxWidth(mainColumnWidth: column))
        #expect(abs(width - column * 0.8) < 0.001)
    }

    @Test
    func actualComposerInputsFollowTheWidthContract() throws {
        let cases: [(CGFloat, CGFloat, ComposerFooterLayout, ComposerFooterLayout)] = [
            (500.5, 400.4, .minimal, .minimal),
            (612, 489.6, .minimal, .minimal),
            (613, 490.4, .compact, .compact),
            (749, 599.2, .compact, .compact),
            (750, 600, .standard, .compact),
            (950, 760, .standard, .compact),
            (1000, 800, .standard, .compact),
            (1500, 1200, .standard, .compact)
        ]
        for (parent, expected, single, grid) in cases {
            let transcript = try #require(ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: parent))
            let composer = try #require(ComposerLayout.proposedWidth(mainColumnWidth: parent))
            #expect(abs(transcript - expected) < 0.001)
            #expect(abs(composer - expected) < 0.001)
            #expect(ComposerLayout.controlsLayout(proposedWidth: composer) == single)
            #expect(ComposerLayout.gridControlsLayout(proposedWidth: composer) == grid)
        }
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
