import Foundation

/// 接続トークンの安全な保管口（DI シーム）。
///
/// 実体は Keychain ベース（PhloxSecurity / E3-3）。トークンは漏洩時被害が致命的なため
/// `ConnectionConfig`（host/port）とは分離し、本ストアだけが保持する（architecture.md §6）。
/// Keychain アクセスはメインスレッドを避けたいため async とし、actor 実装を許容する。
public protocol TokenStore: Sendable {
    /// トークンを保存（既存があれば上書き）。
    func save(_ token: String) async throws
    /// 保存済みトークンを取得。未保存なら nil。
    func load() async throws -> String?
    /// 保存済みトークンを削除（サインアウト・接続先変更時）。
    func delete() async throws
}
