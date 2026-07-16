import Foundation

/// 元エラー（DecodingError / URLError 等）を Sendable・Equatable に包む薄いラッパ。
/// `PhloxError` を Sendable かつ比較可能に保つために使う（生の `any Error` は Sendable でない）。
public struct WrappedError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ error: Error) {
        self.description = String(describing: error)
    }

    public init(description: String) {
        self.description = description
    }
}

/// API・ネットワーク層のエラーを UI が回復導線を出せる粒度に正規化した統一型（E3-2）。
public enum PhloxError: Error, Sendable, Equatable {
    /// 401。トークン失効・未設定。
    case unauthorized
    /// ネットワーク到達不可・タイムアウト（圏外 / Mac スリープ）。
    case unreachable
    /// 429。`Retry-After`（秒）。
    case rateLimited(retryAfter: Int)
    /// spawn 拒否（depth 超過等、サーバ理由つき）。
    case spawnRejected(reason: String)
    /// 404。
    case notFound
    /// その他 5xx/4xx。
    case server(status: Int, message: String?)
    /// デコード失敗。
    case decoding(WrappedError)
    /// トランスポート層の失敗（URLError 等のうち unreachable に分類されないもの）。
    case transport(WrappedError)
}
