import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-7 白箱テスト — transcript 幅 API が composer 幅の恒等別名であることを固定する。
@Suite("TranscriptWidth whitebox")
struct TranscriptWidthTests {

    @Test(arguments: [CGFloat(-1), 0, 1, 500, 1000, 800 / 0.6, 10_000])
    func transcriptContentWidthIsComposerWidthAlias(width: CGFloat) {
        #expect(
            ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: width)
                == ComposerLayout.maxWidth(mainColumnWidth: width)
        )
    }

    @Test
    func unknownOrInvalidWidthsRemainUnconstrained() {
        #expect(ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: 0) == nil)
        #expect(ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: -100) == nil)
    }
}
