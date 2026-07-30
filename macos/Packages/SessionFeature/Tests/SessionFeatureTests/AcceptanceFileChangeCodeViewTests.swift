// task-3 受け入れテスト。契約: tasks/task-3.md
import AppKit
import SwiftUI
import Testing
import StructuredChatKit
@testable import SessionFeature

@Suite("File change code view acceptance (task-3)")
struct AcceptanceFileChangeCodeViewTests {
    @Test(arguments: [
        ("edit", "編集済み"),
        ("MultiEdit", "編集済み"),
        ("write", "作成済み"),
        ("create", "作成済み"),
        ("delete", "削除済み"),
        ("rename", "変更済み"),
        (nil, "変更済み"),
    ])
    func ファイル変更種別から見出しの動詞を決める(kind: String?, expected: String) {
        #expect(FileChangePresentation.verb(for: kind) == expected)
    }

    @Test
    func 変更行数は複数ファイルを合算しヘッダとhunkを数えない() {
        let changes = [
            FilePatchChange(path: "Sources/A.swift", diff: "--- a/A.swift\n+++ b/A.swift\n@@ -1,2 +1,2 @@\n-old\n keep\n+new", kind: "edit"),
            FilePatchChange(path: "Sources/B.swift", diff: "+onlyAddition\n-deleteMe\n@@ -9 +9 @@", kind: "write"),
            FilePatchChange(path: "Sources/C.swift", diff: "@@ -1 +1 @@", kind: "edit"),
        ]

        #expect(FileChangePresentation.counts(for: changes) == .init(additions: 2, deletions: 2))
        #expect(FileChangePresentation.counts(for: [FilePatchChange(path: "Empty", diff: "@@ -0,0 +0,0 @@")]) == .init(additions: 0, deletions: 0))
        #expect(FileChangePresentation.title(for: [changes[0]]) == "編集済み A.swift")
        #expect(FileChangePresentation.title(for: changes) == "編集済み 3 件のファイル")
    }

