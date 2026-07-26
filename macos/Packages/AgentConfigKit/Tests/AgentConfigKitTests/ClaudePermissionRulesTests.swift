import Foundation
import Testing
@testable import AgentConfigKit

private func decode(_ json: String) throws -> JSONValue {
    try JSONValueCoder.decode(Data(json.utf8))
}

@Test("permissions の3バケットを読み出せる")
func permissionRules_extractsBuckets() throws {
    let root = try decode("""
    {"permissions":{"allow":["Bash(git status)","Read"],"deny":["Bash(rm *)"],"ask":["WebFetch"]}}
    """)
    let rules = ClaudePermissionRules.extract(from: root)
    #expect(rules.allow == ["Bash(git status)", "Read"])
    #expect(rules.deny == ["Bash(rm *)"])
    #expect(rules.ask == ["WebFetch"])
}

@Test("permissions 配下の未知キー（defaultMode 等）は書き戻しても残る")
func permissionRules_preservesUnknownPermissionKeys() throws {
    let root = try decode("""
    {"permissions":{"allow":["Read"],"defaultMode":"acceptEdits","additionalDirectories":["/tmp"]}}
    """)
    var rules = ClaudePermissionRules.extract(from: root)
    rules.add("Bash(ls)", to: .allow)
    let updated = rules.apply(to: root)

    #expect(updated["permissions"]?["defaultMode"]?.stringValue == "acceptEdits")
    #expect(updated["permissions"]?["additionalDirectories"]?.stringArrayValue == ["/tmp"])
    #expect(updated["permissions"]?["allow"]?.stringArrayValue == ["Read", "Bash(ls)"])
}

@Test("空になったバケットはキーごと消える")
func permissionRules_dropsEmptyBuckets() throws {
    let root = try decode(#"{"permissions":{"allow":["Read"],"deny":["Bash(rm *)"]}}"#)
    var rules = ClaudePermissionRules.extract(from: root)
    rules.remove("Read", from: .allow)
    let updated = rules.apply(to: root)

    #expect(updated["permissions"]?["allow"] == nil)
    #expect(updated["permissions"]?["deny"]?.stringArrayValue == ["Bash(rm *)"])
}

@Test("3バケットとも空で他キーも無ければ permissions ごと消える")
func permissionRules_dropsPermissionsWhenFullyEmpty() throws {
    let root = try decode(#"{"model":"sonnet","permissions":{"allow":["Read"]}}"#)
    var rules = ClaudePermissionRules.extract(from: root)
    rules.remove("Read", from: .allow)
    let updated = rules.apply(to: root)

    #expect(updated["permissions"] == nil)
    #expect(updated["model"]?.stringValue == "sonnet")
}

@Test("重複ルールと空文字は追加されない")
func permissionRules_rejectsDuplicateAndBlank() {
    var rules = ClaudePermissionRules(allow: ["Read"])
    let addedDuplicate = rules.add("Read", to: .allow)
    let addedBlank = rules.add("   ", to: .allow)
    let addedNew = rules.add("  Bash(ls)  ", to: .allow)

    #expect(addedDuplicate == false)
    #expect(addedBlank == false)
    #expect(addedNew)
    #expect(rules.allow == ["Read", "Bash(ls)"])
}

@Test("ルールを別のバケットへ移せる")
func permissionRules_movesBetweenBuckets() {
    var rules = ClaudePermissionRules(allow: ["Bash(rm *)"])
    rules.move("Bash(rm *)", from: .allow, to: .deny)
    #expect(rules.allow.isEmpty)
    #expect(rules.deny == ["Bash(rm *)"])
}
