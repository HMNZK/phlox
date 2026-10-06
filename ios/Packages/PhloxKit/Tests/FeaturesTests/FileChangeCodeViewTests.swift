import Testing
import PhloxCore
import ChatRenderKit
@testable import Features

// iOS のファイル変更表示（コードビュー・ADR 0146/0147）。
//   ①行番号は hunk ヘッダから起算し、分からないときは推測しない
//   ②hunk 行・--- / +++ ・no-newline 注記は表示しない（採番のデータとしては保持する）
//   ③行番号が 1 つも確定しない diff では番号列の幅を 0 にする
//   ④既定は折りたたみ（行数に依存した自動展開をしない）
//   ⑤見出しは「動詞 ファイル名 +A -D」、カード内にフルパス
//   ⑥コピーは元の diff 全文（表示から消した行を含む）

private let sampleDiff = """
--- a/lessons.md
+++ b/lessons.md
@@ -10,3 +20,4 @@
 context line
-removed line
+added line
\\ No newline at end of file
"""

private func change(_ path: String = "src/deep/lessons.md", _ diff: String = sampleDiff, _ kind: String? = "edit") -> ChatFileChange {
    ChatFileChange(path: path, diff: diff, kind: kind)
}

@Suite("iOS ファイル変更: 表示データ")
struct FileChangeCodeViewTests {
    @Test("hunk・ファイルヘッダ・no-newline 注記は表示しない")
    func noiseLinesAreHidden() {
        let data = SessionDetailDiffCodeViewData(changes: [change()])
        let texts = data.lines.map(\.text)
        #expect(texts.contains { $0.hasPrefix("@@") } == false)
        #expect(texts.contains { $0.hasPrefix("---") || $0.hasPrefix("+++") } == false)
        #expect(texts.contains { $0.contains("No newline at end of file") } == false)
        #expect(texts == [" context line", "-removed line", "+added line"])
    }

    @Test("行番号は hunk ヘッダから起算する（削除は旧側・追加とコンテキストは新側）")
    func lineNumbersComeFromHunkHeader() {
        let data = SessionDetailDiffCodeViewData(changes: [change()])
        #expect(data.hasLineNumbers == true)
        #expect(data.lines.map(\.displayLineNumber) == [20, 11, 21])
    }

    @Test("採番は共有実装と一致する（規則を二重に持たない）")
    func numberingMatchesSharedRule() {
        // 表示対象は「isDisplayable かつ hunk 行でない」行（hunk は採番のデータとしてだけ残す・ADR 0147）。
        let shared = ChatDiffClassifier.classify(sampleDiff).filter { $0.isDisplayable && $0.kind != .hunk }
        let data = SessionDetailDiffCodeViewData(changes: [change()])
        #expect(data.lines.map(\.displayLineNumber) == shared.map(\.displayLineNumber))
    }

    @Test("行番号が 1 つも確定しない diff では番号列の幅を 0 にする")
    func widthIsZeroWhenNoNumbers() {
        let data = SessionDetailDiffCodeViewData(changes: [change("a.swift", "+added\n-removed", "edit")])
        #expect(data.hasLineNumbers == false)
        #expect(data.lineNumberWidth == 0)
    }

    @Test("壊れた diff・空 diff でも落ちない", arguments: [
        "", "@@", "@@@@@@", "-", "+", "\\", "@@ -x +y @@\n+a",
    ])
    func brokenDiffIsSafe(_ diff: String) {
        _ = SessionDetailDiffCodeViewData(changes: [change("a.swift", diff, nil)])
    }

    @Test("見出しは 動詞 ファイル名 と増減行数")
    func titleShowsVerbAndCounts() {
        let data = SessionDetailDiffCodeViewData(changes: [change()])
        #expect(data.title == "編集済み lessons.md")
        #expect(data.additions == 1)
        #expect(data.deletions == 1)
    }