    @Test(arguments: [0, 1, 500, 10_000])
    func ファイル変更は行数によらず既定で折りたたむ(lineCount: Int) {
        #expect(!FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount: lineCount))
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: true, lineCount: lineCount))
        #expect(!FileChangeDisplayPolicy.isExpanded(userOverride: false, lineCount: lineCount))
    }

    @Test
    func hunk起点の行番号は行種ごとに正しく付与される() {
        let lines = DiffLineClassifier.classify("""
        --- a/Sources/A.swift
        +++ b/Sources/A.swift
        @@ -10,2 +20,3 @@
        -let old = 1
         let unchanged = 2
        +let added = 3
        +let extra = 4
        @@ -30 +40 @@
        -struct Old {}
        +struct New {}
        """)

        #expect(lines.map(\.oldLineNumber) == [nil, nil, nil, 10, nil, nil, nil, nil, 30, nil])
        #expect(lines.map(\.newLineNumber) == [nil, nil, nil, nil, 20, 21, 22, nil, nil, 40])
    }

    @Test
    func hunk無しdiffでは行番号を推測しない() {
        let lines = DiffLineClassifier.classify("-old\n context\n+new")
        #expect(lines.allSatisfy { $0.oldLineNumber == nil && $0.newLineNumber == nil })
    }

    @Test
    func 壊れたhunkヘッダでもクラッシュせず採番をリセットする() {
        let malformedHeaders = [
            "@@ -1,2 + @@",
            "@@ - +1,2 @@",
            "@@ - + @@",
            "@@ -,2 +1,2 @@",
            "@@ -1,2 +,2 @@",
            "@@ broken @@",
        ]

        for header in malformedHeaders {
            let lines = DiffLineClassifier.classify("@@ -1 +1 @@\n+before\n\(header)\n+after")
            #expect(lines.map(\.displayLineNumber) == [nil, 1, nil, nil])
        }
    }

    @Test
    func noNewline注記は途中にあっても行番号を進めない() {
        let lines = DiffLineClassifier.classify("""
        @@ -1,2 +1,2 @@
         keep
        -old
        \\ No newline at end of file
        +new
        """)

        #expect(lines.map(\.displayLineNumber) == [nil, 1, 2, nil, 2])
        #expect(lines[3].newLineNumber == nil)
    }

    @Test
    func 最大行番号からの加算は採番を停止してクラッシュしない() {
        let lines = DiffLineClassifier.classify("@@ -9223372036854775807,1 +1,1 @@\n-old\n+new")

        #expect(lines.map(\.oldLineNumber) == [nil, .max, nil])
        #expect(lines.map(\.newLineNumber) == [nil, nil, nil])
    }

    @Test
    func hunkとfileHeaderとnoNewline注記はカード描画行から除く() {
        let view = DiffCodeViewData(diff: """
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1 @@
        -old
        +new
        \\ No newline at end of file
        """, path: "A.swift")
        #expect(view.lines.map { $0.line.text } == ["-old", "+new"])
    }

    @Test
    func swiftだけがキーワードを分類し未対応拡張子はplainへフォールバックする() {
        let swift = ChatCodeHighlighter.tokens(for: "func make() { let value = 1 }", path: "A.swift")
        let unknown = ChatCodeHighlighter.tokens(for: "func make() { let value = 1 }", path: "A.unknownext")

        #expect(swift.contains { $0.kind == .keyword && $0.text == "func" })
        #expect(unknown.allSatisfy { $0.kind == .plain })
    }

    @Test @MainActor
    func 省略とフィルタがあってもコピー元はdiff全文のまま() {
        let additions = (1...600).map { "+let value\($0) = \($0)" }.joined(separator: "\n")
        let fullDiff = "--- a/A.swift\n+++ b/A.swift\n@@ -1,600 +1,600 @@\n\(additions)\n\\ No newline at end of file"
        let cell = FileChangeCell(changes: [FilePatchChange(path: "A.swift", diff: fullDiff)], timestamp: .now)
        let sections = cell.visibleSections

        #expect(sections.count == 1)
        #expect(sections[0].codeView.lines.count == FileChangeDisplayPolicy.visibleLineLimit)
        #expect(sections[0].codeView.lines.map { $0.line.text }.joined(separator: "\n") != fullDiff)
        #expect(sections[0].copyText == fullDiff)
    }

    @Test @MainActor
    func 複数ファイルの各セクションはカードヘッダ用の完全パスを保持する() {
        let cell = FileChangeCell(
            changes: [
                FilePatchChange(path: "/repo/Sources/First.swift", diff: "+first"),
                FilePatchChange(path: "/repo/Tests/Second.swift", diff: "+second"),
            ],
            timestamp: .now
        )

        let sections = cell.visibleSections
        #expect(sections.count == 2)
        #expect(sections[0].path == "/repo/Sources/First.swift")
        #expect(sections[1].path == "/repo/Tests/Second.swift")
    }

    @Test
    func 行番号が皆無なら列を確保せず混在時は分かる行だけを表示する() {
        let withoutNumbers = DiffCodeViewData(diff: "-old\n+new", path: "A.swift")
        #expect(!withoutNumbers.hasLineNumbers)
        #expect(withoutNumbers.lineNumberWidth == 0)

        let mixed = DiffCodeViewData(diff: "@@ -10 +20 @@\n-old\n+new\n@@ malformed @@\n+unknown", path: "A.swift")
        #expect(mixed.hasLineNumbers)
        #expect(mixed.lineNumberWidth == 2)
        #expect(mixed.lines.map { $0.line.displayLineNumber } == [10, 20, nil])
    }

    @Test @MainActor
    func fileChangeCellをImageRendererで描画できる() {
        let cell = FileChangeCell(
            changes: [FilePatchChange(path: "/tmp/Sources/A.swift", diff: "@@ -1 +1 @@\n-let old = 1\n+let new = 2")],
            timestamp: .now
        )
        let renderer = ImageRenderer(content: cell.frame(width: 600))
        #expect(renderer.nsImage != nil)
    }
}
