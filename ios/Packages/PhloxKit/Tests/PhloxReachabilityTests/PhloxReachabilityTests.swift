import XCTest
import PhloxCore
@testable import PhloxReachability

// E3-4 検証。二層判定の純粋ロジック（resolve）と、URLProtocol スタブによる
// ホストヘルスチェック（GET /sessions の成否）を検証する。実 NWPathMonitor には依存しない。
final class PhloxReachabilityTests: XCTestCase {

    private let baseURL = URL(string: "http://100.64.0.1:8765")!

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - resolve（二層判定）

    func testResolveOfflineWhenNetworkUnsatisfied() {
        XCTAssertEqual(ReachabilityMonitor.resolve(networkSatisfied: false, healthOK: false), .offlineNetwork)
        XCTAssertEqual(ReachabilityMonitor.resolve(networkSatisfied: false, healthOK: true), .offlineNetwork)
    }

    func testResolveOnlineWhenNetworkAndHostOK() {
        XCTAssertEqual(ReachabilityMonitor.resolve(networkSatisfied: true, healthOK: true), .online)
    }

    func testResolveUnreachableHostWhenNetworkButNoHost() {
        XCTAssertEqual(ReachabilityMonitor.resolve(networkSatisfied: true, healthOK: false), .unreachableHost)
    }

    // MARK: - HostHealthChecker（URLProtocol スタブ）

    func testHealthCheckTrueOnHTTPResponse() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        let checker = HostHealthChecker(session: stubbedSession())
        let reachable = await checker.isHostReachable(baseURL: baseURL, token: "t")
        XCTAssertTrue(reachable)
    }

    func testHealthCheckTrueEvenOn401() async {
        // 401 でもホストは生きている（到達可能）。
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let checker = HostHealthChecker(session: stubbedSession())
        let reachable = await checker.isHostReachable(baseURL: baseURL, token: nil)
        XCTAssertTrue(reachable)
    }

    func testHealthCheckFalseOnTransportError() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let checker = HostHealthChecker(session: stubbedSession())
        let reachable = await checker.isHostReachable(baseURL: baseURL, token: "t")
        XCTAssertFalse(reachable)
    }

    // MARK: - 統合（health → resolve）

    func testOnlineEndToEndViaHealthCheck() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let checker = HostHealthChecker(session: stubbedSession())
        let healthOK = await checker.isHostReachable(baseURL: baseURL, token: "t")
        XCTAssertEqual(ReachabilityMonitor.resolve(networkSatisfied: true, healthOK: healthOK), .online)
    }

    func testUnreachableHostEndToEndViaHealthCheck() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let checker = HostHealthChecker(session: stubbedSession())
        let healthOK = await checker.isHostReachable(baseURL: baseURL, token: "t")
        XCTAssertEqual(ReachabilityMonitor.resolve(networkSatisfied: true, healthOK: healthOK), .unreachableHost)
    }
}

/// テスト用 URLProtocol スタブ。設定したハンドラでレスポンス/エラーを差し込む。
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
