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

    @Test("変更タブの行ごとの色: 行の区切りが違う入力は、キャッシュで取り違えない")
    @MainActor
    func highlightedLinesCacheKeepsLineBoundaries() {
        let first = ChatCodeHighlighter.highlightLines(["a\u{0}b", "c"], path: "s.py")
        let second = ChatCodeHighlighter.highlightLines(["a", "b\u{0}c"], path: "s.py")
        #expect(first.map { String($0.characters) } == ["a\u{0}b", "c"])
        #expect(second.map { String($0.characters) } == ["a", "b\u{0}c"])
    }

    @Test("変更タブの行ごとの色: Python は def がキーワード、# がコメント")
    @MainActor
    func highlightedLinesUseExtensionRules() {
        let lines = ChatCodeHighlighter.highlightLines(["def f(): # 説明"], path: "s.py")
        #expect(color(of: "def", in: lines[0]) == DSColor.codeSyntaxKeyword)
        #expect(color(of: "# 説明", in: lines[0]) == DSColor.codeSyntaxComment)
    }
}
