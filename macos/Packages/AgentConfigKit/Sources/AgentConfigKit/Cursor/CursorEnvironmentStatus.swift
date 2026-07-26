import Foundation

/// 「いまの Cursor Agent はどうなっているか」のスナップショット。
public struct CursorEnvironmentStatus: Sendable, Equatable {
    public var cursorVersion: String?
    public var cursorExecutablePath: String
    public var configFilePath: String
    public var configFileExists: Bool
    public var mcpFilePath: String
    public var modelID: String?
    public var modelDisplayName: String?
    public var approvalMode: String?
    public var sandboxMode: String?
    public var allowRuleCount: Int
    public var denyRuleCount: Int
    public var mcpServerCount: Int

    public init(
        cursorVersion: String? = nil,
        cursorExecutablePath: String = "",
        configFilePath: String = "",
        configFileExists: Bool = false,
        mcpFilePath: String = "",
        modelID: String? = nil,
        modelDisplayName: String? = nil,
        approvalMode: String? = nil,
        sandboxMode: String? = nil,
        allowRuleCount: Int = 0,
        denyRuleCount: Int = 0,
        mcpServerCount: Int = 0
    ) {
        self.cursorVersion = cursorVersion
        self.cursorExecutablePath = cursorExecutablePath
        self.configFilePath = configFilePath
        self.configFileExists = configFileExists
        self.mcpFilePath = mcpFilePath
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.approvalMode = approvalMode
        self.sandboxMode = sandboxMode
        self.allowRuleCount = allowRuleCount
        self.denyRuleCount = denyRuleCount
        self.mcpServerCount = mcpServerCount
    }
}

public enum CursorEnvironmentStatusBuilder {
    /// `cursor-agent --version` の出力から版番号だけ取り出す。
    public static func parseVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces)
    }

    /// cli-config.json の中身から、プロセスを起動せずに分かる項目を埋める。
    public static func fromConfig(_ root: JSONValue) -> CursorEnvironmentStatus {
        let permissions = CursorPermissionRules.extract(from: root)
        return CursorEnvironmentStatus(
            modelID: CursorModelSettings.currentModelID(in: root),
            modelDisplayName: CursorModelSettings.currentDisplayName(in: root),
            approvalMode: CursorGeneralSettings.string(.approvalMode, in: root),
            sandboxMode: CursorGeneralSettings.string(.sandboxMode, in: root),
            allowRuleCount: permissions.allow.count,
            denyRuleCount: permissions.deny.count
        )
    }
}
