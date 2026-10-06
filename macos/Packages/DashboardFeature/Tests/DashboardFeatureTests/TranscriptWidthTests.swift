import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// トランスクリプト内容の最大幅は `ComposerLayout.transcriptContentMaxWidth` に一本化され、
/// 全入力で composer 幅（`ComposerLayout.maxWidth`）と恒等である（出力メッセージ列の幅 = 入力欄の幅）。
@Suite("TranscriptWidth")
struct TranscriptWidthTests {

    @Test(arguments: [CGFloat(-100), -1, 0, 1, 500, 1000, 1332, 1333, 1334, 800 / 0.6, 2000, 8000, 10_000])
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
