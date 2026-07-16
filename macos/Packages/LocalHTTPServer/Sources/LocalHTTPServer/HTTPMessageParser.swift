import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    /// 受信した request-target そのまま(query 文字列を含む)。
    /// Hook 契約は raw target での照合(旧実装の path 照合と同一挙動)に使う。
    public let target: String
    public let path: String
    public let query: [String: String]
    public let hasQuery: Bool
    public let headers: [String: String]
    public let body: Data
}

public enum HTTPMessageParserError: Error, Sendable {
    case invalidRequest
    case incomplete
    case payloadTooLarge
}

public enum HTTPMessageParser: Sendable {
    public static let maxBodyLength = 256 * 1024

    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard isComplete(data) else {
            throw HTTPMessageParserError.incomplete
        }

        if exceedsMaxBodyLength(data) {
            throw HTTPMessageParserError.payloadTooLarge
        }

        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw HTTPMessageParserError.invalidRequest
        }

        let headerData = data[..<headerEnd.lowerBound]
        let bodyStart = headerEnd.upperBound
        let body = data[bodyStart...]

        return try makeRequest(headerData: Data(headerData), body: Data(body))
    }

    /// ヘッダ部(\r\n\r\n を含まない)とボディからリクエストを構築する。
    static func makeRequest(headerData: Data, body: Data) throws -> HTTPRequest {
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw HTTPMessageParserError.invalidRequest
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            throw HTTPMessageParserError.invalidRequest
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            throw HTTPMessageParserError.invalidRequest
        }

        let method = String(parts[0])
        let rawTarget = String(parts[1])
        let target = parseTarget(rawTarget)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).lowercased()
            let valueStart = line.index(after: colon)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return HTTPRequest(
            method: method,
            target: rawTarget,
            path: target.path,
            query: target.query,
            hasQuery: target.hasQuery,
            headers: headers,
            body: body
        )
    }

    static func isComplete(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return false
        }

        let contentLength = contentLength(in: headerText) ?? 0
        if contentLength > maxBodyLength {
            return true
        }

        let bodyStart = headerEnd.upperBound
        return data.count >= bodyStart + contentLength
    }

    static func exceedsMaxBodyLength(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxBodyLength
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return false
        }

        if let contentLength = contentLength(in: headerText), contentLength > maxBodyLength {
            return true
        }

        let bodyStart = headerEnd.upperBound
        return data.count - bodyStart > maxBodyLength
    }

    static func contentLength(in headerText: String) -> Int? {
        for line in headerText.split(separator: "\r\n").dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
                // 負値(および非数)は無効として nil を返す(呼び出し側は 0 扱い)。
                // 負値を許すと bodyStart + n < buffer.count が常に成立し complete を誤判定する。
                guard let value, let n = Int(value), n >= 0 else {
                    return nil
                }
                return n
            }
        }
        return nil
    }

    private static func parseTarget(_ target: String) -> (path: String, query: [String: String], hasQuery: Bool) {
        guard let questionMark = target.firstIndex(of: "?") else {
            return (target, [:], false)
        }

        let path = String(target[..<questionMark])
        let queryStart = target.index(after: questionMark)
        let query = parseQuery(String(target[queryStart...]))
        return (path, query, true)
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]

        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = parts.first else {
                continue
            }
            let rawValue = parts.count == 2 ? String(parts[1]) : ""
            let name = String(rawName).removingPercentEncoding ?? String(rawName)
            let value = rawValue.removingPercentEncoding ?? rawValue
            result[name] = value
        }

        return result
    }
}
