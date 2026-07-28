import Foundation
import Testing
@testable import AgentConfigKit

private let configSample = """
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
personality = "pragmatic"

[projects."/Users/me/Alpha"]
trust_level = "trusted"

[projects."/Users/me/Beta"]
trust_level = "untrusted"

[features]
web_search = true

"""

// MARK: - トップレベル設定

@Test("config.toml のトップレベル設定を読み書きできる")
func codexGeneralSettings_readsAndWrites() {
    var document = TOMLDocument(text: configSample)
    #expect(CodexGeneralSettings.value(.model, in: document) == "gpt-5.6-sol")
    #expect(CodexGeneralSettings.value(.personality, in: document) == "pragmatic")
    #expect(CodexGeneralSettings.value(.sandboxMode, in: document) == nil)

    CodexGeneralSettings.setValue("workspace-write", for: .sandboxMode, in: &document)
    #expect(CodexGeneralSettings.value(.sandboxMode, in: document) == "workspace-write")
    // 既存キーは巻き添えにならない。
    #expect(CodexGeneralSettings.value(.model, in: document) == "gpt-5.6-sol")
    #expect(document.bool(at: ["features", "web_search"]) == true)
}

@Test("空文字を渡すとキーごと消えて Codex の既定に戻る")
func codexGeneralSettings_clearingRemovesKey() {
    var document = TOMLDocument(text: configSample)
    CodexGeneralSettings.setValue("   ", for: .personality, in: &document)
    #expect(CodexGeneralSettings.value(.personality, in: document) == nil)
    #expect(!document.text.contains("personality"))
}

@Test("ファイルに入っている見知らぬ値も選択肢に残す")
func codexSettingKey_keepsUnknownCurrentValue() {
    #expect(CodexSettingKey.personality.options(current: "pragmatic") == ["friendly", "pragmatic"])
    #expect(CodexSettingKey.personality.options(current: "mystery") == ["mystery", "friendly", "pragmatic"])
    #expect(CodexSettingKey.model.isEnumerated == false)
}

@Test("スナップショットは設定済みのキーだけを返す")
func codexGeneralSettings_snapshotSkipsUnsetKeys() {
    let snapshot = CodexGeneralSettings.snapshot(from: TOMLDocument(text: configSample))
    #expect(snapshot[.model] == "gpt-5.6-sol")
    #expect(snapshot[.sandboxMode] == nil)
    #expect(snapshot.count == 3)
}

// MARK: - プロジェクト信頼設定

@Test("プロジェクト信頼設定を列挙する")
func codexProjectTrust_listsEntries() {
    let entries = CodexProjectTrustSettings.entries(from: TOMLDocument(text: configSample))
    #expect(entries.map(\.path) == ["/Users/me/Alpha", "/Users/me/Beta"])
    #expect(entries[0].isTrusted)
    #expect(!entries[1].isTrusted)
}

@Test("信頼設定の切り替えは対象プロジェクトだけに効く")
func codexProjectTrust_togglesSingleProject() {
    var document = TOMLDocument(text: configSample)
    CodexProjectTrustSettings.setTrusted(false, path: "/Users/me/Alpha", in: &document)

    let entries = CodexProjectTrustSettings.entries(from: document)
    #expect(entries[0].trustLevel == "untrusted")
    #expect(entries[1].trustLevel == "untrusted")
    #expect(document.string(at: ["model"]) == "gpt-5.6-sol")
}

@Test("プロジェクト登録の削除はそのテーブルだけを消す")
func codexProjectTrust_removesEntry() {
    var document = TOMLDocument(text: configSample)
    CodexProjectTrustSettings.remove(path: "/Users/me/Alpha", in: &document)

    #expect(CodexProjectTrustSettings.entries(from: document).map(\.path) == ["/Users/me/Beta"])
    #expect(document.bool(at: ["features", "web_search"]) == true)
}

@Test("ホーム配下のパスは ~ 表記で見せる")
func codexProjectTrust_displaysTildePath() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(CodexProjectTrust(path: "/Users/me/Alpha", trustLevel: nil).displayPath(homeDirectory: home) == "~/Alpha")
    #expect(CodexProjectTrust(path: "/tmp/x", trustLevel: nil).displayPath(homeDirectory: home) == "/tmp/x")
}

// MARK: - config.toml の保存

@Test("保存時は直前の内容を控えとして残す")
func codexConfigStore_writesBackupBeforeSaving() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config.toml")
    let backupURL = directory.appendingPathComponent("config.toml.phlox-backup")
    try Data(configSample.utf8).write(to: configURL)

    let store = CodexConfigStore(fileURL: configURL, backupURL: backupURL)
    let changed = try store.update { document in
        CodexGeneralSettings.setValue("high", for: .modelReasoningEffort, in: &document)
    }

    #expect(changed)
    #expect(try String(contentsOf: backupURL, encoding: .utf8) == configSample)
    #expect(try String(contentsOf: configURL, encoding: .utf8).contains("model_reasoning_effort = \"high\""))
}

