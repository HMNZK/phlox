import Foundation
import PhloxCore

/// 接続設定（host/port）の保存口。トークンは含めない（トークンは Keychain＝TokenStore）。
/// `@MainActor` の ViewModel 内でのみ使用するため Sendable は要求しない。
public protocol ConnectionConfigStoring {
    func save(_ config: ConnectionConfig)
    func load() -> ConnectionConfig?
}

/// UserDefaults 実装。host/port のみ保存（トークン非保存）。
public struct UserDefaultsConnectionConfigStore: ConnectionConfigStoring {
    private static let hostKey = "phlox.connection.host"
    private static let portKey = "phlox.connection.port"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ config: ConnectionConfig) {
        defaults.set(config.host, forKey: Self.hostKey)
        defaults.set(config.port, forKey: Self.portKey)
    }

    public func load() -> ConnectionConfig? {
        Self.read(from: defaults)
    }

    /// host/port を UserDefaults から読む純関数（保存済みが無ければ nil）。
    static func read(from defaults: UserDefaults) -> ConnectionConfig? {
        guard let host = defaults.string(forKey: hostKey), !host.isEmpty else { return nil }
        let port = defaults.integer(forKey: portKey)
        return ConnectionConfig(host: host, port: port == 0 ? 8765 : port)
    }

    /// `UserDefaults.standard` を**都度**読む `@Sendable` プロバイダ。
    /// 起動時に config を固定捕捉せず、保存後に再起動なしで新 host/port を反映するために使う。
    /// 未設定時は空 host（呼び出し側で到達不可として扱われる）を返す。
    public static let liveProvider: @Sendable () -> ConnectionConfig = {
        read(from: .standard) ?? ConnectionConfig(host: "", port: 8765)
    }
}

/// テスト用インメモリ実装。
public final class InMemoryConnectionConfigStore: ConnectionConfigStoring {
    private var stored: ConnectionConfig?

    public init(_ config: ConnectionConfig? = nil) {
        self.stored = config
    }

    public func save(_ config: ConnectionConfig) {
        stored = config
    }

    public func load() -> ConnectionConfig? {
        stored
    }
}
