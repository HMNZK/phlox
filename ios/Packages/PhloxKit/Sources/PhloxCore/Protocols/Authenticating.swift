import Foundation

/// 起動ゲートの生体認証（DI シーム）。
///
/// 実体は LocalAuthentication（Face ID / Touch ID、PhloxSecurity / E3-3）。
/// 起動ゲート画面（カンプ⑥ / E4-1）が、トークン読み出し前に本人確認を要求するために使う。
public protocol Authenticating: Sendable {
    /// 認証を要求する。成功すれば `true`。ユーザーキャンセルや失敗は `false` または throws で表す。
    /// - Parameter reason: システムの認証ダイアログに表示する理由文言。
    func authenticate(reason: String) async throws -> Bool
}
