import Testing
import SwiftUI
import DesignSystem
@testable import SessionFeature

/// 差分の色分けは、変更前（削除行）と変更後（追加行）を別々に分類する。
@Suite("差分の色分け: 削除側と追加側を分ける")
struct DiffHighlightSideTests {
    private func color(of word: String, in body: AttributedString) -> Color? {
        guard let range = body.range(of: word) else { return nil }
        return body[range].runs.first?.foregroundColor
    }

    @Test("削除行で始まったブロックコメントは、追加行の色に及ばない")
    @MainActor
    func deletedBlockCommentDoesNotLeakIntoAddedLine() {
        let diff = "@@ -1,1 +1,1 @@\n-/* 古い説明\n+const a = 1\n"
        let data = DiffCodeViewData(diff: diff, path: "a.js")
        let added = data.lines.first { $0.line.kind == .addition }
        #expect(added.flatMap { color(of: "const", in: $0.body) } == DSColor.codeSyntaxKeyword)
    }
}
