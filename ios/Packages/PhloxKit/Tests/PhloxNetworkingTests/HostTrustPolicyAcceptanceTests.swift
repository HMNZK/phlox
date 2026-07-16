import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

/// task-3 受け入れテスト（PM 著・実装役は編集禁止）。
/// レビュー #3（CWE-319）へのクライアント側ガード（ゲート①決定）:
/// 信頼できる host（Tailscale / プライベートレンジ / loopback）以外には Bearer を送らない。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
// .serialized: TrustStubURLProtocol の static 状態（lastRequest/nextBody）を共有するため並列不可
// （URLProtocol は URLSession 経由でインスタンス注入できず static が構造的に必要）。
@Suite(.serialized)
struct HostTrustPolicyAcceptanceTests {
    @Test("Tailscale MagicDNS（*.ts.net）は信頼する")
    func allowsTailscaleMagicDNS() {
        #expect(HostTrustPolicy.allowsAuthorization(host: "mac.tail1234.ts.net"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "MAC.TAIL1234.TS.NET"), "大文字小文字を区別しない")
    }

    @Test("ts.net を騙るドメイン（ドット境界なし）は信頼しない")
    func rejectsTSNetSpoof() {
        #expect(!HostTrustPolicy.allowsAuthorization(host: "evil-ts.net"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "ts.net.evil.com"))
    }

    @Test("Tailscale CGNAT レンジ（100.64.0.0/10）は信頼する")
    func allowsTailscaleCGNAT() {
        #expect(HostTrustPolicy.allowsAuthorization(host: "100.64.0.0"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "100.64.0.1"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "100.127.255.255"))
    }

    @Test("CGNAT レンジ境界外の 100.x は信頼しない")
    func rejectsOutsideCGNAT() {
        #expect(!HostTrustPolicy.allowsAuthorization(host: "100.63.255.255"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "100.128.0.0"))
    }

    @Test("RFC1918 プライベートレンジと loopback は信頼する")
    func allowsPrivateAndLoopback() {
        #expect(HostTrustPolicy.allowsAuthorization(host: "192.168.1.5"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "10.0.0.2"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "172.16.0.9"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "172.31.255.254"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "127.0.0.1"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "localhost"))
    }

    @Test("グローバルアドレス・一般ドメインは信頼しない")
    func rejectsPublicHosts() {
        #expect(!HostTrustPolicy.allowsAuthorization(host: "example.com"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "8.8.8.8"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "203.0.113.5"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "172.32.0.1"), "172.16/12 の外")
        #expect(!HostTrustPolicy.allowsAuthorization(host: "192.169.0.1"), "192.168/16 の外")
    }

    @Test("信頼しない host への実リクエストに Authorization ヘッダーが付かない")
    func clientOmitsBearerForUntrustedHost() async throws {
        TrustStubURLProtocol.reset()
        TrustStubURLProtocol.nextBody = Data(#"{"sessions":[]}"#.utf8)
        let client = makeClient(host: "203.0.113.5")
        _ = try await client.listSessions()
        let request = try #require(TrustStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil,
                "非信頼 host にはトークンを送らない")
    }

    @Test("信頼する host への実リクエストには Authorization ヘッダーが付く")
    func clientSendsBearerForTrustedHost() async throws {
        TrustStubURLProtocol.reset()
        TrustStubURLProtocol.nextBody = Data(#"{"sessions":[]}"#.utf8)
        let client = makeClient(host: "100.64.0.1")
        _ = try await client.listSessions()
        let request = try #require(TrustStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    // MARK: - ハーネス

    private func makeClient(host: String) -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrustStubURLProtocol.self]
        return PhloxAPIClient(
            config: ConnectionConfig(host: host, port: 8765),
            tokenStore: FixedTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )
    }
}

/// 本ファイル専用の URLProtocol スタブ（NetStubURLProtocol とは独立。凍結ファイルの自己完結性のため）。
final class TrustStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var nextBody = Data()

    static func reset() {
        lastRequest = nil
        nextBody = Data()
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.nextBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct FixedTokenStore: TokenStore {
    let token: String?
    func save(_ token: String) async throws {}
    func load() async throws -> String? { token }
    func delete() async throws {}
}
