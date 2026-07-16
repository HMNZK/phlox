import AgentDomain
import Foundation
import SQLite3

public protocol UsageHTTP: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionUsageHTTP: UsageHTTP {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

public final class CursorUsageProvider: UsageProvider {
    public let kind: AgentKind = .cursor

    private let tokenDatabaseURL: URL
    private let http: any UsageHTTP
    private let retryDelay: Duration

    public init(
        tokenDatabaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
        http: any UsageHTTP = URLSessionUsageHTTP()
    ) {
        self.tokenDatabaseURL = tokenDatabaseURL
        self.http = http
        self.retryDelay = .milliseconds(400)
    }

    init(
        tokenDatabaseURL: URL,
        http: any UsageHTTP,
        retryDelay: Duration
    ) {
        self.tokenDatabaseURL = tokenDatabaseURL
        self.http = http
        self.retryDelay = retryDelay
    }

    public func fetch() async -> CLIUsage {
        let now = Date()
        var lastFailure: FetchFailure?

        for attempt in 0..<2 {
            let result = await fetchOnce(updatedAt: now)
            switch result {
            case .success(let usage):
                return usage
            case .failure(.appNotFound):
                return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "Cursorアプリ未検出")), updatedAt: now, action: .installCursor)
            case .failure(.authenticationRequired):
                lastFailure = .authenticationRequired
            case .failure(.temporary):
                lastFailure = .temporary
            }

            if attempt == 0 {
                try? await Task.sleep(for: retryDelay)
            }
        }

        switch lastFailure {
        case .appNotFound:
            return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "Cursorアプリ未検出")), updatedAt: now)
        case .authenticationRequired:
            return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "Cursorアプリで再ログインが必要")), updatedAt: now)
        case .temporary, nil:
            return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "Cursorの使用量を一時的に取得できません")), updatedAt: now)
        }
    }

    private func fetchOnce(updatedAt: Date) async -> Result<CLIUsage, FetchFailure> {
        guard let accessToken = Self.readAccessToken(from: tokenDatabaseURL) else {
            return .failure(.appNotFound)
        }
        guard let userID = Self.userID(fromAccessToken: accessToken) else {
            return .failure(.authenticationRequired)
        }
        do {
            let request = Self.makeRequest(userID: userID, accessToken: accessToken)
            let (data, response) = try await http.data(for: request)
            guard response.statusCode == 200 else {
                return response.statusCode == 401 ? .failure(.authenticationRequired) : .failure(.temporary)
            }
            guard let buckets = try? Self.buckets(fromResponseData: data) else {
                return .failure(.temporary)
            }
            return .success(CLIUsage(kind: kind, state: .ok(buckets), updatedAt: updatedAt))
        } catch {
            return .failure(.temporary)
        }
    }

    static func userID(fromAccessToken accessToken: String) -> String? {
        let segments = accessToken.split(separator: ".")
        guard segments.count >= 2,
              let payloadData = base64URLDecode(String(segments[1])),
              let payload = try? JSONDecoder().decode(CursorJWTPayload.self, from: payloadData)
        else {
            return nil
        }
        return payload.sub.split(separator: "|").last.map(String.init)
    }

    static func buckets(fromResponseData data: Data) throws -> [UsageBucket] {
        let response = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        let usage = response.planUsage
        return [
            UsageBucket(id: "auto", label: "Auto+Composer", usedPercent: usage.autoPercentUsed),
            UsageBucket(id: "api", label: "API", usedPercent: usage.apiPercentUsed),
        ]
    }

    private static func makeRequest(userID: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func readAccessToken(from databaseURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: databaseURL.path(percentEncoded: false)) else {
            return nil
        }

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path(percentEncoded: false),
            &handle,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close_v2(handle)
            }
            return nil
        }
        defer { sqlite3_close_v2(handle) }

        let sql = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: cString)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }
}

private enum FetchFailure: Error, Sendable {
    case appNotFound
    case authenticationRequired
    case temporary
}

private struct CursorJWTPayload: Decodable {
    let sub: String
}

private struct CursorUsageResponse: Decodable {
    let planUsage: CursorPlanUsage
}

private struct CursorPlanUsage: Decodable {
    let autoPercentUsed: Double
    let apiPercentUsed: Double
}
