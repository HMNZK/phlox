import Foundation
import Testing
@testable import AgentConfigKit

private let configJSON = """
{
  "version": 3,
  "approvalMode": "allowlist",
  "notifications": true,
  "hints": true,
  "rewind": false,
  "sandbox": { "mode": "disabled", "networkAccess": "user_config_with_defaults" },
  "display": { "zenMode": true, "showLineNumbers": false },
  "editor": { "vimMode": false },
  "attribution": { "attributeCommitsToAgent": true, "attributePRsToAgent": true },
  "permissions": { "allow": ["Shell(git status)"], "deny": [] },
  "model": {
    "modelId": "composer-2.5",
    "displayName": "Composer 2.5",
    "aliases": ["composer"]
  },
  "selectedModel": { "modelId": "composer-2.5", "parameters": [{ "id": "fast", "value": "false" }] },
  "authInfo": { "token": "secret-value" },
  "modelParameters": { "composer-2.5": [{ "id": "fast", "value": "false" }] }
}
"""

private func loadConfig() throws -> JSONValue {
    try JSONValueCoder.decode(Data(configJSON.utf8))
}

// MARK: - 設定値

@Test("入れ子のキーを読み書きできる")
func cursorGeneralSettings_readsAndWritesNestedKeys() throws {
    let root = try loadConfig()
    #expect(CursorGeneralSettings.string(.approvalMode, in: root) == "allowlist")
    #expect(CursorGeneralSettings.bool(.zenMode, in: root) == true)
    #expect(CursorGeneralSettings.bool(.showLineNumbers, in: root) == false)

    let updated = CursorGeneralSettings.setBool(true, for: .showLineNumbers, in: root)
    #expect(CursorGeneralSettings.bool(.showLineNumbers, in: updated) == true)
    // 同じ入れ子の兄弟キーは残る。
    #expect(CursorGeneralSettings.bool(.zenMode, in: updated) == true)
}

@Test("設定を書き換えても認証情報やキャッシュには触らない")
func cursorGeneralSettings_preservesUnknownKeys() throws {
    let root = try loadConfig()
    let updated = CursorGeneralSettings.setString("unrestricted", for: .approvalMode, in: root)

    #expect(updated["authInfo"]?["token"]?.stringValue == "secret-value")
    #expect(updated["modelParameters"]?["composer-2.5"] != nil)
    #expect(updated["version"]?.intValue == 3)
    #expect(updated["sandbox"]?["networkAccess"]?.stringValue == "user_config_with_defaults")
}

@Test("途中のオブジェクトが無いキーでも書ける")
func cursorGeneralSettings_createsMissingParents() {
    let updated = CursorGeneralSettings.setBool(true, for: .vimMode, in: .object([:]))
    #expect(updated["editor"]?["vimMode"]?.boolValue == true)
}

@Test("設定項目はグループごとに分かれている")
func cursorSettingKey_groupsCoverAllKeys() {
    let grouped = CursorSettingKey.Group.allCases.flatMap { CursorGeneralSettings.keys(in: $0) }
    #expect(Set(grouped) == Set(CursorSettingKey.allCases))
    #expect(CursorSettingKey.approvalMode.kind == .choice(["allowlist", "unrestricted", "auto-review"]))
    #expect(CursorSettingKey.zenMode.kind == .toggle)
}

@Test("見知らぬ現在値も選択肢に残す")
func cursorSettingKey_keepsUnknownCurrentValue() {
    #expect(CursorSettingKey.sandboxMode.options(current: "enabled") == ["disabled", "enabled"])
    #expect(CursorSettingKey.sandboxMode.options(current: "future") == ["future", "disabled", "enabled"])
    #expect(CursorSettingKey.zenMode.options(current: "x").isEmpty)
}

// MARK: - 権限

@Test("許可・拒否ルールを読み書きできる")
func cursorPermissionRules_roundTrips() throws {
    let root = try loadConfig()
    var rules = CursorPermissionRules.extract(from: root)
    #expect(rules.allow == ["Shell(git status)"])
    #expect(rules.deny.isEmpty)

    let addedNewRule = rules.add("Shell(rm -rf /)", to: .deny)
    let addedBlank = rules.add("   ", to: .deny)
    let addedDuplicate = rules.add("Shell(git status)", to: .allow)
    #expect(addedNewRule)
    #expect(!addedBlank)
    #expect(!addedDuplicate)

    let updated = rules.apply(to: root)
    #expect(CursorPermissionRules.extract(from: updated).deny == ["Shell(rm -rf /)"])
    #expect(updated["authInfo"]?["token"]?.stringValue == "secret-value")
}

