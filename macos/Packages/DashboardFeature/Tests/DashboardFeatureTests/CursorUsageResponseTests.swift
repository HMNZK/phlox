import AgentDomain
import Foundation
import SQLite3
import Testing
@testable import DashboardFeature

@Test func cursorUsageResponse_decodesPlanUsageBuckets() throws {
    let data = Data("""
    {
      "planUsage": {
        "totalPercentUsed": 15.56,
        "autoPercentUsed": 18.49,
        "apiPercentUsed": 5.8
      }
    }
    """.utf8)

    let buckets = try CursorUsageProvider.buckets(fromResponseData: data)

    #expect(buckets.map(\.id) == ["auto", "api"])
    #expect(buckets.map(\.label) == ["Auto+Composer", "API"])
    #expect(buckets.map(\.usedPercent) == [18.49, 5.8])
}

@Test func cursorUsageProvider_appNotFound_offersInstallAction() async {
    // 実在しない DB パス = Cursor 未インストール相当。
    let missing = URL(fileURLWithPath: "/tmp/phlox-cursor-absent-\(UUID().uuidString)/state.vscdb")
    let usage = await CursorUsageProvider(tokenDatabaseURL: missing, http: MockUsageHTTP(responses: [])).fetch()

    #expect(usage.kind == .cursor)
    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state for missing Cursor DB")
        return
    }
    #expect(reason == "Cursorアプリ未検出")
    // UsageSidebarView が「Cursorをインストール」ボタン(cursor.com/downloads)を出すための導線。
    #expect(usage.action == .installCursor)
}

@Test func cursorUsageProvider_http200ReturnsBuckets() async throws {
    let tokenDatabaseURL = try makeCursorTokenDatabase(accessToken: makeJWT(sub: "google-oauth2|123"))
    defer { try? FileManager.default.removeItem(at: tokenDatabaseURL.deletingLastPathComponent()) }

    let http = MockUsageHTTP(
        responses: [.status(200, Data("""
        {"planUsage":{"totalPercentUsed":15.56,"autoPercentUsed":18.49,"apiPercentUsed":5.8}}
        """.utf8))]
    )
    let usage = await CursorUsageProvider(tokenDatabaseURL: tokenDatabaseURL, http: http).fetch()

    guard case let .ok(buckets) = usage.state else {
        Issue.record("Expected Cursor usage buckets")
        return
    }
    #expect(usage.kind == .cursor)
    #expect(buckets.first { $0.id == "auto" }?.usedPercent == 18.49)
    #expect(buckets.first { $0.id == "api" }?.usedPercent == 5.8)
    #expect(http.requests.count == 1)
    let request = try #require(http.requests.first)
    #expect(request.url?.absoluteString == "https://cursor.com/api/dashboard/get-current-period-usage")
    #expect(request.value(forHTTPHeaderField: "Origin") == "https://cursor.com")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Cookie")?.hasPrefix("WorkosCursorSessionToken=123%3A%3A") == true)
}

@Test func cursorUsageProvider_http401ReturnsReloginUnavailable() async throws {
    let tokenDatabaseURL = try makeCursorTokenDatabase(accessToken: makeJWT(sub: "google-oauth2|123"))
    defer { try? FileManager.default.removeItem(at: tokenDatabaseURL.deletingLastPathComponent()) }

    let usage = await CursorUsageProvider(
        tokenDatabaseURL: tokenDatabaseURL,
        http: MockUsageHTTP(responses: [.status(401, Data()), .status(401, Data())]),
        retryDelay: .milliseconds(1)
    ).fetch()

    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state")
        return
    }
    #expect(reason == "Cursorアプリで再ログインが必要")
}

@Test func cursorUsageProvider_temporaryFailureReturnsTemporaryUnavailable() async throws {
    let tokenDatabaseURL = try makeCursorTokenDatabase(accessToken: makeJWT(sub: "google-oauth2|123"))
    defer { try? FileManager.default.removeItem(at: tokenDatabaseURL.deletingLastPathComponent()) }

    let http = MockUsageHTTP(responses: [
        .throwing(URLError(.timedOut)),
        .status(503, Data()),
    ])
    let usage = await CursorUsageProvider(
        tokenDatabaseURL: tokenDatabaseURL,
        http: http,
        retryDelay: .milliseconds(1)
    ).fetch()

    guard case let .unavailable(reason) = usage.state else {
        Issue.record("Expected unavailable state")
        return
    }
    #expect(reason == "Cursorの使用量を一時的に取得できません")
    #expect(http.requests.count == 2)
}

@Test func cursorUsageProvider_retrySuccessReturnsBuckets() async throws {
    let tokenDatabaseURL = try makeCursorTokenDatabase(accessToken: makeJWT(sub: "google-oauth2|123"))
    defer { try? FileManager.default.removeItem(at: tokenDatabaseURL.deletingLastPathComponent()) }

    let http = MockUsageHTTP(responses: [
        .throwing(URLError(.timedOut)),
        .status(200, Data("""
        {"planUsage":{"totalPercentUsed":15.56,"autoPercentUsed":18.49,"apiPercentUsed":5.8}}
        """.utf8)),
    ])
    let usage = await CursorUsageProvider(
        tokenDatabaseURL: tokenDatabaseURL,
        http: http,
        retryDelay: .milliseconds(1)
    ).fetch()

    guard case let .ok(buckets) = usage.state else {
        Issue.record("Expected Cursor usage buckets")
        return
    }
    #expect(buckets.first { $0.id == "auto" }?.usedPercent == 18.49)
    #expect(http.requests.count == 2)
}

@Test func cursorUserID_decodesJWTSubject() {
    #expect(CursorUsageProvider.userID(fromAccessToken: makeJWT(sub: "google-oauth2|123")) == "123")
    #expect(CursorUsageProvider.userID(fromAccessToken: "not-a-jwt") == nil)
}

private final class MockUsageHTTP: UsageHTTP, @unchecked Sendable {
    enum Response {
        case status(Int, Data)
        case throwing(any Error)
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = lock.withLock {
            storedRequests.append(request)
            if responses.isEmpty {
                return Response.throwing(URLError(.badServerResponse))
            }
            return responses.removeFirst()
        }
        switch response {
        case .status(let statusCode, let data):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        case .throwing(let error):
            throw error
        }
    }
}

private func makeCursorTokenDatabase(accessToken: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-cursor-usage-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "state.vscdb")

    var handle: OpaquePointer?
    let result = sqlite3_open_v2(url.path(percentEncoded: false), &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard result == SQLITE_OK, let handle else {
        throw NSError(domain: "CursorUsageResponseTests", code: 1)
    }
    defer { sqlite3_close_v2(handle) }

    sqlite3_exec(handle, "CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT);", nil, nil, nil)
    var statement: OpaquePointer?
    sqlite3_prepare_v2(handle, "INSERT INTO ItemTable(key, value) VALUES('cursorAuth/accessToken', ?);", -1, &statement, nil)
    guard let statement else {
        throw NSError(domain: "CursorUsageResponseTests", code: 2)
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, accessToken, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_step(statement)
    return url
}

private func makeJWT(sub: String) -> String {
    let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
    let payload = base64URL(Data(#"{"sub":"\#(sub)"}"#.utf8))
    return "\(header).\(payload).signature"
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
