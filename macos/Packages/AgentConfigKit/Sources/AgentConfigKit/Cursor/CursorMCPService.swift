import Foundation

/// `cursor-agent ...`（非対話）を叩くサービス。
///
/// 一覧は JSON ファイル（`mcp.json` / `cli-config.json`）を直接読むほうが確実なので、
/// ここは「CLI にしかできないこと」だけを担う——モデル一覧の取得と MCP の有効・無効。
public struct CursorCommandService: Sendable {
    private let runner: AgentCommandRunning

    public init(runner: AgentCommandRunning) {
        self.runner = runner
    }

    public func version() async throws -> String? {
        let result = try await runner.run(["--version"])
        guard result.succeeded else { throw AgentCommandError.failed(result) }
        return CursorEnvironmentStatusBuilder.parseVersion(from: result.standardOutput)
    }

    public func availableModels() async throws -> [CursorModelOption] {
        let result = try await runner.run(["models"])
        guard result.succeeded else { throw AgentCommandError.failed(result) }
        return CursorModelSettings.parseModels(from: result.standardOutput)
    }

    public func setMCPEnabled(_ enabled: Bool, name: String) async throws {
        let result = try await runner.run(["mcp", enabled ? "enable" : "disable", name])
        guard result.succeeded else { throw AgentCommandError.failed(result) }
    }
}
