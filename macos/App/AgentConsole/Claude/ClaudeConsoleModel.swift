import Foundation
import Observation
import AgentConfigKit

/// 管理ウィンドウ全体の状態。設定ファイルの読み書きと `claude` CLI 呼び出しをここへ集める。
@MainActor
@Observable
final class ClaudeConsoleModel {
    let paths: ClaudeConfigPaths
    /// アプリの composition より先にこのウィンドウが復元されることがある（起動時のウィンドウ復元）。
    /// その時点では CLI パスが未解決なので、後から差し替えられるよう var で持つ。
    private var claudeExecutablePath: String?
    private var pathEnvironment: String

    private(set) var settings: JSONValue = .object([:])
    private(set) var status = ClaudeEnvironmentStatus()

    private(set) var installedPlugins: [ClaudeInstalledPlugin] = []
    private(set) var availablePlugins: [ClaudeAvailablePlugin] = []
    private(set) var marketplaces: [ClaudeMarketplace] = []

    private(set) var memoryFiles: [AgentMemoryFile] = []

    var isLoadingSettings = false
    var isLoadingPlugins = false
    /// 進行中の CLI 操作の説明（ボタンを止めて出す）。
    var runningOperation: String?
    var errorMessage: String?
    var infoMessage: String?

    private let settingsStore: JSONSettingsStore
    private let memory: ClaudeMemoryFiles
    private var projectDirectory: URL?

    init(
        paths: ClaudeConfigPaths = .live,
        claudeExecutablePath: String?,
        pathEnvironment: String,
        projectDirectory: URL? = nil
    ) {
        self.paths = paths
        self.claudeExecutablePath = claudeExecutablePath
        self.pathEnvironment = pathEnvironment
        self.projectDirectory = projectDirectory
        self.settingsStore = JSONSettingsStore(fileURL: paths.userSettingsFile)
        self.memory = ClaudeMemoryFiles(paths: paths)
    }

    var isClaudeAvailable: Bool { pluginService != nil }

    /// composition 完了後に CLI パスなどを差し替える。値が変わったときだけ true を返す
    /// （呼び出し側が再読み込みの要否を判断できるように）。
    @discardableResult
    func updateEnvironment(
        claudeExecutablePath: String?,
        pathEnvironment: String,
        projectDirectory: URL?
    ) -> Bool {
        let changed = self.claudeExecutablePath != claudeExecutablePath
            || self.pathEnvironment != pathEnvironment
            || self.projectDirectory != projectDirectory
        guard changed else { return false }
        self.claudeExecutablePath = claudeExecutablePath
        self.pathEnvironment = pathEnvironment
        self.projectDirectory = projectDirectory
        return true
    }

    private var pluginService: ClaudePluginService? {
        guard let claudeExecutablePath else { return nil }
        return ClaudePluginService(
            runner: AgentProcessCommandRunner(
                toolName: "claude",
                executablePath: claudeExecutablePath,
                pathEnvironment: pathEnvironment
            )
        )
    }

    private var commandRunner: AgentCommandRunning? {
        guard let claudeExecutablePath else { return nil }
        return AgentProcessCommandRunner(
            toolName: "claude",
            executablePath: claudeExecutablePath,
            pathEnvironment: pathEnvironment
        )
    }

    // MARK: - 読み込み

    func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        do {
            settings = try settingsStore.load()
            errorMessage = nil
        } catch {
            settings = .object([:])
            errorMessage = "settings.json を読めませんでした: \(error.localizedDescription)"
        }
        memoryFiles = memory.discover(projectDirectory: projectDirectory)
        rebuildStatus()
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

    func loadVersion() async {
        guard let commandRunner else { return }
        let result = try? await commandRunner.run(["--version"])
        status.claudeVersion = result.flatMap {
            ClaudeEnvironmentStatusBuilder.parseVersion(from: $0.standardOutput)
        }
    }

    private func rebuildStatus() {
        var next = ClaudeEnvironmentStatusBuilder.fromSettings(settings)
        next.claudeVersion = status.claudeVersion
        next.claudeExecutablePath = claudeExecutablePath ?? "（見つかりません）"
        next.settingsFilePath = settingsStore.url.path
        next.settingsFileExists = settingsStore.exists
        next.installedPluginCount = installedPlugins.count
        next.enabledPluginCount = installedPlugins.filter(\.isEnabled).count
        next.marketplaceCount = marketplaces.count
        next.memoryFiles = memoryFiles
        status = next
    }

    // MARK: - 設定の書き込み

    /// 設定ツリーを丸ごと差し替えて保存する。失敗したらメッセージを出し、状態は元に戻す。
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

    // MARK: - メモリ

    func readMemory(_ file: AgentMemoryFile) -> String {
        (try? memory.read(file)) ?? ""
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

    // MARK: - プラグイン操作

    func performPluginOperation(_ description: String, _ operation: @escaping (ClaudePluginService) async throws -> Void) async {
        guard let pluginService else {
            errorMessage = "claude コマンドが見つかりません。"
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
    }

    /// インストール済みプラグインの scope を CLI へそのまま渡せる形にする。
    func scope(for plugin: ClaudeInstalledPlugin) -> ClaudePluginScope? {
        plugin.scope.flatMap(ClaudePluginScope.init(rawValue:))
    }

    func clearMessages() {
        infoMessage = nil
        errorMessage = nil
    }
}
