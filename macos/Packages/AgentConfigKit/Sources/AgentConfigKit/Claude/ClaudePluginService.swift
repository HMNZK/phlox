import Foundation

/// プラグイン操作のインストール範囲。CLI の `--scope` に対応する。
public enum ClaudePluginScope: String, Sendable, CaseIterable, Identifiable {
    case user
    case project
    case local

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: return "ユーザー"
        case .project: return "プロジェクト"
        case .local: return "このマシンだけ"
        }
    }
}

/// `claude plugin ...` を叩いてプラグインを管理するサービス。
///
/// `/plugin` は対話 TUI 専用でセッションからは使えないため、Phlox は同じことを
/// この非対話サブコマンド経由で行う。
public struct ClaudePluginService: Sendable {
    private let runner: AgentCommandRunning

    public init(runner: AgentCommandRunning) {
        self.runner = runner
    }

    // MARK: - 読み取り

    public func installedPlugins() async throws -> [ClaudeInstalledPlugin] {
        let json = try await runJSON(["plugin", "list", "--json"])
        return ClaudePluginParsing.installedPlugins(from: json)
    }

    /// インストール済みとマーケットプレイスで配布中のものをまとめて取る。
    public func catalog() async throws -> (installed: [ClaudeInstalledPlugin], available: [ClaudeAvailablePlugin]) {
        let json = try await runJSON(["plugin", "list", "--available", "--json"])
        return (
            ClaudePluginParsing.installedPlugins(from: json),
            ClaudePluginParsing.availablePlugins(from: json)
        )
    }

    public func marketplaces() async throws -> [ClaudeMarketplace] {
        let json = try await runJSON(["plugin", "marketplace", "list", "--json"])
        return ClaudePluginParsing.marketplaces(from: json)
    }

    // MARK: - 変更

    public func setEnabled(_ isEnabled: Bool, pluginID: String, scope: ClaudePluginScope?) async throws {
        var arguments = ["plugin", isEnabled ? "enable" : "disable", pluginID]
        if let scope { arguments += ["--scope", scope.rawValue] }
        try await runExpectingSuccess(arguments)
    }

    public func install(pluginID: String, scope: ClaudePluginScope) async throws {
        try await runExpectingSuccess(["plugin", "install", pluginID, "--scope", scope.rawValue])
    }

    /// アンインストール。`--yes` は TTY が無い環境で確認プロンプトに固まらないために必須。
    public func uninstall(pluginID: String, scope: ClaudePluginScope) async throws {
        try await runExpectingSuccess(["plugin", "uninstall", pluginID, "--scope", scope.rawValue, "--yes"])
    }

    public func update(pluginID: String, scope: ClaudePluginScope) async throws {
        try await runExpectingSuccess(["plugin", "update", pluginID, "--scope", scope.rawValue])
    }

    public func addMarketplace(source: String) async throws {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await runExpectingSuccess(["plugin", "marketplace", "add", trimmed])
    }

    public func removeMarketplace(name: String) async throws {
        try await runExpectingSuccess(["plugin", "marketplace", "remove", name])
    }

    public func updateMarketplaces() async throws {
        try await runExpectingSuccess(["plugin", "marketplace", "update"])
    }

    // MARK: - 実行の共通処理

    private func runJSON(_ arguments: [String]) async throws -> JSONValue {
        let result = try await runner.run(arguments)
        guard result.succeeded else { throw AgentCommandError.failed(result) }
        guard let data = AgentCommandOutput.jsonPayload(from: result.standardOutput) else {
            throw AgentCommandError.unreadableOutput("claude")
        }
        do {
            return try JSONValueCoder.decode(data)
        } catch {
            throw AgentCommandError.unreadableOutput("claude")
        }
    }

    private func runExpectingSuccess(_ arguments: [String]) async throws {
        let result = try await runner.run(arguments)
        guard result.succeeded else { throw AgentCommandError.failed(result) }
    }
}