@Test("バケット間の移動で重複が生まれない")
func cursorPermissionRules_movesBetweenBuckets() throws {
    var rules = CursorPermissionRules.extract(from: try loadConfig())
    rules.move("Shell(git status)", from: .allow, to: .deny)
    #expect(rules.allow.isEmpty)
    #expect(rules.deny == ["Shell(git status)"])
}

@Test("空になってもキー自体は残す")
func cursorPermissionRules_keepsEmptyArrays() throws {
    let root = try loadConfig()
    var rules = CursorPermissionRules.extract(from: root)
    rules.remove("Shell(git status)", from: .allow)
    let updated = rules.apply(to: root)

    #expect(updated["permissions"]?["allow"]?.arrayValue?.isEmpty == true)
    #expect(updated["permissions"]?["deny"] != nil)
}

// MARK: - モデル

@Test("cursor-agent models の出力を選択肢へ写す")
func cursorModelSettings_parsesModels() {
    let output = """
    Available models

    auto - Auto (default)
    gpt-5.3-codex-high - Codex 5.3 High
    composer-2.5 - Composer 2.5 (current)
    """
    let models = CursorModelSettings.parseModels(from: output)
    #expect(models.map(\.modelID) == ["auto", "gpt-5.3-codex-high", "composer-2.5"])
    #expect(models[0].displayName == "Auto (default)")
}

@Test("モデル変更は model と selectedModel の両方を揃える")
func cursorModelSettings_writesBothPlaces() throws {
    let root = try loadConfig()
    let updated = CursorModelSettings.apply(
        CursorModelOption(modelID: "gpt-5.2", displayName: "GPT-5.2"),
        to: root
    )

    #expect(CursorModelSettings.currentModelID(in: updated) == "gpt-5.2")
    #expect(updated["model"]?["displayName"]?.stringValue == "GPT-5.2")
    #expect(updated["selectedModel"]?["modelId"]?.stringValue == "gpt-5.2")
    #expect(updated["hasChangedDefaultModel"]?.boolValue == true)
    // 意味を知らないキーは触らない。
    #expect(updated["model"]?["aliases"]?.stringArrayValue == ["composer"])
    #expect(updated["selectedModel"]?["parameters"] != nil)
}

// MARK: - MCP

@Test("mcp.json から stdio と HTTP のサーバーを読む")
func cursorMCPServers_readsBothTransports() throws {
    let json = """
    {"mcpServers":{
      "local":{"command":"npx","args":["-y","server"]},
      "remote":{"url":"https://example.com/mcp","type":"http"}
    }}
    """
    let servers = CursorMCPServers.servers(from: try JSONValueCoder.decode(Data(json.utf8)))
    #expect(servers.map(\.name) == ["local", "remote"])
    #expect(servers[0].endpoint == "npx -y server")
    #expect(servers[0].transportType == "stdio")
    #expect(servers[1].endpoint == "https://example.com/mcp")
}

@Test("MCP サーバーの追加と削除で他の登録が消えない")
func cursorMCPServers_addsAndRemoves() throws {
    let json = #"{"mcpServers":{"keep":{"url":"https://keep.example"}}}"#
    let root = try JSONValueCoder.decode(Data(json.utf8))

    let added = CursorMCPServers.addingStdioServer(name: "new", command: "npx", arguments: ["-y", "x"], to: root)
    #expect(CursorMCPServers.servers(from: added).map(\.name) == ["keep", "new"])

    let removed = CursorMCPServers.removing(name: "new", from: added)
    #expect(CursorMCPServers.servers(from: removed).map(\.name) == ["keep"])
}

@Test("コマンド文字列を実行ファイルと引数へ割る")
func cursorMCPServers_splitsCommand() {
    let parsed = CursorMCPServers.splitCommand("  npx -y some-server  ")
    #expect(parsed?.command == "npx")
    #expect(parsed?.arguments == ["-y", "some-server"])
    #expect(CursorMCPServers.splitCommand("   ") == nil)
}

// MARK: - 状態

@Test("cli-config.json から状態サマリを組み立てる")
func cursorEnvironmentStatus_buildsFromConfig() throws {
    let status = CursorEnvironmentStatusBuilder.fromConfig(try loadConfig())
    #expect(status.modelID == "composer-2.5")
    #expect(status.modelDisplayName == "Composer 2.5")
    #expect(status.approvalMode == "allowlist")
    #expect(status.sandboxMode == "disabled")
    #expect(status.allowRuleCount == 1)
    #expect(status.denyRuleCount == 0)
}

@Test("cursor-agent --version の出力から版番号を取り出す")
func cursorEnvironmentStatus_parsesVersion() {
    #expect(CursorEnvironmentStatusBuilder.parseVersion(from: "2026.07.20-8cc9c0b\n") == "2026.07.20-8cc9c0b")
    #expect(CursorEnvironmentStatusBuilder.parseVersion(from: "  ") == nil)
}
