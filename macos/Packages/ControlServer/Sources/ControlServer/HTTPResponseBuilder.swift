import Foundation
import LocalHTTPServer

/// テストが @testable 経由で参照する内部名(maxBodyLength 等)を
/// 共通パッケージ移設後も維持するための別名。
typealias HTTPMessageParser = LocalHTTPServer.HTTPMessageParser

/// Control 契約のレスポンス形式(application/json・対応ステータス表)。
/// 直列化そのものは LocalHTTPServer の serializer に委ね、
/// Content-Type とステータステキスト表だけをこちらで保持する。
enum HTTPResponseBuilder: Sendable {
    static func jsonResponse(statusCode: Int, body: Data = Data()) -> Data {
        HTTPResponseSerializer.serialize(
            statusCode: statusCode,
            statusText: HTTPStatusText.text(for: statusCode),
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }
}
