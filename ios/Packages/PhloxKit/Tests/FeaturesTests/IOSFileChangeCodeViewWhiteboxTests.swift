import Testing
import PhloxCore
import ChatRenderKit
@testable import Features

@Suite("iOS ファイル変更コードビュー白箱")
struct IOSFileChangeCodeViewWhiteboxTests {
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
