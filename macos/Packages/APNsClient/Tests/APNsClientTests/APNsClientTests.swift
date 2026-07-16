import CryptoKit
import Foundation
import Testing
@testable import APNsClient

@Suite("APNs provider token")
struct APNsProviderTokenTests {
    @Test("JWT contains ES256 claims and verifies with public key")
    func jwtStructureAndSignatureVerifyWithPublicKey() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let authKey = try APNsAuthKey(pem: privateKey.pemRepresentation)
        let configuration = APNsConfiguration(
            keyID: "KEY1234567",
            teamID: "TEAM123456",
            environment: .sandbox
        )
        let signer = APNsProviderTokenSigner(
            configuration: configuration,
            authKey: authKey,
            clock: { Date(timeIntervalSince1970: 1_700_000_123) }
        )

        let token = try await signer.providerToken()
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        for part in parts {
            #expect(part.contains("=") == false)
            #expect(part.range(of: #"[+/]"#, options: .regularExpression) == nil)
        }

        let headerData = try #require(base64URLDecode(parts[0]))
        let payloadData = try #require(base64URLDecode(parts[1]))
        let signatureData = try #require(base64URLDecode(parts[2]))
        let header = try JSONSerialization.jsonObject(with: headerData) as? [String: String]
        let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]

        #expect(header?["alg"] == "ES256")
        #expect(header?["kid"] == "KEY1234567")
        #expect(payload?["iss"] as? String == "TEAM123456")
        #expect(payload?["iat"] as? Int == 1_700_000_123)
        #expect(signatureData.count == 64)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        let signingInput = "\(parts[0]).\(parts[1])"
        let inputData = try #require(signingInput.data(using: .utf8))
        #expect(privateKey.publicKey.isValidSignature(signature, for: inputData))
    }

    @Test("JWT is cached for 50 minutes using injected clock")
    func jwtCachingUsesFiftyMinuteWindow() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let authKey = try APNsAuthKey(pem: privateKey.pemRepresentation)
        let configuration = APNsConfiguration(
            keyID: "KEY1234567",
            teamID: "TEAM123456",
            environment: .production
        )
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let signer = APNsProviderTokenSigner(
            configuration: configuration,
            authKey: authKey,
            clock: { clock.now }
        )

        let first = try await signer.providerToken()
        clock.now = Date(timeIntervalSince1970: 1_700_000_000 + 49 * 60 + 59)
        let cached = try await signer.providerToken()
        clock.now = Date(timeIntervalSince1970: 1_700_000_000 + 50 * 60)
        let refreshed = try await signer.providerToken()

        #expect(cached == first)
        #expect(refreshed != first)
    }
}

