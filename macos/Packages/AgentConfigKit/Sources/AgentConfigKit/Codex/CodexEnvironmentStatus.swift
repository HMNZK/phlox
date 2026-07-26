import Foundation

/// 「いまの Codex CLI はどうなっているか」のスナップショット。
public struct CodexEnvironmentStatus: Sendable, Equatable {
    public var codexVersion: String?
    public var codexExecutablePath: String
    public var configFilePath: String
    public var configFileExists: Bool
    public var model: String?
    public var reasoningEffort: String?
    public var personality: String?
    public var approvalPolicy: String?
    public var sandboxMode: String?
    public var trustedProjectCount: Int
    public var projectCount: Int
    public var installedPluginCount: Int
    public var enabledPluginCount: Int
    public var marketplaceCount: Int
    public var mcpServerCount: Int
    public var enabledMCPServerCount: Int
    public var memoryFiles: [AgentMemoryFile]

    public init(
        codexVersion: String? = nil,
        codexExecutablePath: String = "",
        configFilePath: String = "",
        configFileExists: Bool = false,
        model: String? = nil,
        reasoningEffort: String? = nil,
        personality: String? = nil,
        approvalPolicy: String? = nil,
        sandboxMode: String? = nil,
        trustedProjectCount: Int = 0,
        projectCount: Int = 0,
        installedPluginCount: Int = 0,
        enabledPluginCount: Int = 0,
        marketplaceCount: Int = 0,
        mcpServerCount: Int = 0,
        enabledMCPServerCount: Int = 0,
        memoryFiles: [AgentMemoryFile] = []
    ) {
        self.codexVersion = codexVersion
        self.codexExecutablePath = codexExecutablePath
        self.configFilePath = configFilePath
        self.configFileExists = configFileExists
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.personality = personality
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
        self.trustedProjectCount = trustedProjectCount
        self.projectCount = projectCount
        self.installedPluginCount = installedPluginCount
        self.enabledPluginCount = enabledPluginCount
        self.marketplaceCount = marketplaceCount
        self.mcpServerCount = mcpServerCount
        self.enabledMCPServerCount = enabledMCPServerCount
        self.memoryFiles = memoryFiles
    }
}

public enum CodexEnvironmentStatusBuilder {
    /// `codex --version` の出力から版番号だけ取り出す（例: `codex-cli 0.144.6` → `0.144.6`）。
    public static func parseVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ")
        return parts.count >= 2 ? String(parts[1]) : String(parts[0])
    }

    /// `config.toml` の中身から、プロセスを起動せずに分かる項目を埋める。
    public static func fromConfig(_ document: TOMLDocument) -> CodexEnvironmentStatus {
        let projects = CodexProjectTrustSettings.entries(from: document)
        return CodexEnvironmentStatus(
            model: CodexGeneralSettings.value(.model, in: document),
            reasoningEffort: CodexGeneralSettings.value(.modelReasoningEffort, in: document),
            personality: CodexGeneralSettings.value(.personality, in: document),
            approvalPolicy: CodexGeneralSettings.value(.approvalPolicy, in: document),
            sandboxMode: CodexGeneralSettings.value(.sandboxMode, in: document),
            trustedProjectCount: projects.filter(\.isTrusted).count,
            projectCount: projects.count
        )
    }
}
