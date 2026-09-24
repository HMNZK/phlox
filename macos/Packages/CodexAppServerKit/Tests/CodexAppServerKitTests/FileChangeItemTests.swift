import Foundation
import Testing
@testable import CodexAppServerKit

// 0.156 の fileChange item は `changes: [{path, diff, kind: {type}}]` で届く（generate-json-schema の FileChangeThreadItem）。
// 最上位の diff だけを読んでいたため、会話にも承認カードにもファイルが出なかった。

@Test func threadItem_fileChangesReadsChangesArray() throws {
    let json = """
    {"type":"fileChange","id":"call_1","status":"inProgress","changes":[
      {"path":"/tmp/a.txt","diff":"a\\nb\\n","kind":{"type":"add"}},
      {"path":"/tmp/b.txt","diff":"@@ -1 +1 @@\\n-x\\n+y\\n","kind":{"type":"update","move_path":null}},
      {"path":"/tmp/c.txt","kind":"delete"}
    ]}
    """
    let item = try JSONDecoder().decode(ThreadItem.self, from: Data(json.utf8))

    #expect(item.fileChanges.map(\.path) == ["/tmp/a.txt", "/tmp/b.txt"])
    #expect(item.fileChanges.map(\.kindName) == ["add", "update"])
    #expect(FilePatchChange(path: "x", diff: "", kind: .string("delete")).kindName == "delete")
}

@Test func threadItem_fileChangesEmptyWithoutArray() throws {
    let item = try JSONDecoder().decode(ThreadItem.self, from: Data(#"{"type":"fileChange","id":"x","diff":"d"}"#.utf8))
    #expect(item.fileChanges.isEmpty)
}

@Test func filePatchChange_unifiedDiffMarksAddedAndDeletedContent() {
    #expect(FilePatchChange(path: "a", diff: "a\n\nb\n", kind: .object(["type": .string("add")])).unifiedDiff == "+a\n+\n+b")
    #expect(FilePatchChange(path: "a", diff: "x\n", kind: .string("delete")).unifiedDiff == "-x")
    #expect(FilePatchChange(path: "a.md", diff: "---\ntitle: x\n---\n", kind: .string("add")).unifiedDiff == "+---\n+title: x\n+---")
    let added = "--- /dev/null\n+++ b/a\n@@ -0,0 +1 @@\n+a\n"
    #expect(FilePatchChange(path: "a", diff: added, kind: .string("add")).unifiedDiff == added)
    let update = "@@ -1 +1 @@\n-x\n+y\n"
    #expect(FilePatchChange(path: "a", diff: update, kind: .object(["type": .string("update")])).unifiedDiff == update)
}
