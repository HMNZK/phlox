import Testing
import PhloxCore
import ChatRenderKit
@testable import Features

// iOS のファイル変更表示（コードビュー・ADR 0146/0147）。
//   ①行番号は hunk ヘッダから起算し、分からないときは推測しない
//   ②hunk 行・--- / +++ ・no-newline 注記は表示しない（採番のデータとしては保持する）
//   ③行番号が 1 つも確定しない diff では番号列の幅を 0 にする
//   ④既定は折りたたみ（行数に依存した自動展開をしない）
//   ⑤見出しは「動詞」、要約にフルパス、右端に +A −D
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
        let data = SessionDetailDiffCodeViewData(change: change())
        let texts = data.lines.map(\.text)
        #expect(texts.contains { $0.hasPrefix("@@") } == false)
        #expect(texts.contains { $0.hasPrefix("---") || $0.hasPrefix("+++") } == false)
        #expect(texts.contains { $0.contains("No newline at end of file") } == false)
        #expect(texts == [" context line", "-removed line", "+added line"])
    }

    @Test("行番号は hunk ヘッダから起算する（削除は旧側・追加とコンテキストは新側）")
    func lineNumbersComeFromHunkHeader() {
        let data = SessionDetailDiffCodeViewData(change: change())
        #expect(data.hasLineNumbers == true)
        #expect(data.lines.map(\.displayLineNumber) == [20, 11, 21])
    }

    @Test("採番は共有実装と一致する（規則を二重に持たない）")
    func numberingMatchesSharedRule() {
        // 表示対象は「isDisplayable かつ hunk 行でない」行（hunk は採番のデータとしてだけ残す・ADR 0147）。
        let shared = ChatDiffClassifier.classify(sampleDiff).filter { $0.isDisplayable && $0.kind != .hunk }
        let data = SessionDetailDiffCodeViewData(change: change())
        #expect(data.lines.map(\.displayLineNumber) == shared.map(\.displayLineNumber))
    }

    @Test("行番号が 1 つも確定しない diff では番号列の幅を 0 にする")
    func widthIsZeroWhenNoNumbers() {
        let data = SessionDetailDiffCodeViewData(change: change("a.swift", "+added\n-removed", "edit"))
        #expect(data.hasLineNumbers == false)
        #expect(data.lineNumberWidth == 0)
    }

    @Test("壊れた diff・空 diff でも落ちない", arguments: [
        "", "@@", "@@@@@@", "-", "+", "\\", "@@ -x +y @@\n+a",
    ])
    func brokenDiffIsSafe(_ diff: String) {
        _ = SessionDetailDiffCodeViewData(change: change("a.swift", diff, nil))
    }

    @Test("見出しは動詞、要約用パスと増減行数を保持する")
    func titleShowsVerbPathAndCounts() {
        let data = SessionDetailDiffCodeViewData(change: change())
        #expect(data.title == "編集")
        #expect(data.path == "src/deep/lessons.md")
        #expect(data.additions == 1)
        #expect(data.deletions == 1)
        #expect(data.countBadges.map(\.text) == ["+1", "−1"])
    }

    @Test("増減が 0 の印は出さない")
    func zeroFileChangeCountsAreOmitted() {
        let added = SessionDetailDiffCodeViewData(change: change(
            "new.swift",
            "@@ -0,0 +1,2 @@\n+one\n+two",
            "create"
        ))
        let unchanged = SessionDetailDiffCodeViewData(change: change("empty.swift", "", "edit"))

        #expect(added.countBadges.map { $0.text } == ["+2"])
        #expect(unchanged.countBadges.isEmpty)
    }

    @Test("見出しの要約用にフルパスを保持する")
    func fullPathIsAvailableForHeader() {
        let data = SessionDetailDiffCodeViewData(change: change())
        #expect(data.path == "src/deep/lessons.md")
    }

    @Test("既定は折りたたみ（行数に依存した自動展開をしない）")
    func collapsedByDefault() {
        let short = SessionDetailDiffCodeViewData(change: change("a.swift", "@@ -1,1 +1,1 @@\n+a", "edit"))
        let long = SessionDetailDiffCodeViewData(change: change(
            "a.swift",
            "@@ -1,200 +1,200 @@\n" + (1...200).map { "+line \($0)" }.joined(separator: "\n"),
            "edit"
        ))
        #expect(short.isExpandedByDefault == false)
        #expect(long.isExpandedByDefault == false)
    }

    @Test("表示行は共有分類のマーカーと本文を分けて保つ")
    func displayLinesKeepMarkersAndBody() {
        let data = SessionDetailDiffCodeViewData(change: ChatFileChange(
            path: "Sources/Example.swift",
            diff: "@@ -2,1 +2,1 @@\n-oldValue\n+let value = 1\n context",
            kind: "edit"
        ))

        #expect(data.lines.map(\.text) == ["-oldValue", "+let value = 1", " context"])
        #expect(data.lines.map(\.body) == ["oldValue", "let value = 1", "context"])
        #expect(data.lines.map(\.kind) == [.deletion, .addition, .context])
    }

    @Test("コピーは表示行の再構成ではなく入力 diff 全文を返す")
    func copyTextIsOriginalDiff() {
        let diff = "--- a/a.swift\n+++ b/a.swift\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file"
        let data = SessionDetailDiffCodeViewData(change: ChatFileChange(path: "a.swift", diff: diff, kind: "edit"))
        #expect(data.copyText == diff)
    }

    @Test("番号幅は表示対象の確定番号全体から求め、混在した空欄も同じ列に置く")
    func lineNumberWidthUsesAllConfirmedNumbers() {
        let data = SessionDetailDiffCodeViewData(change: ChatFileChange(
            path: "a.swift",
            diff: "@@ -1,1 +123456,1 @@\n numbered\n@@ broken\n unnumbered",
            kind: "edit"
        ))

        #expect(data.hasLineNumbers)
        #expect(data.lineNumberWidth == 6)
        #expect(data.lines.last?.displayLineNumber == nil)
    }
}
