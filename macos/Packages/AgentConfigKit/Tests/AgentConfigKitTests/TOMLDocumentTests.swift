import Foundation
import Testing
@testable import AgentConfigKit

private let sample = """
# 先頭のコメント
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
notify = ["/Applications/Some App.app/Contents/MacOS/tool", "turn-ended"]
service_tier = "default"   # 末尾コメント

[projects."/Users/me/A"]
trust_level = "trusted"

[projects."/Users/me/B"]
trust_level = "untrusted"

[features]
web_search = true
retries = 3

[mcp_servers.github]
command = "gh"
args = [
  "mcp",
  "serve",
]

"""

@Test("読み取りは型ごとに値を返す")
func tomlDocument_readsScalars() {
    let doc = TOMLDocument(text: sample)
    #expect(doc.string(at: ["model"]) == "gpt-5.6-sol")
    #expect(doc.string(at: ["service_tier"]) == "default")
    #expect(doc.bool(at: ["features", "web_search"]) == true)
    #expect(doc.integer(at: ["features", "retries"]) == 3)
    #expect(doc.string(at: ["projects", "/Users/me/B", "trust_level"]) == "untrusted")
    #expect(doc.string(at: ["missing"]) == nil)
}

@Test("複数行の配列も1つの値として読める")
func tomlDocument_readsMultilineArray() {
    let doc = TOMLDocument(text: sample)
    #expect(doc.stringArray(at: ["mcp_servers", "github", "args"]) == ["mcp", "serve"])
    #expect(doc.stringArray(at: ["notify"])?.count == 2)
    #expect(doc.stringArray(at: ["notify"])?.last == "turn-ended")
}

@Test("宣言済みテーブル名を文書順で列挙する")
func tomlDocument_listsSubtables() {
    let doc = TOMLDocument(text: sample)
    #expect(doc.subtableKeys(under: ["projects"]) == ["/Users/me/A", "/Users/me/B"])
    #expect(doc.hasTable(["features"]))
    #expect(!doc.hasTable(["nope"]))
}

@Test("既存キーの書き換えは、その行の値だけを差し替えて他行を1バイトも変えない")
func tomlDocument_replacesOnlyTargetLine() {
    var doc = TOMLDocument(text: sample)
    doc.setString("gpt-5.6-terra", at: ["model"])

    let before = sample.components(separatedBy: "\n")
    let after = doc.text.components(separatedBy: "\n")
    #expect(before.count == after.count)
    for (index, line) in before.enumerated() where index != 1 {
        #expect(after[index] == line, "行 \(index) が変わってしまった")
    }
    #expect(after[1] == "model = \"gpt-5.6-terra\"")
}

@Test("末尾コメント付きの行を書き換えてもコメントが残る")
func tomlDocument_preservesTrailingComment() {
    var doc = TOMLDocument(text: sample)
    doc.setString("flex", at: ["service_tier"])
    #expect(doc.text.contains("service_tier = \"flex\"   # 末尾コメント"))
}

@Test("既存テーブル内に無いキーは、そのテーブルの末尾へ足される")
func tomlDocument_appendsKeyIntoExistingTable() {
    var doc = TOMLDocument(text: sample)
    doc.setBool(false, at: ["features", "beta_ui"])

    let lines = doc.text.components(separatedBy: "\n")
    let featuresIndex = try! #require(lines.firstIndex(of: "[features]"))
    #expect(lines[featuresIndex + 3] == "beta_ui = false")
    // 隣のテーブルに漏れていない。
    #expect(doc.string(at: ["mcp_servers", "github", "command"]) == "gh")
}

@Test("テーブルごと無いキーは、新しいテーブルを文書末尾に作って足す")
func tomlDocument_createsMissingTable() {
    var doc = TOMLDocument(text: sample)
    doc.setString("trusted", at: ["projects", "/Users/me/C", "trust_level"])

    #expect(doc.text.contains("[projects.\"/Users/me/C\"]"))
    #expect(doc.string(at: ["projects", "/Users/me/C", "trust_level"]) == "trusted")
    #expect(doc.subtableKeys(under: ["projects"]) == ["/Users/me/A", "/Users/me/B", "/Users/me/C"])
}

@Test("ルート直下の新しいキーは、最初のテーブル見出しより前に入る")
func tomlDocument_insertsRootKeyBeforeFirstTable() {
    var doc = TOMLDocument(text: sample)
    doc.setString("pragmatic", at: ["personality"])

    let lines = doc.text.components(separatedBy: "\n")
    let personality = try! #require(lines.firstIndex(of: "personality = \"pragmatic\""))
    let firstTable = try! #require(lines.firstIndex(where: { $0.hasPrefix("[") }))
    #expect(personality < firstTable)
}

@Test("テーブル削除は見出しから次の見出し直前までを消す")
func tomlDocument_removesTable() {
    var doc = TOMLDocument(text: sample)
    doc.removeTable(["projects", "/Users/me/A"])

    #expect(doc.subtableKeys(under: ["projects"]) == ["/Users/me/B"])
    #expect(!doc.text.contains("/Users/me/A"))
    // 残りのテーブルは無傷。
    #expect(doc.string(at: ["projects", "/Users/me/B", "trust_level"]) == "untrusted")
    #expect(doc.bool(at: ["features", "web_search"]) == true)
}

@Test("キー削除は該当行だけを消す")
func tomlDocument_removesKey() {
    var doc = TOMLDocument(text: sample)
    doc.removeKey(at: ["features", "retries"])
    #expect(doc.integer(at: ["features", "retries"]) == nil)
    #expect(doc.bool(at: ["features", "web_search"]) == true)
}

@Test("何も書き換えなければ、テキストは1バイトも変わらない")
func tomlDocument_roundTripsUnchanged() {
    let doc = TOMLDocument(text: sample)
    #expect(doc.text == sample)
}

@Test("末尾に改行が無い文書でも往復で改行が増えない")
func tomlDocument_roundTripsWithoutTrailingNewline() {
    let text = "model = \"a\""
    var doc = TOMLDocument(text: text)
    #expect(doc.text == text)
    doc.setString("b", at: ["model"])
    #expect(doc.text == "model = \"b\"")
}

@Test("引用符やエスケープを含む値を書いても読み戻せる")
func tomlDocument_encodesSpecialCharacters() {
    var doc = TOMLDocument(text: sample)
    doc.setString("say \"hi\"\\path", at: ["model"])
    #expect(doc.string(at: ["model"]) == "say \"hi\"\\path")
}

@Test("複数行文字列を跨いでも次のキーを取り違えない")
func tomlDocument_skipsMultilineStrings() {
    let text = """
    intro = \"\"\"
    model = "この行はキーではない"
    \"\"\"
    model = "real"
    """
    let doc = TOMLDocument(text: text)
    #expect(doc.string(at: ["model"]) == "real")
}
