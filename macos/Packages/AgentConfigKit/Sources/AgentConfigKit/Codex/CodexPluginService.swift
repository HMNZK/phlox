import Foundation

/// `codex plugin list --json` の `installed` 1件。
public struct CodexInstalledPlugin: Sendable, Equatable, Identifiable {
    public let pluginID: String
    public let name: String
    public let marketplaceName: String?
    public let version: String?
    public let isEnabled: Bool

    public var id: String { pluginID }

    public init(pluginID: String, name: String, marketplaceName: String?, version: String?, isEnabled: Bool) {
        self.pluginID = pluginID
        self.name = name
        self.marketplaceName = marketplaceName
        self.version = version
        self.isEnabled = isEnabled
    }
}

/// マーケットプレイスにあるがまだ入れていないプラグイン。
public struct CodexAvailablePlugin: Sendable, Equatable, Identifiable {
    public let pluginID: String
    public let name: String
    public let marketplaceName: String?
    public let description: String?

    public var id: String { pluginID }

    public init(pluginID: String, name: String, marketplaceName: String?, description: String?) {
        self.pluginID = pluginID
        self.name = name
        self.marketplaceName = marketplaceName
        self.description = description
    }
}

/// `codex plugin marketplace list --json` の1件。
public struct CodexMarketplace: Sendable, Equatable, Identifiable {
    public let name: String
    public let root: String?
    public let source: String?

    public var id: String { name }

    public var originDescription: String { source ?? root ?? "—" }

    public init(name: String, root: String?, source: String?) {
        self.name = name
        self.root = root
        self.source = source
    }
}

enum CodexPluginParsing {
    static func installedPlugins(from json: JSONValue) -> [CodexInstalledPlugin] {
        (json["installed"]?.arrayValue ?? []).compactMap { item in
            guard let pluginID = item["pluginId"]?.stringValue else { return nil }
            return CodexInstalledPlugin(
                pluginID: pluginID,
                name: item["name"]?.stringValue ?? pluginID,
                marketplaceName: item["marketplaceName"]?.stringValue,
                version: item["version"]?.stringValue,
                isEnabled: item["enabled"]?.boolValue ?? false
            )
        }
    }

    static func availablePlugins(from json: JSONValue) -> [CodexAvailablePlugin] {
        (json["available"]?.arrayValue ?? []).compactMap { item in
            guard let pluginID = item["pluginId"]?.stringValue else { return nil }
            return CodexAvailablePlugin(
                pluginID: pluginID,
                name: item["name"]?.stringValue ?? pluginID,
                marketplaceName: item["marketplaceName"]?.stringValue,
                description: item["description"]?.stringValue
            )
        }
    }

    static func marketplaces(from json: JSONValue) -> [CodexMarketplace] {
        (json["marketplaces"]?.arrayValue ?? []).compactMap { item in
            guard let name = item["name"]?.stringValue else { return nil }
            return CodexMarketplace(
                name: name,
                root: item["root"]?.stringValue,
                source: item["marketplaceSource"]?["source"]?.stringValue
            )
        }
    }
}

/// `codex plugin ...`（非対話）でプラグインとマーケットプレイスを管理するサービス。
///
/// 設定の実体は `config.toml` の `[plugins.*]` / `[marketplaces.*]` だが、
/// **書き込みは必ず CLI に任せる**（Phlox が自前で TOML を組み立てない）。
public struct CodexPluginService: Sendable {
    private let runner: AgentCommandRunning

    public init(runner: AgentCommandRunning) {
        self.runner = runner
    }

    // MARK: - 読み取り

    public func catalog() async throws -> (installed: [CodexInstalledPlugin], available: [CodexAvailablePlugin]) {
        let json = try await runJSON(["plugin", "list", "--json"])
        return (
            CodexPluginParsing.installedPlugins(from: json),
            CodexPluginParsing.availablePlugins(from: json)
        )
    }

    public func marketplaces() async throws -> [CodexMarketplace] {
        let json = try await runJSON(["plugin", "marketplace", "list", "--json"])
        return CodexPluginParsing.marketplaces(from: json)
    }

    // MARK: - 変更

    public func install(pluginID: String) async throws {
        try await runExpectingSuccess(["plugin", "add", pluginID])
    }

    public func uninstall(pluginID: String) async throws {
        try await runExpectingSuccess(["plugin", "remove", pluginID])
    }

    public func addMarketplace(source: String) async throws {
        try await runExpectingSuccess(["plugin", "marketplace", "add", source])
    }

    public func removeMarketplace(name: String) async throws {
        try await runExpectingSuccess(["plugin", "marketplace", "remove", name])
    }

    public func upgradeMarketplaces() async throws {
        try await runExpectingSuccess(["plugin", "marketplace", "upgrade"])
    }

    // MARK: - 実行の共通処理

    private func runJSON(_ arguments: [String]) async throws -> JSONValue {
        let result = try await runner.run(arguments)
        guard result.succeeded else { throw AgentCommandError.failed(result) }
        guard let data = AgentCommandOutput.jsonPayload(from: result.standardOutput) else {
            throw AgentCommandError.unreadableOutput("codex")
        }
        do {
            return try JSONValueCoder.decode(data)
        } catch {
            throw AgentCommandError.unreadableOutput("codex")
        }
    }

    private func runExpectingSuccess(_ arguments: [String]) async throws {
        let result = try await runner.run(arguments)
        guard result.succeeded else { throw AgentCommandError.failed(result) }
    }
}
