import Foundation

/// ダッシュボードで管理できる CLI エージェントの種類。
public enum AgentKind: String, CaseIterable, Sendable, Identifiable, Codable {
    case claudeCode
    case codex
    case cursor

    public var id: String { rawValue }

    /// UI に表示する名前。
    public var displayName: String {
        AgentRegistry.descriptor(for: self).displayName
    }

    /// PATH 上で解決する実行ファイル名。
    public var binaryName: String {
        AgentRegistry.descriptor(for: self).binaryName
    }

    /// UI のメニュー / バッジで使う SF Symbols 名。
    public var symbolName: String {
        AgentRegistry.descriptor(for: self).symbolName
    }
}
