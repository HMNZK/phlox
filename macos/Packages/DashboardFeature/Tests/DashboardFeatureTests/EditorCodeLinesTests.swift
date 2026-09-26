import Foundation
import Testing
@testable import DashboardFeature

// 07 D2: 差分を行番号つきの行に分け、「さらに表示（残り n 塊 · m 行）」の数を出す。

private let twoHunkDiff = """
diff --git a/Broker.swift b/Broker.swift
index 1111111..2222222 100644
--- a/Broker.swift
+++ b/Broker.swift
@@ -88,3 +88,4 @@ struct Broker {
     func requests() {
-        pending
+        let now = clock.now
+        expireOverdue(at: now)
     }
@@ -120,2 +121,2 @@ struct Broker {
-    let old = 1
+    let new = 2
     done()
"""

@Test func diffLinesNumberAddedAndContextByNewFileAndRemovedByOldFile() {
    let lines = EditorCodeLines.diff(twoHunkDiff)

    #expect(lines.prefix(6) == [
        EditorCodeLine(number: nil, text: "@@ -88,3 +88,4 @@ struct Broker {", kind: .hunk),
        EditorCodeLine(number: 88, text: "    func requests() {", kind: .context),
        EditorCodeLine(number: 89, text: "        pending", kind: .removed),
        EditorCodeLine(number: 89, text: "        let now = clock.now", kind: .added),
        EditorCodeLine(number: 90, text: "        expireOverdue(at: now)", kind: .added),
        EditorCodeLine(number: 91, text: "    }", kind: .context),
    ])
    #expect(lines[7] == EditorCodeLine(number: 120, text: "    let old = 1", kind: .removed))
    #expect(lines[8] == EditorCodeLine(number: 121, text: "    let new = 2", kind: .added))
}

@Test func remainderCountsPartialAndFollowingHunks() {
    let lines = EditorCodeLines.diff(twoHunkDiff)

    // 先頭 3 行（見出し・88・89 削除）の後ろ: 1 つ目の塊の残りと 2 つ目の塊。
    let rest = EditorCodeLines.remainder(of: lines, after: 3)

    #expect(rest.hunks == 2)
    #expect(rest.lines == 6)
}

@Test func contentLinesAreNumberedFromOne() {
    let lines = EditorCodeLines.content("let a = 1\nlet b = 2\n")

    #expect(lines == [
        EditorCodeLine(number: 1, text: "let a = 1", kind: .context),
        EditorCodeLine(number: 2, text: "let b = 2", kind: .context),
    ])
}

@Test func diffWithoutHunksShowsGitHeaderInsteadOfEmptyPane() {
    let lines = EditorCodeLines.diff("diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n")

    #expect(lines == [
        EditorCodeLine(number: nil, text: "diff --git a/run.sh b/run.sh", kind: .context),
        EditorCodeLine(number: nil, text: "old mode 100644", kind: .context),
        EditorCodeLine(number: nil, text: "new mode 100755", kind: .context),
    ])
}

// 2026-09-26 ユーザー報告（変更タブの色分けが効かない）: 本文は塊ごと・変更前と変更後で別々に分類する。
@Test func highlightedBodiesClassifyRemovedAndAddedSidesSeparatelyPerHunk() {
    let lines = EditorCodeLines.diff(twoHunkDiff)
    var calls: [[String]] = []
    let bodies = EditorCodeLines.highlightedBodies(lines) { texts in
        calls.append(texts)
        return texts.map { AttributedString("\(calls.count - 1):\($0)") }
    }

    #expect(calls == [
        ["    func requests() {", "        pending", "    }"],
        ["    func requests() {", "        let now = clock.now", "        expireOverdue(at: now)", "    }"],
        ["    let old = 1", "    done()"],
        ["    let new = 2", "    done()"],
    ])
    // 削除行は変更前の側、追加行と文脈は変更後の側の色。見出しは分類しない。
    #expect(String(bodies[0].characters) == "@@ -88,3 +88,4 @@ struct Broker {")
    #expect(String(bodies[1].characters) == "1:    func requests() {")
    #expect(String(bodies[2].characters) == "0:        pending")
    #expect(String(bodies[3].characters) == "1:        let now = clock.now")
}

@Test func highlightedBodiesClassifyFileContentOnce() {
    var calls: [[String]] = []
    _ = EditorCodeLines.highlightedBodies(EditorCodeLines.content("a\nb\n")) { texts in
        calls.append(texts)
        return texts.map { AttributedString($0) }
    }
    #expect(calls == [["a", "b"]])
}
