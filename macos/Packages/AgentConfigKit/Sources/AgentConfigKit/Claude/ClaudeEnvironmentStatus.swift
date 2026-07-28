import Foundation

/// `/status` 相当の「いまの Claude Code はどうなっているか」のスナップショット。
public struct ClaudeEnvironmentStatus: Sendable, Equatable {
    public var claudeVersion: String?
    public var claudeExecutablePath: String
    public var settingsFilePath: String
    public var settingsFileExists: Bool
    public var model: String?
    public var effortLevel: String?
    public var outputStyle: String?
    public var permissionRuleCount: Int
    public var hookCount: Int
    public var installedPluginCount: Int
    public var enabledPluginCount: Int
    public var marketplaceCount: Int
    public var memoryFiles: [AgentMemoryFile]

    public init(
        claudeVersion: String? = nil,
        claudeExecutablePath: String = "",
        settingsFilePath: String = "",
        settingsFileExists: Bool = false,
        model: String? = nil,
        effortLevel: String? = nil,
        outputStyle: String? = nil,
        permissionRuleCount: Int = 0,
        hookCount: Int = 0,
        installedPluginCount: Int = 0,
        enabledPluginCount: Int = 0,
        marketplaceCount: Int = 0,
        memoryFiles: [AgentMemoryFile] = []
    ) {
        self.claudeVersion = claudeVersion
        self.claudeExecutablePath = claudeExecutablePath
        self.settingsFilePath = settingsFilePath
        self.settingsFileExists = settingsFileExists
        self.model = model
        self.effortLevel = effortLevel
        self.outputStyle = outputStyle
        self.permissionRuleCount = permissionRuleCount
        self.hookCount = hookCount
        self.installedPluginCount = installedPluginCount
        self.enabledPluginCount = enabledPluginCount
        self.marketplaceCount = marketplaceCount
        self.memoryFiles = memoryFiles
    }
}

public enum ClaudeEnvironmentStatusBuilder {
    /// `claude --version` の出力から版番号だけ取り出す（例: `2.1.220 (Claude Code)` → `2.1.220`）。
    public static func parseVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// 設定ファイルの中身から、プロセスを起動せずに分かる項目を埋める。
    public static func fromSettings(_ root: JSONValue) -> ClaudeEnvironmentStatus {
        let permissions = ClaudePermissionRules.extract(from: root)
        return ClaudeEnvironmentStatus(
            model: root["model"]?.stringValue,
            effortLevel: root["effortLevel"]?.stringValue,
            outputStyle: ClaudeOutputStyleSettings.extract(from: root),
            permissionRuleCount: permissions.allow.count + permissions.ask.count + permissions.deny.count,
            hookCount: ClaudeHookSettings.entries(from: root).count
        )
    }
}
