import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-6 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-6.md — (1) 描画結果の同値性（メモ化しても出力が1ビットも変わらない）、
// (2) FileChangeCell の既定展開ポリシー（大きい diff は折りたたみ・表示行上限あり）。
// 挙動の詳細凍結は既存テスト（ChatCodeHighlighterTests / ChatMessageCellsRenderTests /
// Task4ChatCodeHighlighterAcceptanceTests — いずれも編集禁止）が担う。

@Suite(.serialized)
struct PM3Task6CellRenderEquivalenceAcceptanceTests {

    // 同一入力に対する highlight は決定論的（複数回呼んで完全一致）。
    // メモ化導入後もこの同値性が崩れないこと（キャッシュが別内容・stale を返さないことの下限保証）。
    @Test
    func highlight_isDeterministicAcrossRepeatedCalls() {
        let samples = [
            "let x = 42 // コメント\nfunc foo() -> String { \"文字列\" }",
            "import Foundation\n/* block */ struct A { var n: Int = 0xFF }",
            "echo \"hello\" && ls -la | grep -v tmp",
            "",
            "日本語のプレーンテキストと identifier123 と 3.14",
        ]
        for code in samples {
            let first = ChatCodeHighlighter.highlight(code)
            let second = ChatCodeHighlighter.highlight(code)
            let third = ChatCodeHighlighter.highlight(code)
            #expect(first == second, "同一入力の highlight が呼び出し間で不一致")
            #expect(second == third, "同一入力の highlight が呼び出し間で不一致（3回目）")
        }
    }

    // 異なる内容（同じ長さ）は異なる結果になり得る入力で、取り違えが起きないこと。
    // 「item.id＋本文長」キーの stale ヒット（同長別内容の取り違え）をキャッシュ導入後も検出する。
    @Test
    func highlight_doesNotConfuseSameLengthDifferentContent() {
        let a = "let value = 1"
        let b = "var value = 2"
        #expect(a.count == b.count, "テスト前提: 同じ長さの別内容")
        let ra1 = ChatCodeHighlighter.highlight(a)
        let rb = ChatCodeHighlighter.highlight(b)
        let ra2 = ChatCodeHighlighter.highlight(a)
        #expect(ra1 == ra2, "同一入力が安定しない")
        #expect(String(ra1.characters) == a)
        #expect(String(rb.characters) == b, "同長別内容で取り違え（stale キャッシュヒット）")
    }

    // splitFencedCodeBlocks の決定論性（メモ化導入後も分割結果が変わらない）。
    @Test
    func splitFencedCodeBlocks_isDeterministic() {
        let markdown = """
        前文です。
        ```swift
        let a = 1
        ```
        中間の文。
        ```
        plain block
        ```
        後文。
        """
        let first = ChatMarkdownFormatter.splitFencedCodeBlocks(markdown)
        let second = ChatMarkdownFormatter.splitFencedCodeBlocks(markdown)
        #expect(first.count == second.count)
        #expect(first.count >= 4, "fence 2つを含む分割が最低4セグメントになる想定（前文/コード/中間/コード/後文）")
    }

    // FileChange の既定展開ポリシー: 小さい diff は展開・大きい diff は折りたたみ。
    // 閾値と表示行上限は有限の定数として一元定義される。
    @Test
    func fileChangeDisplayPolicy_collapsesLargeDiffsAndBoundsVisibleLines() {
        #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: 5) == true, "小さい diff は既定展開")
        #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: 1000) == false, "大きい diff は既定折りたたみ")
        #expect(
            (50...400).contains(FileChangeDisplayPolicy.collapseThresholdLines),
            "折りたたみ閾値が有限の定数（50...400 行）で定義されていない: \(FileChangeDisplayPolicy.collapseThresholdLines)"
        )
        #expect(
            (100...2000).contains(FileChangeDisplayPolicy.visibleLineLimit),
            "表示行上限が有限の定数（100...2000 行）で定義されていない: \(FileChangeDisplayPolicy.visibleLineLimit)"
        )
        // 閾値との整合: 閾値以下は展開・閾値超は折りたたみ（境界の一貫性）。
        // 有限性は上の range 検査が強制するため、ここは有限のときのみ検査する（スタブの Int.max で
        // t+1 がオーバーフローするのを避ける）。
        let t = FileChangeDisplayPolicy.collapseThresholdLines
        if t < Int.max {
            #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: t) == true)
            #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: t + 1) == false)
        }
    }

    // DiffLineClassifier の決定論性（classify メモ化導入後も分類が変わらない）。
    @Test
    func diffLineClassifier_isDeterministic() {
        let diff = """
        @@ -1,3 +1,4 @@
         context line
        -removed line
        +added line
        +another added
        """
        let first = DiffLineClassifier.classify(diff)
        let second = DiffLineClassifier.classify(diff)
        #expect(first.count == second.count)
        #expect(first.count == 5)
    }
}
