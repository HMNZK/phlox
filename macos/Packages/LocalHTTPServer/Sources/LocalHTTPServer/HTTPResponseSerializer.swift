import Foundation

/// HTTP/1.1 レスポンスの直列化。Content-Type とステータステキストは
/// 各サーバーの契約(text/plain か JSON か、対応ステータス表)を変えないよう
/// 呼び出し側が与える。
public enum HTTPResponseSerializer: Sendable {
    public static func serialize(
        statusCode: Int,
        statusText: String,
        contentType: String,
        body: Data
    ) -> Data {
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            "",
        ]
        var data = Data(headers.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }
}
