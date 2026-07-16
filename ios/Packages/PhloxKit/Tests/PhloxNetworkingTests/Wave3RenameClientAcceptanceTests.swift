import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

/// wave-3 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-1.md）。
///
/// 契約: `PhloxAPIClient.rename(sessionID:name:)` は
///   PATCH /sessions/{id} に body `{"name": String}` を送り、破壊的操作として自動再試行しない。
/// macOS 側 `PATCH /sessions/{id}`（既存・実装済み・統合テスト patchSessionRename）と一致する。
///
/// ハーネス: 他スイートと static 状態を共有しないよう**このスイート専用の URLProtocol**
/// （`RenameStubURLProtocol`）で隔離する（Ext/Trust/DeviceToken 等と同じ「1スイート=1プロトコル」方針。
/// `NetStubURLProtocol` を Task6 等と共有すると並列実行で相互汚染して flake するため）。
@Suite(.serialized) struct Wave3RenameClientAcceptanceTests {
    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    private func makeClient(maxRetries: Int = 1) -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RenameStubURLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: maxRetries,
            retryBaseDelayNanos: 1
        )
    }

    @Test func renamePatchesSessionPathWithNameBodyWithoutRetry() async throws {
        RenameStubURLProtocol.reset()
        RenameStubURLProtocol.outcomes = [.status(200, Data(), [:])]

        try await makeClient(maxRetries: 3).rename(sessionID: "sess-9", name: "新しい名前")

        #expect(RenameStubURLProtocol.requestCount == 1, "破壊的操作は自動再試行しない")
        #expect(RenameStubURLProtocol.lastRequest?.httpMethod == "PATCH")
        let path = URLComponents(
            url: try #require(RenameStubURLProtocol.lastRequest?.url),
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath
        #expect(path == "/sessions/sess-9")
        let body = try #require(RenameStubURLProtocol.lastRequestBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(object?["name"] == "新しい名前")
    }
}

/// このスイート専用の URLProtocol スタブ（static 状態を他スイートと共有しない）。
/// `StubOutcome`（PhloxNetworkingTests.swift）と `readBodyForTesting()`（URLRequestBodyReader.swift）を再利用する。
private final class RenameStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var outcomes: [StubOutcome] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset() {
        outcomes = []
        requestCount = 0
        lastRequest = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = min(RenameStubURLProtocol.requestCount, RenameStubURLProtocol.outcomes.count - 1)
        RenameStubURLProtocol.requestCount += 1
        RenameStubURLProtocol.lastRequest = request
        RenameStubURLProtocol.lastRequestBody = request.readBodyForTesting()

        guard index >= 0, RenameStubURLProtocol.outcomes.indices.contains(index) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch RenameStubURLProtocol.outcomes[index] {
        case let .status(code, data, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .error(urlError):
            client?.urlProtocol(self, didFailWithError: urlError)
        }
    }

    override func stopLoading() {}
}
