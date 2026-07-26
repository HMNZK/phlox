import Foundation
import Observation
import AgentConfigKit

/// Codex 管理画面の状態。`config.toml` の読み書きと `codex` CLI 呼び出しをここへ集める。
///
/// `config.toml` はユーザーの手書き資産なので、書き込みは必ず `CodexConfigStore`（行単位の
/// 差し替え＋控えの保存）を通す。プラグインと MCP は Phlox が TOML を組まず CLI に任せる。
@MainActor
@Observable
final class CodexConsoleModel {
    let paths: CodexConfigPaths
    private var executablePath: String?
    private var pathEnvironment: String
    private var projectDirectory: URL?

    private(set) var config = TOMLDocument(text: "")
    private(set) var status = CodexEnvironmentStatus()
    private(set) var projects: [CodexProjectTrust] = []
    private(set) var installedPlugins: [CodexInstalledPlugin] = []
    private(set) var availablePlugins: [CodexAvailablePlugin] = []
    private(set) var marketplaces: [CodexMarketplace] = []
    private(set) var mcpServers: [CodexMCPServer] = []
    private(set) var memoryFiles: [AgentMemoryFile] = []

    var isLoadingPlugins = false
    var isLoadingMCP = false
    var runningOperation: String?
    var errorMessage: String?
    var infoMessage: String?

    private let store: CodexConfigStore
    private let memory: CodexMemoryFiles

    init(
        paths: CodexConfigPaths = .live,
        executablePath: String?,
        pathEnvironment: String,
        projectDirectory: URL? = nil
    ) {
        self.paths = paths
        self.executablePath = executablePath
        self.pathEnvironment = pathEnvironment
        self.projectDirectory = projectDirectory
        self.store = CodexConfigStore(paths: paths)
        self.memory = CodexMemoryFiles(paths: paths)
    }

    var isAvailable: Bool { executablePath != nil }

    @discardableResult
    func updateEnvironment(
        executablePath: String?,
        pathEnvironment: String,
        projectDirectory: URL?
    ) -> Bool {
        let changed = self.executablePath != executablePath
            || self.pathEnvironment != pathEnvironment
            || self.projectDirectory != projectDirectory
        guard changed else { return false }
        self.executablePath = executablePath
        self.pathEnvironment = pathEnvironment
        self.projectDirectory = projectDirectory
        return true
    }

    private var runner: AgentCommandRunning? {
        guard let executablePath else { return nil }
        return AgentProcessCommandRunner(
            toolName: "codex",
            executablePath: executablePath,
            pathEnvironment: pathEnvironment
        )
    }

    private var pluginService: CodexPluginService? {
        runner.map(CodexPluginService.init(runner:))
    }

    private var mcpService: CodexMCPService? {
        runner.map(CodexMCPService.init(runner:))
    }

    // MARK: - 読み込み

    func loadConfig() {
        do {
            config = try store.load()
            errorMessage = nil
        } catch {
            config = TOMLDocument(text: "")
            errorMessage = "config.toml を読めませんでした: \(error.localizedDescription)"
        }
        projects = CodexProjectTrustSettings.entries(from: config)
        memoryFiles = memory.discover(projectDirectory: projectDirectory)
        rebuildStatus()
    }

    func loadVersion() async {
        guard let runner else { return }
        let result = try? await runner.run(["--version"])
        status.codexVersion = result.flatMap {
            CodexEnvironmentStatusBuilder.parseVersion(from: $0.standardOutput)
        }
    }

    func loadPlugins() async {
        guard let pluginService else { return }
        isLoadingPlugins = true
        defer { isLoadingPlugins = false }
        do {
            let catalog = try await pluginService.catalog()
            installedPlugins = catalog.installed
            availablePlugins = catalog.available
            marketplaces = try await pluginService.marketplaces()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        rebuildStatus()
    }

    func loadMCPServers() async {
        guard let mcpService else { return }
        isLoadingMCP = true
        defer { isLoadingMCP = false }
        do {
            mcpServers = try await mcpService.servers()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        rebuildStatus()
    }

    private func rebuildStatus() {
        var next = CodexEnvironmentStatusBuilder.fromConfig(config)
        next.codexVersion = status.codexVersion
        next.codexExecutablePath = executablePath ?? "（見つかりません）"
        next.configFilePath = store.url.path
        next.configFileExists = store.exists
        next.installedPluginCount = installedPlugins.count
        next.enabledPluginCount = installedPlugins.filter(\.isEnabled).count
        next.marketplaceCount = marketplaces.count
        next.mcpServerCount = mcpServers.count
        next.enabledMCPServerCount = mcpServers.filter(\.isEnabled).count
        next.memoryFiles = memoryFiles
        status = next
    }

    // MARK: - config.toml の書き込み

    /// 文書を書き換えて保存する。失敗したらメッセージを出し、状態は元に戻す。
    func applyConfig(_ mutate: (inout TOMLDocument) -> Void, successMessage: String) {
        let previous = config
        var updated = config
        mutate(&updated)
        do {
            let changed = try store.save(updated)
            config = updated
            projects = CodexProjectTrustSettings.entries(from: updated)
            infoMessage = changed ? successMessage : "変更はありませんでした。"
            errorMessage = nil
            rebuildStatus()
        } catch {
            config = previous
            errorMessage = "config.toml を保存できませんでした: \(error.localizedDescription)"
        }
    }

    var backupPath: String { store.backupFileURL.path }

    // MARK: - メモリ

    func readMemory(_ file: AgentMemoryFile) -> String {
        (try? memory.read(file)) ?? ""
    }

    func symlinkTarget(of file: AgentMemoryFile) -> String? {
        memory.symlinkTarget(of: file)
    }

    func writeMemory(_ text: String, to file: AgentMemoryFile) {
        do {
            try memory.write(text, to: file)
            memoryFiles = memory.discover(projectDirectory: projectDirectory)
            infoMessage = "\(file.displayPath) を保存しました。"
            errorMessage = nil
            rebuildStatus()
        } catch {
            errorMessage = "\(file.displayPath) を保存できませんでした: \(error.localizedDescription)"
        }
    }

    // MARK: - CLI 操作

    func performPluginOperation(
        _ description: String,
        _ operation: @escaping (CodexPluginService) async throws -> Void
    ) async {
        guard let pluginService else {
            errorMessage = "codex コマンドが見つかりません。"
            return
        }
        runningOperation = description
        defer { runningOperation = nil }
        do {
            try await operation(pluginService)
            infoMessage = "\(description)しました。"
            errorMessage = nil
        } catch {
            errorMessage = "\(description)できませんでした: \(error.localizedDescription)"
        }
        await loadPlugins()
        loadConfig()
    }

    func performMCPOperation(
        _ description: String,
        _ operation: @escaping (CodexMCPService) async throws -> Void
    ) async {
        guard let mcpService else {
            errorMessage = "codex コマンドが見つかりません。"
            return
        }
        runningOperation = description
        defer { runningOperation = nil }
        do {
            try await operation(mcpService)
            infoMessage = "\(description)しました。"
            errorMessage = nil
        } catch {
            errorMessage = "\(description)できませんでした: \(error.localizedDescription)"
        }
        await loadMCPServers()
        loadConfig()
    }

    func clearMessages() {
        infoMessage = nil
        errorMessage = nil
    }
}
