import Foundation
import LocalHTTPServer

/// Hook 契約のレスポンス形式(text/plain・対応ステータスのみ)。
/// 直列化そのものは LocalHTTPServer の serializer に委ね、
/// Content-Type とステータステキスト表だけをこちらで保持する。
enum HTTPResponseBuilder: Sendable {
    static func response(statusCode: Int, body: String = "") -> Data {
        return HTTPResponseSerializer.serialize(
            statusCode: statusCode,
            statusText: HTTPStatusText.text(for: statusCode),
            contentType: "text/plain; charset=utf-8",
            body: Data(body.utf8)
        )
    }
}