@Suite("APNs sender")
struct APNsSenderTests {
    @Test("send posts to sandbox with required headers and unchanged body")
    func sendUsesSandboxHostHeadersAndBody() async throws {
        let payload = Data(#"{"aps":{"alert":{"title":"t","body":"b"}}}"#.utf8)
        let http = FakeAPNsHTTP(responses: [
            .init(statusCode: 200, body: Data()),
        ])
        let signer = try makeSigner(environment: .sandbox)
        let sender = APNsSender(configuration: .test(environment: .sandbox), signer: signer, http: http)

        let result = try await sender.send(
            deviceToken: "abcdef0123456789",
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:approval_pending",
            payload: payload
        )

        let request = try #require(await http.requests.first)
        #expect(result == .success)
        #expect(request.url?.host == "api.sandbox.push.apple.com")
        #expect(request.url?.path == "/3/device/abcdef0123456789")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apns-topic") == "com.example.PhloxMobile")
        #expect(request.value(forHTTPHeaderField: "apns-push-type") == "alert")
        #expect(request.value(forHTTPHeaderField: "apns-priority") == "10")
        #expect(request.value(forHTTPHeaderField: "apns-collapse-id") == "session-1:approval_pending")
        #expect(request.value(forHTTPHeaderField: "authorization")?.hasPrefix("bearer ") == true)
        #expect(request.httpBody == payload)
    }

    @Test("send posts to production host")
    func sendUsesProductionHost() async throws {
        let http = FakeAPNsHTTP(responses: [
            .init(statusCode: 200, body: Data()),
        ])
        let signer = try makeSigner(environment: .production)
        let sender = APNsSender(configuration: .test(environment: .production), signer: signer, http: http)

        _ = try await sender.send(
            deviceToken: "abcdef0123456789",
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:session_completed",
            payload: Data("{}".utf8)
        )

        let request = try #require(await http.requests.first)
        #expect(request.url?.host == "api.push.apple.com")
    }

    @Test("send maps 200 and 410 responses to dedicated results")
    func sendMapsSuccessAndUnregistered() async throws {
        let http = FakeAPNsHTTP(responses: [
            .init(statusCode: 200, body: Data()),
            .init(statusCode: 410, body: Data(#"{"reason":"Unregistered"}"#.utf8)),
        ])
        let signer = try makeSigner(environment: .sandbox)
        let sender = APNsSender(configuration: .test(environment: .sandbox), signer: signer, http: http)

        let success = try await sender.send(
            deviceToken: "abcdef0123456789",
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:approval_pending",
            payload: Data("{}".utf8)
        )
        let unregistered = try await sender.send(
            deviceToken: "abcdef0123456789",
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:approval_pending",
            payload: Data("{}".utf8)
        )

        #expect(success == .success)
        #expect(unregistered == .unregistered(reason: "Unregistered"))
    }

    @Test("send reports non-success APNs reason without leaking the full token")
    func sendMapsFailureReasonWithoutFullToken() async throws {
        let fullToken = "abcdef0123456789abcdef0123456789"
        let http = FakeAPNsHTTP(responses: [
            .init(statusCode: 403, body: Data(#"{"reason":"InvalidProviderToken"}"#.utf8)),
        ])
        let signer = try makeSigner(environment: .sandbox)
        let sender = APNsSender(configuration: .test(environment: .sandbox), signer: signer, http: http)

        let result = try await sender.send(
            deviceToken: fullToken,
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:approval_pending",
            payload: Data("{}".utf8)
        )

        #expect(result == .failure(statusCode: 403, reason: "InvalidProviderToken"))
        #expect(String(describing: result).contains(fullToken) == false)
    }

    @Test("transport errors do not leak the full device token")
    func transportErrorDoesNotLeakFullDeviceToken() async throws {
        let fullToken = "abcdef0123456789abcdef0123456789"
        let http = ThrowingHTTP()
        let signer = try makeSigner(environment: .sandbox)
        let sender = APNsSender(configuration: .test(environment: .sandbox), signer: signer, http: http)

        do {
            _ = try await sender.send(
                deviceToken: fullToken,
                topic: "com.example.PhloxMobile",
                collapseID: "s:t",
                payload: Data()
            )
            Issue.record("expected throw")
        } catch {
            #expect(String(describing: error).contains(fullToken) == false)
            #expect(String(describing: error).contains("abcdef01"))
        }
    }

    @Test("429 and 5xx are failures without retry")
    func retryableStatusCodesReturnFailureWithoutRetry() async throws {
        let signer = try makeSigner(environment: .sandbox)
        let tooManyRequestsHTTP = FakeAPNsHTTP(responses: [
            .init(statusCode: 429, body: Data(#"{"reason":"TooManyRequests"}"#.utf8)),
        ])
        let serverErrorHTTP = FakeAPNsHTTP(responses: [
            .init(statusCode: 500, body: Data(#"{"reason":"InternalServerError"}"#.utf8)),
        ])

        let tooManyRequests = try await APNsSender(
            configuration: .test(environment: .sandbox),
            signer: signer,
            http: tooManyRequestsHTTP
        ).send(
            deviceToken: "abcdef0123456789",
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:approval_pending",
            payload: Data("{}".utf8)
        )
        let serverError = try await APNsSender(
            configuration: .test(environment: .sandbox),
            signer: signer,
            http: serverErrorHTTP
        ).send(
            deviceToken: "abcdef0123456789",
            topic: "com.example.PhloxMobile",
            collapseID: "session-1:approval_pending",
            payload: Data("{}".utf8)
        )

        #expect(tooManyRequests == .failure(statusCode: 429, reason: "TooManyRequests"))
        #expect(serverError == .failure(statusCode: 500, reason: "InternalServerError"))
        #expect(await tooManyRequestsHTTP.requests.count == 1)
        #expect(await serverErrorHTTP.requests.count == 1)
    }
}

private func makeSigner(environment: APNsEnvironment) throws -> APNsProviderTokenSigner {
    let privateKey = P256.Signing.PrivateKey()
    let authKey = try APNsAuthKey(pem: privateKey.pemRepresentation)
    return APNsProviderTokenSigner(
        configuration: .test(environment: environment),
        authKey: authKey,
        clock: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
}

private final class ManualClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private actor FakeAPNsHTTP: APNsHTTP {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    private let responses: [Response]
    private var index = 0
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses[index]
        index += 1
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/2",
            headerFields: nil
        )!
        return (response.body, httpResponse)
    }
}

private actor ThrowingHTTP: APNsHTTP {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw NSError(domain: "transport", code: 1, userInfo: [
            NSURLErrorFailingURLStringErrorKey: request.url!.absoluteString,
        ])
    }
}

private extension APNsConfiguration {
    static func test(environment: APNsEnvironment) -> APNsConfiguration {
        APNsConfiguration(
            keyID: "KEY1234567",
            teamID: "TEAM123456",
            environment: environment
        )
    }
}

private func base64URLDecode(_ value: String) -> Data? {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64.append(String(repeating: "=", count: padding))
    return Data(base64Encoded: base64)
}