@Test("内容が変わらない保存は書き込まず、控えも潰さない")
func codexConfigStore_skipsNoOpSave() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config.toml")
    let backupURL = directory.appendingPathComponent("config.toml.phlox-backup")
    try Data(configSample.utf8).write(to: configURL)

    let store = CodexConfigStore(fileURL: configURL, backupURL: backupURL)
    let changed = try store.update { _ in }

    #expect(!changed)
    #expect(!FileManager.default.fileExists(atPath: backupURL.path))
}

@Test("設定ファイルが無くても空の文書として読める")
func codexConfigStore_loadsEmptyWhenMissing() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = CodexConfigStore(
        fileURL: directory.appendingPathComponent("config.toml"),
        backupURL: directory.appendingPathComponent("config.toml.phlox-backup")
    )
    #expect(!store.exists)
    #expect(try store.load().text.isEmpty)
}

// MARK: - CLI 出力の解釈

@Test("codex plugin list --json をモデルへ写す")
func codexPluginParsing_readsCatalog() throws {
    let json = """
    {
      "installed": [
        {
          "pluginId": "documents@openai-primary-runtime",
          "name": "documents",
          "marketplaceName": "openai-primary-runtime",
          "version": "26.709.11516",
          "enabled": true
        }
      ],
      "available": [
        {"pluginId": "pdf@official", "name": "pdf", "marketplaceName": "official", "description": "PDF を読む"}
      ]
    }
    """
    let value = try JSONValueCoder.decode(Data(json.utf8))

    let installed = CodexPluginParsing.installedPlugins(from: value)
    #expect(installed.count == 1)
    #expect(installed[0].name == "documents")
    #expect(installed[0].version == "26.709.11516")
    #expect(installed[0].isEnabled)

    let available = CodexPluginParsing.availablePlugins(from: value)
    #expect(available.map(\.pluginID) == ["pdf@official"])
    #expect(available[0].description == "PDF を読む")
}

@Test("codex plugin marketplace list --json をモデルへ写す")
func codexPluginParsing_readsMarketplaces() throws {
    let json = """
    {"marketplaces":[{"name":"official","root":"/tmp/root","marketplaceSource":{"sourceType":"local","source":"/tmp/src"}}]}
    """
    let marketplaces = CodexPluginParsing.marketplaces(from: try JSONValueCoder.decode(Data(json.utf8)))
    #expect(marketplaces.count == 1)
    #expect(marketplaces[0].name == "official")
    #expect(marketplaces[0].originDescription == "/tmp/src")
}

@Test("codex mcp list --json の stdio と HTTP を両方読める")
func codexMCPParsing_readsBothTransports() throws {
    let json = """
    [
      {"name":"local","enabled":false,"disabled_reason":"手動で無効","transport":{"type":"stdio","command":"./tool","args":["mcp"]},"auth_status":"unsupported"},
      {"name":"github","enabled":true,"disabled_reason":null,"transport":{"type":"streamable_http","url":"https://example.com/mcp"},"auth_status":"ok"}
    ]
    """
    let servers = CodexMCPParsing.servers(from: try JSONValueCoder.decode(Data(json.utf8)))

    #expect(servers.count == 2)
    #expect(servers[0].endpoint == "./tool mcp")
    #expect(!servers[0].isEnabled)
    #expect(servers[0].disabledReason == "手動で無効")
    #expect(servers[1].endpoint == "https://example.com/mcp")
    #expect(servers[1].isEnabled)
}

@Test("codex --version の出力から版番号だけ取り出す")
func codexEnvironmentStatus_parsesVersion() {
    #expect(CodexEnvironmentStatusBuilder.parseVersion(from: "codex-cli 0.144.6\n") == "0.144.6")
    #expect(CodexEnvironmentStatusBuilder.parseVersion(from: "0.9.0") == "0.9.0")
    #expect(CodexEnvironmentStatusBuilder.parseVersion(from: "  ") == nil)
}

@Test("config.toml から状態サマリを組み立てる")
func codexEnvironmentStatus_buildsFromConfig() {
    let status = CodexEnvironmentStatusBuilder.fromConfig(TOMLDocument(text: configSample))
    #expect(status.model == "gpt-5.6-sol")
    #expect(status.reasoningEffort == "medium")
    #expect(status.projectCount == 2)
    #expect(status.trustedProjectCount == 1)
    #expect(status.sandboxMode == nil)
}
