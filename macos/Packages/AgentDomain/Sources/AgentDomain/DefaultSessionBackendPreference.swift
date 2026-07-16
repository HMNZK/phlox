import Foundation

/// 新規セッションを「チャット（appServer）」「ターミナル（pty）」どちらで開くかの既定設定。
/// App 層（SettingsView の @AppStorage）と DashboardFeature の GUI spawn 経路が同じキーを参照する。
/// 未設定キーは .chat 扱い（既定でチャット起動）。API/orchestration 経路（backend 明示指定）には適用しない。
public enum DefaultSessionBackendPreference: String, CaseIterable, Sendable {
    case chat
    case terminal

    public static let storageKey = "phlox.defaultSessionBackend"

    /// 保存値から設定を読む。未設定・不明値は .chat（R5: 既定でチャット）。
    public static func stored(defaults: UserDefaults = .phloxDefaults()) -> DefaultSessionBackendPreference {
        guard let raw = defaults.string(forKey: storageKey) else { return .chat }
        return DefaultSessionBackendPreference(rawValue: raw) ?? .chat
    }

    /// 設定とエージェントの structured chat 対応から、実際に起動する SessionBackend を解決する。
    /// チャット非対応のエージェントは .pty へフォールバックする（エラーにしない）。
    public func resolveBackend(supportsStructuredChat: Bool) -> SessionBackend {
        switch self {
        case .chat:
            supportsStructuredChat ? .appServer : .pty
        case .terminal:
            .pty
        }
    }
}
