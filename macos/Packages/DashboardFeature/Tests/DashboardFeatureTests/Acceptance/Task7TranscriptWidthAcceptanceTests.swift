import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-7 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 要件3（出力メッセージ列の幅 = 入力欄の幅）の契約:
/// トランスクリプト内容の最大幅は `ComposerLayout.transcriptContentMaxWidth` に一本化し、
/// これは全入力で `ComposerLayout.maxWidth`（composer 幅の単一真実源）と恒等であること。
/// 幅の視覚的一致・CPU 収束維持（runtime 挙動）は PM の実機統合検証が担う。
@Suite("task-7 transcript width acceptance")
struct Task7TranscriptWidthAcceptanceTests {

    @Test(arguments: [CGFloat(-100), 0, 1, 500, 1000, 1332, 1333, 1334, 2000, 8000])
    func transcriptWidthIsIdenticalToComposerWidth(width: CGFloat) {
        // 恒等別名: 境界（90%/800 切替）・nil 域を含む全域で composer 幅と一致する。
        #expect(
            ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: width)
                == ComposerLayout.maxWidth(mainColumnWidth: width)
        )
    }

    @Test
    func unknownWidthFallsBackToNil() {
        // 初回フレーム（幅未確定）は composer 側と同じく制約なし。
        #expect(ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: 0) == nil)
    }
}
