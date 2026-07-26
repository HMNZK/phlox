import Foundation
import Observation
import AgentConfigKit

/// Cursor 管理画面の状態。`cli-config.json` / `mcp.json` の読み書きと
/// `cursor-agent` 呼び出しをここへ集める。
///
/// `cli-config.json` には認証情報とキャッシュも入っているため、書き込みは常に部分更新で行い、
/// 触らないキーはそのまま残す（画面にも出さない）。
@MainActor
@Observable
final class CursorConsoleModel {
    let paths: CursorConfigPaths
    private var executablePath: String?
    private var pathEnvironment: String

    private(set) var settings: JSONValue = .object([:])
    private(set) var mcpRoot: JSONValue = .object([:])
    private(set) var status = CursorEnvironmentStatus()
    private(set) var mcpServers: [CursorMCPServer] = []
    private(set) var availableModels: [CursorModelOption] = []

    var isLoadingModels = false
    var runningOperation: String?
    var errorMessage: String?
    var infoMessage: String?

    private let settingsStore: JSONSettingsStore
    private let mcpStore: JSONSettingsStore

    init(
        paths: CursorConfigPaths = .live,
        executablePath: String?,
        pathEnvironment: String
    ) {
        self.paths = paths
        self.executablePath = executablePath
        self.pathEnvironment = pathEnvironment
        self.settingsStore = JSONSettingsStore(fileURL: paths.configFile)
        self.mcpStore = JSONSettingsStore(fileURL: paths.mcpFile)
    }

    var isAvailable: Bool { executablePath != nil }

    @discardableResult
    func updateEnvironment(executablePath: String?, pathEnvironment: String) -> Bool {
        let changed = self.executablePath != executablePath || self.pathEnvironment != pathEnvironment
        guard changed else { return false }
        self.executablePath = executablePath
        self.pathEnvironment = pathEnvironment
        return true
    }

    private var service: CursorCommandService? {
        guard let executablePath else { return nil }
        return CursorCommandService(
            runner: AgentProcessCommandRunner(
                toolName: "cursor-agent",
                executablePath: executablePath,
                pathEnvironment: pathEnvironment
            )
        )
    }

    // MARK: - 読み込み

    func loadSettings() {
        do {
            settings = try settingsStore.load()
            errorMessage = nil
        } catch {
            settings = .object([:])
            errorMessage = "cli-config.json を読めませんでした: \(error.localizedDescription)"
        }
        // mcp.json は空ファイルのことがあるので、読めなくても致命にしない。
        mcpRoot = (try? mcpStore.load()) ?? .object([:])
        mcpServers = CursorMCPServers.servers(from: mcpRoot)
        rebuildStatus()
    }

    func loadVersionAndModels() async {
        guard let service else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        if let version = try? await service.version() {
            status.cursorVersion = version
        }
        do {
            availableModels = try await service.availableModels()
        } catch {
            // モデル一覧は未ログインだと取れない。設定編集は続けられるので警告に留める。
            availableModels = []
        }
    }

    private func rebuildStatus() {
        var next = CursorEnvironmentStatusBuilder.fromConfig(settings)
        next.cursorVersion = status.cursorVersion
        next.cursorExecutablePath = executablePath ?? "（見つかりません）"
        next.configFilePath = settingsStore.url.path
        next.configFileExists = settingsStore.exists
        next.mcpFilePath = mcpStore.url.path
        next.mcpServerCount = mcpServers.count
        status = next
    }

    // MARK: - 書き込み

    func applySettings(_ transform: (JSONValue) -> JSONValue, successMessage: String) {
        let previous = settings
        let updated = transform(settings)
        do {
            try settingsStore.save(updated)
            settings = updated
            infoMessage = successMessage
            errorMessage = nil
            rebuildStatus()
        } catch {
            settings = previous
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    func applyMCP(_ transform: (JSONValue) -> JSONValue, successMessage: String) {
        let previous = mcpRoot
        let updated = transform(mcpRoot)
        do {
            try mcpStore.save(updated)
            mcpRoot = updated
            mcpServers = CursorMCPServers.servers(from: updated)
            infoMessage = successMessage
            errorMessage = nil
            rebuildStatus()
        } catch {
            mcpRoot = previous
            errorMessage = "mcp.json を保存できませんでした: \(error.localizedDescription)"
        }
    }

    func setMCPEnabled(_ enabled: Bool, name: String) async {
        guard let service else {
            errorMessage = "cursor-agent コマンドが見つかりません。"
            return
        }
        let description = enabled ? "\(name) を有効に" : "\(name) を無効に"
        runningOperation = description
        defer { runningOperation = nil }
        do {
            try await service.setMCPEnabled(enabled, name: name)
            infoMessage = "\(description)しました。"
            errorMessage = nil
        } catch {
            errorMessage = "\(description)できませんでした: \(error.localizedDescription)"
        }
    }

    func clearMessages() {
        infoMessage = nil
        errorMessage = nil
    }
}