    @Test("カード内にはフルパスを出す")
    func fullPathIsShown() {
        let data = SessionDetailDiffCodeViewData(changes: [change()])
        #expect(data.fullPaths == ["src/deep/lessons.md"])
    }

    @Test("既定は折りたたみ（行数に依存した自動展開をしない）")
    func collapsedByDefault() {
        let short = SessionDetailDiffCodeViewData(changes: [change("a.swift", "@@ -1,1 +1,1 @@\n+a", "edit")])
        let long = SessionDetailDiffCodeViewData(changes: [
            change("a.swift", "@@ -1,200 +1,200 @@\n" + (1...200).map { "+line \($0)" }.joined(separator: "\n"), "edit")
        ])
        #expect(short.isExpandedByDefault == false)
        #expect(long.isExpandedByDefault == false)
    }

    @Test("コピーは表示から消した行を含む元の diff 全文を返す")
    func copyTextIsTheOriginalDiff() {
        let data = SessionDetailDiffCodeViewData(changes: [change()])
        #expect(data.copyText.contains("--- a/lessons.md"))
        #expect(data.copyText.contains("@@ -10,3 +20,4 @@"))
        #expect(data.copyText.contains("No newline at end of file"))
    }

    @Test("複数ファイルの変更も 1 つの表示データにまとまる")
    func multipleChanges() {
        let data = SessionDetailDiffCodeViewData(changes: [change(), change("other/foo.swift", "@@ -1,1 +1,1 @@\n+x", "write")])
        #expect(data.fullPaths == ["src/deep/lessons.md", "other/foo.swift"])
        #expect(data.title == ChatFileChangePresentation.title(for: [
            ChatFilePatch(path: "src/deep/lessons.md", diff: sampleDiff, kind: "edit"),
            ChatFilePatch(path: "other/foo.swift", diff: "@@ -1,1 +1,1 @@\n+x", kind: "write"),
        ]))
    }

    @Test("表示行は共有分類のマーカーを保ち、ハイライト本文からマーカーを分離する")
    func displayLinesKeepMarkersAndHighlightBody() {
        let data = SessionDetailDiffCodeViewData(changes: [
            ChatFileChange(
                path: "Sources/Example.swift",
                diff: "@@ -2,1 +2,1 @@\n-oldValue\n+let value = 1\n context",
                kind: "edit"
            ),
        ])

        #expect(data.lines.map(\.text) == ["-oldValue", "+let value = 1", " context"])
        #expect(data.lines.map(\.body) == ["oldValue", "let value = 1", "context"])
        #expect(data.lines.map { String($0.highlightedBody.characters) } == [
            "oldValue", "let value = 1", "context",
        ])
        #expect(data.lines.map(\.kind) == [.deletion, .addition, .context])
    }

    @Test("表示データのコピーは表示行の再構成ではなく各 change の原文を連結する")
    func copyTextPreservesEachOriginalDiff() {
        let first = "--- a/a.swift\n+++ b/a.swift\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file"
        let second = "@@ broken\n+second"
        let data = SessionDetailDiffCodeViewData(changes: [
            ChatFileChange(path: "a.swift", diff: first, kind: "edit"),
            ChatFileChange(path: "b.swift", diff: second, kind: "write"),
        ])

        #expect(data.copyText == "\(first)\n\n\(second)")
    }

    @Test("番号幅は表示対象の確定番号全体から求め、混在した空欄も同じ列に置く")
    func lineNumberWidthUsesAllConfirmedNumbers() {
        let data = SessionDetailDiffCodeViewData(changes: [
            ChatFileChange(
                path: "a.swift",
                diff: "@@ -1,1 +123456,1 @@\n numbered\n@@ broken\n unnumbered",
                kind: "edit"
            ),
        ])

        #expect(data.hasLineNumbers)
        #expect(data.lineNumberWidth == 6)
        #expect(data.lines.last?.displayLineNumber == nil)
    }
}
