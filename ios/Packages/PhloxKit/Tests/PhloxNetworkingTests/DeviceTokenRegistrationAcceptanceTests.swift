import Foundation
import Testing
import PhloxCore
import PhloxNetworking

// task-1 受け入れテスト（PM 著・凍結。実装役は編集禁止 — ハーネス欠陥は PM 承認の上ハーネス部分のみ修理可）。
// POST /device-tokens の wire 契約（doc/apns-implementation-request.md v1）を URLProtocol スタブで固定する。
// 既存 NetStubURLProtocol（XCTest 側）と static 状態を共有しないよう専用スタブを持つ。

final class DeviceTokenStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status: Int = 200
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset(status: Int) {
        self.status = status
        requestCount = 0
        lastRequest = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
        Self.lastRequestBody = request.readBodyForTesting()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// URLProtocol の static 共有状態を使うため直列実行（ハーネス都合の一時措置。並列化には instance 分離が必要）
@Suite(.serialized)
struct DeviceTokenRegistrationAcceptanceTests {

    private func makeClient(status: Int) -> PhloxAPIClient {
        DeviceTokenStubURLProtocol.reset(status: status)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceTokenStubURLProtocol.self]
        return PhloxAPIClient(
            config: ConnectionConfig(host: "100.64.0.1", port: 8765),
            tokenStore: InMemoryTokenStore(token: "tok-123"),
            session: URLSession(configuration: configuration),
            maxRetries: 3,
            retryBaseDelayNanos: 1
        )
    }

    private var registration: DeviceTokenRegistration {
        DeviceTokenRegistration(deviceToken: "0aff00", bundleId: "com.phlox.mobile.PhloxMobile", environment: .sandbox)
    }

    @Test func POSTでdevice_tokensへ送る() async throws {
        let client = makeClient(status: 200)
        try await client.registerDeviceToken(registration)
        let request = try #require(DeviceTokenStubURLProtocol.lastRequest)
        #expect(request.url?.path == "/device-tokens")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func 既存APIと同じBearerを付与する() async throws {
        let client = makeClient(status: 200)
        try await client.registerDeviceToken(registration)
        let request = try #require(DeviceTokenStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
    }

    @Test func bodyは契約キーで送られる() async throws {
        let client = makeClient(status: 200)
        try await client.registerDeviceToken(registration)
        let body = try #require(DeviceTokenStubURLProtocol.lastRequestBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["deviceToken"] as? String == "0aff00")
        #expect(object["bundleId"] as? String == "com.phlox.mobile.PhloxMobile")
        #expect(object["environment"] as? String == "sandbox")
    }

    @Test func 成功判定はステータスのみでbodyに依存しない() async throws {
        // 200 + 空 body で throw しない（契約: 成否は HTTP ステータスコードのみ）
        let client = makeClient(status: 200)
        try await client.registerDeviceToken(registration)
        #expect(DeviceTokenStubURLProtocol.requestCount == 1)
    }

    @Test func 未マージの404はエラーとして投げる() async {
        // Mac 側エンドポイント未マージの間は 404（「静かに失敗」の判断は task-2 の責務）
        let client = makeClient(status: 404)
        await #expect(throws: PhloxError.self) {
            try await client.registerDeviceToken(registration)
        }
    }

    @Test func サーバエラーでも自動再試行しない() async {
        // 500 は既存 GET 系ではリトライ対象。この POST は retry: false であることを回数で固定する。
        let client = makeClient(status: 500)
        await #expect(throws: PhloxError.self) {
            try await client.registerDeviceToken(registration)
        }
        #expect(DeviceTokenStubURLProtocol.requestCount == 1, "リトライ戦略は task-2 の責務（自動再試行しない）")
    }

    @Test func ステータス401はエラーとして投げる() async {
        let client = makeClient(status: 401)
        await #expect(throws: PhloxError.self) {
            try await client.registerDeviceToken(registration)
        }
    }
}
