import Foundation
import Testing
@testable import AgentConfigKit

private func decode(_ json: String) throws -> JSONValue {
    try JSONValueCoder.decode(Data(json.utf8))
}

private let sampleHooks = """
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "guard.sh", "timeout": 5 },
        { "type": "command", "command": "audit.sh" }
      ]}
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "verify.sh" } ] }
    ]
  }
}
"""

@Test("登録済みフックをイベント順・出現順で列挙する")
func hookSettings_listsEntries() throws {
    let entries = ClaudeHookSettings.entries(from: try decode(sampleHooks))
    #expect(entries.count == 3)
    #expect(entries[0].event == "PreToolUse")
    #expect(entries[0].matcher == "Bash")
    #expect(entries[0].command == "guard.sh")
    #expect(entries[0].timeoutSeconds == 5)
    #expect(entries[1].command == "audit.sh")
    #expect(entries[1].timeoutSeconds == nil)
    #expect(entries[2].event == "Stop")
    #expect(entries[2].matcher == nil)
}

@Test("1件消しても同じグループの他のフックは残る")
func hookSettings_removesSingleEntry() throws {
    let root = try decode(sampleHooks)
    let entries = ClaudeHookSettings.entries(from: root)
    let target = try #require(entries.first { $0.command == "guard.sh" })

    let updated = ClaudeHookSettings.removing(target, from: root)
    let remaining = ClaudeHookSettings.entries(from: updated).map(\.command)
    #expect(remaining == ["audit.sh", "verify.sh"])
}

@Test("グループの最後の1件を消すとグループごと、イベントごと畳まれる")
func hookSettings_collapsesEmptyGroupsAndEvents() throws {
    let root = try decode(sampleHooks)
    let target = try #require(ClaudeHookSettings.entries(from: root).first { $0.command == "verify.sh" })

    let updated = ClaudeHookSettings.removing(target, from: root)
    #expect(updated["hooks"]?["Stop"] == nil)
    #expect(updated["hooks"]?["PreToolUse"] != nil)
}

@Test("全部消すと hooks キー自体が消える")
func hookSettings_dropsHooksKeyWhenEmpty() throws {
    var root = try decode(#"{"model":"sonnet","hooks":{"Stop":[{"hooks":[{"type":"command","command":"a.sh"}]}]}}"#)
    let target = try #require(ClaudeHookSettings.entries(from: root).first)
    root = ClaudeHookSettings.removing(target, from: root)
    #expect(root["hooks"] == nil)
    #expect(root["model"]?.stringValue == "sonnet")
}

@Test("同じ matcher のグループがあればそこへ追加する")
func hookSettings_addsIntoExistingMatcherGroup() throws {
    let root = try decode(sampleHooks)
    let updated = ClaudeHookSettings.adding(
        event: "PreToolUse", matcher: "Bash", command: "extra.sh", timeoutSeconds: nil, to: root
    )
    let groups = try #require(updated["hooks"]?["PreToolUse"]?.arrayValue)
    #expect(groups.count == 1)
    #expect(groups[0]["hooks"]?.arrayValue?.count == 3)
}

@Test("matcher が違えば新しいグループを作る")
func hookSettings_createsNewGroupForDifferentMatcher() throws {
    let root = try decode(sampleHooks)
    let updated = ClaudeHookSettings.adding(
        event: "PreToolUse", matcher: "Edit", command: "edit-guard.sh", timeoutSeconds: 10, to: root
    )
    let groups = try #require(updated["hooks"]?["PreToolUse"]?.arrayValue)
    #expect(groups.count == 2)
    let added = try #require(ClaudeHookSettings.entries(from: updated).first { $0.command == "edit-guard.sh" })
    #expect(added.matcher == "Edit")
    #expect(added.timeoutSeconds == 10)
}

@Test("空のコマンドは追加しない")
func hookSettings_ignoresBlankCommand() throws {
    let root = try decode(sampleHooks)
    let updated = ClaudeHookSettings.adding(
        event: "Stop", matcher: nil, command: "   ", timeoutSeconds: nil, to: root
    )
    #expect(ClaudeHookSettings.entries(from: updated).count == 3)
}
