import Foundation

/// `codex mcp list --json` の1件。
public struct CodexMCPServer: Sendable, Equatable, Identifiable {
    public let name: String
    public let isEnabled: Bool
    public let disabledReason: String?
    /// `stdio` / `streamable_http` など。
    public let transportType: String?
    /// stdio なら実行コマンド、HTTP なら URL。
    public let endpoint: String?
    public let authStatus: String?

    public var id: String { name }

    public init(
        name: String,
        isEnabled: Bool,
        disabledReason: String?,
        transportType: String?,
        endpoint: String?,
        authStatus: String?
    ) {
        self.name = name
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.transportType = transportType
        self.endpoint = endpoint
        self.authStatus = authStatus
    }
}

enum CodexMCPParsing {
    static func servers(from json: JSONValue) -> [CodexMCPServer] {
        (json.arrayValue ?? []).compactMap { item in
            guard let name = item["name"]?.stringValue else { return nil }
            let transport = item["transport"]
            let command = transport?["command"]?.stringValue
            let args = transport?["args"]?.stringArrayValue ?? []
            let endpoint = transport?["url"]?.stringValue
                ?? command.map { ([$0] + args).joined(separator: " ") }
            return CodexMCPServer(
                name: name,
                isEnabled: item["enabled"]?.boolValue ?? false,
                disabledReason: item["disabled_reason"]?.stringValue,
                transportType: transport?["type"]?.stringValue,
                endpoint: endpoint,
                authStatus: item["auth_status"]?.stringValue
            )
        }
    }
}

/// `codex mcp ...`（非対話）で MCP サーバーを管理するサービス。
/// 実体は `config.toml` の `[mcp_servers.*]` だが、書き込みは CLI に任せる。
public struct CodexMCPService: Sendable {
    private let runner: AgentCommandRunning

    public init(runner: AgentCommandRunning) {
        self.runner = runner
    }

    public func servers() async throws -> [CodexMCPServer] {
        let result = try await runner.run(["mcp", "list", "--json"])
        guard result.succeeded else { throw AgentCommandError.failed(result) }
        guard let data = AgentCommandOutput.jsonPayload(from: result.standardOutput) else {
            // サーバーが1つも無いとき CLI は JSON ではなく案内文だけを返す。
            return []
        }
        do {
            return CodexMCPParsing.servers(from: try JSONValueCoder.decode(data))
        } catch {
            throw AgentCommandError.unreadableOutput("codex")
        }
    }

    /// stdio 起動のサーバーを足す（`codex mcp add <name> -- <command...>`）。
    public func addStdioServer(name: String, command: [String]) async throws {
        guard !command.isEmpty else { return }
        try await runExpectingSuccess(["mcp", "add", name, "--"] + command)
    }

    /// HTTP のサーバーを足す（`codex mcp add <name> --url <url>`）。
    public func addHTTPServer(name: String, url: String) async throws {
        try await runExpectingSuccess(["mcp", "add", name, "--url", url])
    }

    public func remove(name: String) async throws {
        try await runExpectingSuccess(["mcp", "remove", name])
    }

    private func runExpectingSuccess(_ arguments: [String]) async throws {
        let result = try await runner.run(arguments)
        guard result.succeeded else { throw AgentCommandError.failed(result) }
    }
}
