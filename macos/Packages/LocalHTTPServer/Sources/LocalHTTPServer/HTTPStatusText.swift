import Foundation

/// ControlServer / HookServer が共有する HTTP ステータスコード→テキスト対応表。
/// 各サーバーの契約で使うコードの和集合を保持する。
public enum HTTPStatusText: Sendable {
    public static func text(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 201: "Created"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 425: "Too Early"
        case 500: "Internal Server Error"
        default: "Error"
        }
    }
}
