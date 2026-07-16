import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor HandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0
    let response: ControlResponse

    init(response: ControlResponse = .status(200)) {
        self.response = response
    }

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return response
    }

    var wasCalled: Bool {
        callCount > 0
    }
}

@Suite struct DeviceTokenEndpointTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    private let validBody = """
    {"deviceToken":"abcdef0123456789","bundleId":"com.phlox.mobile","environment":"sandbox"}
    """

    @Test func postDeviceTokenRoutesToRegisterDeviceToken() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            bearer: token,
            body: validBody
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        #expect(last?.requester == sessionID)
        guard case .registerDeviceToken(let registration)? = last?.action else {
            Issue.record("expected registerDeviceToken, got \(String(describing: last?.action))")
            return
        }
        #expect(registration.deviceToken == "abcdef0123456789")
        #expect(registration.bundleId == "com.phlox.mobile")
        #expect(registration.environment == .sandbox)
    }

    @Test func postDeviceTokenProductionEnvironment() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"deviceToken":"abcdef0123456789","bundleId":"com.phlox.mobile","environment":"production"}
        """
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            bearer: token,
            body: body
        )
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .registerDeviceToken(let registration)? = last?.action else {
            Issue.record("expected registerDeviceToken")
            return
        }
        #expect(registration.environment == .production)
    }

    @Test func postDeviceTokenWithoutBearerReturns401() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            body: validBody
        )
        #expect(status == 401)
        #expect(await stub.callCount == 0)
    }

    @Test func postDeviceTokenInvalidJSONReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            bearer: token,
            body: "not-json"
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postDeviceTokenMissingRequiredKeysReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            bearer: token,
            body: "{}"
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test(arguments: [
        "abc",
        "ABCDEF0123456789",
        "ghijkl",
        "",
    ])
    func postDeviceTokenInvalidHexReturns400(invalidToken: String) async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"deviceToken":"\(invalidToken)","bundleId":"com.phlox.mobile","environment":"sandbox"}
        """
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            bearer: token,
            body: body
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postDeviceTokenInvalidEnvironmentReturns400() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"deviceToken":"abcdef0123456789","bundleId":"com.phlox.mobile","environment":"staging"}
        """
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens",
            bearer: token,
            body: body
        )
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    @Test func postDeviceTokenWithQueryReturns404() async throws {
        let stub = HandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let status = try await request(
            port: port,
            method: "POST",
            path: "/device-tokens?foo=bar",
            bearer: token,
            body: validBody
        )
        #expect(status == 404)
        #expect(await stub.callCount == 0)
    }

    // MARK: - Helpers

    private func startServer(stub: HandlerStub) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store) { request in
            await stub.handle(request)
        }
        let port = try await server.start()
        return (port, server)
    }

    private func request(
        port: Int,
        method: String,
        path: String,
        bearer: String? = nil,
        body: String? = nil
    ) async throws -> Int {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = method
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = Data(body.utf8)
        }
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}
