import CryptoKit
import Foundation
import Testing
@testable import APNsClient

@Suite struct LiveActivityPushTests {
    @Test func liveActivityHeadersUseRequiredPushTypeAndTopic() async throws {
        let http = RecordingLiveActivityHTTP()
        let configuration = APNsConfiguration(
            keyID: "KEY1234567",
            teamID: "TEAM123456",
            environment: .sandbox
        )
        let authKey = try APNsAuthKey(pem: P256.Signing.PrivateKey().pemRepresentation)
        let sender = APNsSender(
            configuration: configuration,
            signer: APNsProviderTokenSigner(configuration: configuration, authKey: authKey),
            http: http
        )

        _ = try await sender.send(
            deviceToken: "abcdef0123456789",
            topic: "com.phlox.mobile.PhloxMobile",
            collapseID: "session-123:liveactivity",
            payload: Data(#"{"aps":{"event":"update"}}"#.utf8),
            pushType: .liveactivity
        )

        let request = try #require(await http.requests.first)
        #expect(request.value(forHTTPHeaderField: "apns-push-type") == "liveactivity")
        #expect(request.value(forHTTPHeaderField: "apns-topic") == "com.phlox.mobile.PhloxMobile.push-type.liveactivity")
        #expect(request.httpBody == Data(#"{"aps":{"event":"update"}}"#.utf8))
    }
}

private actor RecordingLiveActivityHTTP: APNsHTTP {
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (
            Data(),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/2",
                headerFields: nil
            )!
        )
    }
}
