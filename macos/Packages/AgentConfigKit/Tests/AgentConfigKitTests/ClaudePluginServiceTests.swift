import Foundation
import Testing
@testable import AgentConfigKit

/// `claude` を起動せずにサービスを試すためのダミー。渡された引数を記録する。
private actor StubRunner: AgentCommandRunning {
    private let responses: [String: AgentCommandResult]
    private(set) var invocations: [[String]] = []

    init(responses: [String: AgentCommandResult]) {
        self.responses = responses
    }

    func run(_ arguments: [String]) async throws -> AgentCommandResult {
        invocations.append(arguments)
        return responses[arguments.joined(separator: " ")]
            ?? AgentCommandResult(exitCode: 0, standardOutput: "", standardError: "")
    }

    func recordedInvocations() -> [[String]] { invocations }
}

private let listJSON = """
[
  {
    "id": "claude-security@claude-plugins-official",
    "version": "0.10.0",
    "scope": "user",
    "enabled": true,
    "installPath": "/Users/me/.claude/plugins/cache/x"
  },
  {
    "id": "RevenueCat@RevenueCat",
    "version": "2.0.0",
    "scope": "user",
    "enabled": false,
    "installPath": "/Users/me/.claude/plugins/cache/y",
    "mcpServers": { "RevenueCat": { "type": "http", "url": "https://example.com" } }
  }
]
"""

@Test("plugin list --json をモデルへ写す")
func pluginService_parsesInstalledPlugins() async throws {
    let runner = StubRunner(responses: [
        "plugin list --json": AgentCommandResult(exitCode: 0, standardOutput: listJSON, standardError: ""),
    ])
    let plugins = try await ClaudePluginService(runner: runner).installedPlugins()

    #expect(plugins.count == 2)
    #expect(plugins[0].pluginID == "claude-security@claude-plugins-official")
    #expect(plugins[0].name == "claude-security")
    #expect(plugins[0].marketplace == "claude-plugins-official")
    #expect(plugins[0].isEnabled)
    #expect(plugins[1].isEnabled == false)
    #expect(plugins[1].mcpServerNames == ["RevenueCat"])
}

@Test("--available の {installed, available} 形式も読める")
func pluginService_parsesCatalog() async throws {
    let json = """
    {
      "installed": \(listJSON),
      "available": [
        {
          "pluginId": "foo@official",
          "name": "foo",
          "description": "説明",
          "marketplaceName": "official"
        }
      ]
    }
    """
    let runner = StubRunner(responses: [
        "plugin list --available --json": AgentCommandResult(exitCode: 0, standardOutput: json, standardError: ""),
    ])
    let catalog = try await ClaudePluginService(runner: runner).catalog()

    #expect(catalog.installed.count == 2)
    #expect(catalog.available.count == 1)
    #expect(catalog.available[0].id == "foo@official")
    #expect(catalog.available[0].description == "説明")
}

@Test("marketplace list --json をモデルへ写す")
func pluginService_parsesMarketplaces() async throws {
    let json = """
    [{"name":"official","source":"github","repo":"anthropics/claude-plugins-official","installLocation":"/tmp/x"}]
    """
    let runner = StubRunner(responses: [
        "plugin marketplace list --json": AgentCommandResult(exitCode: 0, standardOutput: json, standardError: ""),
    ])
    let marketplaces = try await ClaudePluginService(runner: runner).marketplaces()

    #expect(marketplaces.count == 1)
    #expect(marketplaces[0].name == "official")
    #expect(marketplaces[0].originDescription == "github: anthropics/claude-plugins-official")
}

@Test("有効化・無効化・削除で CLI に渡す引数が正しい")
func pluginService_buildsExpectedArguments() async throws {
    let runner = StubRunner(responses: [:])
    let service = ClaudePluginService(runner: runner)

    try await service.setEnabled(true, pluginID: "a@b", scope: .user)
    try await service.setEnabled(false, pluginID: "a@b", scope: nil)
    try await service.uninstall(pluginID: "a@b", scope: .user)
    try await service.install(pluginID: "c@d", scope: .project)
    try await service.update(pluginID: "a@b", scope: .user)

    let calls = await runner.recordedInvocations()
    #expect(calls[0] == ["plugin", "enable", "a@b", "--scope", "user"])
    #expect(calls[1] == ["plugin", "disable", "a@b"])
    // TTY が無いので確認プロンプトに固まらないよう --yes が要る。
    #expect(calls[2] == ["plugin", "uninstall", "a@b", "--scope", "user", "--yes"])
    #expect(calls[3] == ["plugin", "install", "c@d", "--scope", "project"])
    #expect(calls[4] == ["plugin", "update", "a@b", "--scope", "user"])
}

@Test("同じプラグインが user と project の両方にあっても identity が衝突しない")
func pluginService_identityIncludesScope() async throws {
    let json = """
    [
      {"id":"a@b","scope":"user","enabled":true},
      {"id":"a@b","scope":"project","enabled":true}
    ]
    """
    let runner = StubRunner(responses: [
        "plugin list --json": AgentCommandResult(exitCode: 0, standardOutput: json, standardError: ""),
    ])
    let plugins = try await ClaudePluginService(runner: runner).installedPlugins()

    #expect(plugins.count == 2)
    #expect(plugins[0].pluginID == plugins[1].pluginID)
    #expect(plugins[0].id != plugins[1].id)
    #expect(Set(plugins.map(\.id)).count == 2)
}

@Test("CLI が失敗したら stderr を持った例外になる")
func pluginService_throwsWithStderr() async throws {
    let runner = StubRunner(responses: [
        "plugin list --json": AgentCommandResult(exitCode: 1, standardOutput: "", standardError: "boom"),
    ])
    await #expect(throws: AgentCommandError.self) {
        _ = try await ClaudePluginService(runner: runner).installedPlugins()
    }
}

@Test("stdout の先頭に進捗行が混ざっても JSON 本体を取り出す")
func pluginService_extractsJSONPayloadFromNoisyOutput() throws {
    let data = try #require(AgentCommandOutput.jsonPayload(from: "Fetching...\n[{\"id\":\"a@b\"}]\n"))
    let value = try JSONValueCoder.decode(data)
    #expect(ClaudePluginParsing.installedPlugins(from: value).map(\.pluginID) == ["a@b"])
}

@Test("JSON が1つも無い出力では nil になる")
func pluginService_jsonPayloadIsNilWithoutJSON() {
    #expect(AgentCommandOutput.jsonPayload(from: "no json here") == nil)
}
