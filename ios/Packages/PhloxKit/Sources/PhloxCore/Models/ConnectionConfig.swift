/// Mac（Phlox プロキシ）への接続先（architecture.md §4 / §13）。
///
/// host/port は UserDefaults 等に保存し設定画面で変更可能なため `var`。
/// トークンは意図的に含めない —— 漏洩時被害が致命的なため Keychain（PhloxSecurity）が単独で保持する。
public struct ConnectionConfig: Sendable, Equatable {
    /// 100.64.0.1 / MagicDNS ホスト名。
    public var host: String
    /// 固定ポート（既定 8765）。背後の可変ポートは Mac 側プロキシが吸収する。
    public var port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}
