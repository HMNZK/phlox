import Foundation
import Testing
import PhloxCore
import PhloxNetworking

final class DeviceTokenClientStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status: Int = 200
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset(status: Int) {
        self.status = status
        requestCount = 0
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
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

@Suite(.serialized)
struct DeviceTokenClientTests {

    private func makeClient(status: Int, token: String? = "tok") -> PhloxAPIClient {
        DeviceTokenClientStubURLProtocol.reset(status: status)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceTokenClientStubURLProtocol.self]
        return PhloxAPIClient(
            config: ConnectionConfig(host: "127.0.0.1", port: 8765),
            tokenStore: InMemoryTokenStore(token: token),
            session: URLSession(configuration: configuration),
            maxRetries: 3,
            retryBaseDelayNanos: 1
        )
    }

    private var registration: DeviceTokenRegistration {
        DeviceTokenRegistration(deviceToken: "deadbeef", bundleId: "com.phlox.mobile.PhloxMobile", environment: .production)
    }

    @Test func status201も成功として扱う() async throws {
        let client = makeClient(status: 201)
        try await client.registerDeviceToken(registration)
        #expect(DeviceTokenClientStubURLProtocol.requestCount == 1)
    }

    @Test func status400はPhloxErrorを投げる() async {
        let client = makeClient(status: 400)
        await #expect(throws: PhloxError.self) {
            try await client.registerDeviceToken(registration)
        }
        #expect(DeviceTokenClientStubURLProtocol.requestCount == 1)
    }

    @Test func トークン未設定時はAuthorizationを付けない() async throws {
        let client = makeClient(status: 200, token: nil)
        try await client.registerDeviceToken(registration)
        let request = try #require(DeviceTokenClientStubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
