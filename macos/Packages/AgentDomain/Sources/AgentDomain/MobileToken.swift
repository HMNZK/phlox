import Foundation
import Security

/// iPhone アプリへ入力する安定したモバイル専用 Bearer トークン。
///
/// 32 バイトの暗号乱数を 64 文字の小文字 hex で表現した文字列をラップする。
/// 値は Keychain に永続化される（`MobileTokenStore` / `KeychainMobileTokenStore`）。
/// 平文を UserDefaults・ログに残さないこと（不変条件）。
public struct MobileToken: Hashable, Sendable {
    public let value: String

    /// 既存トークン文字列をラップする（Keychain からのロード用）。
    public init(value: String) {
        self.value = value
    }

    /// 32 バイトの暗号乱数から 64 文字の小文字 hex トークンを生成する。
    ///
    /// 既定では `SecRandomCopyBytes` を使う。テストでは `randomBytes` を差し込んで決定的に検証できる。
    /// `randomBytes` は要求バイト数を受け取り、その長さの `[UInt8]` を返すこと。
    public static func generate(
        randomBytes: (_ count: Int) -> [UInt8] = MobileToken.secureRandomBytes
    ) -> MobileToken {
        let bytes = randomBytes(32)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return MobileToken(value: hex)
    }

    /// `SecRandomCopyBytes` による暗号乱数バイト列。失敗時も全ゼロのまま返さず、
    /// 既存実装（DashboardViewModel.makeToken）と同じ戦略でベストエフォートに乱数を満たす。
    public static func secureRandomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes が失敗する状況は通常起こらないが、保険として
            // arc4random_buf で埋める（弱い乱数で黙って続行するより明示的なフォールバック）。
            bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, count) }
        }
        return bytes
    }
}
