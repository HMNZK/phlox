import CryptoKit
import Foundation

public enum APNsEnvironment: Sendable, Equatable {
    case sandbox
    case production

    var host: String {
        switch self {
        case .sandbox:
            return "api.sandbox.push.apple.com"
        case .production:
            return "api.push.apple.com"
        }
    }
}

public struct APNsConfiguration: Sendable, Equatable {
    public let keyID: String
    public let teamID: String
    public let environment: APNsEnvironment

    public init(keyID: String, teamID: String, environment: APNsEnvironment) {
        self.keyID = keyID
        self.teamID = teamID
        self.environment = environment
    }
}

public struct APNsAuthKey: Sendable {
    let privateKey: P256.Signing.PrivateKey

    public init(pem: String) throws {
        do {
            self.privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw APNsClientError.invalidAuthKey
        }
    }
}

public enum APNsClientError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidAuthKey
    case invalidJWTEncoding
    case invalidDeviceToken
    case invalidAPNsURL
    case transportFailed(deviceTokenPrefix: String)

    public var description: String {
        switch self {
        case .invalidAuthKey:
            return "Invalid APNs auth key"
        case .invalidJWTEncoding:
            return "Unable to encode APNs provider token"
        case .invalidDeviceToken:
            return "Invalid APNs device token"
        case .invalidAPNsURL:
            return "Invalid APNs endpoint URL"
        case .transportFailed(let deviceTokenPrefix):
            return "APNs transport failed for device token \(deviceTokenPrefix)"
        }
    }
}

public actor APNsProviderTokenSigner {
    private struct CachedToken {
        let value: String
        let issuedAt: Date
    }

    private let configuration: APNsConfiguration
    private let authKey: APNsAuthKey
    private let clock: @Sendable () -> Date
    private var cachedToken: CachedToken?

    public init(
        configuration: APNsConfiguration,
        authKey: APNsAuthKey,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.authKey = authKey
        self.clock = clock
    }

    public func providerToken() throws -> String {
        let now = clock()
        if let cachedToken, now.timeIntervalSince(cachedToken.issuedAt) < 50 * 60 {
            return cachedToken.value
        }

        let token = try signToken(issuedAt: now)
        cachedToken = CachedToken(value: token, issuedAt: now)
        return token
    }

    private func signToken(issuedAt: Date) throws -> String {
        let header = JWTHeader(alg: "ES256", kid: configuration.keyID)
        let payload = JWTPayload(iss: configuration.teamID, iat: Int(issuedAt.timeIntervalSince1970))
        let encoder = JSONEncoder()
        let encodedHeader = try base64URLEncode(encoder.encode(header))
        let encodedPayload = try base64URLEncode(encoder.encode(payload))
        let signingInput = "\(encodedHeader).\(encodedPayload)"
        guard let signingData = signingInput.data(using: .utf8) else {
            throw APNsClientError.invalidJWTEncoding
        }
        let signature = try authKey.privateKey.signature(for: signingData)
        let encodedSignature = base64URLEncode(signature.rawRepresentation)
        return "\(signingInput).\(encodedSignature)"
    }
}

public protocol APNsHTTP: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAPNsHTTP: APNsHTTP {
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

public enum APNsSendResult: Sendable, Equatable, CustomStringConvertible {
    case success
    case unregistered(reason: String)
    case failure(statusCode: Int, reason: String)

    public var description: String {
        switch self {
        case .success:
            return "success"
        case .unregistered(let reason):
            return "unregistered(reason: \(reason))"
        case .failure(let statusCode, let reason):
            return "failure(statusCode: \(statusCode), reason: \(reason))"
        }
    }
}

public enum APNsPushType: String, Sendable, Equatable {
    case alert
    case liveactivity
}

public struct APNsSender: Sendable {
    private let configuration: APNsConfiguration
    private let signer: APNsProviderTokenSigner
    private let http: any APNsHTTP

    public init(
        configuration: APNsConfiguration,
        signer: APNsProviderTokenSigner,
        http: any APNsHTTP = URLSessionAPNsHTTP()
    ) {
        self.configuration = configuration
        self.signer = signer
        self.http = http
    }

    public func send(
        deviceToken: String,
        topic: String,
        collapseID: String,
        payload: Data,
        pushType: APNsPushType = .alert
    ) async throws -> APNsSendResult {
        let request = try await makeRequest(
            deviceToken: deviceToken,
            topic: topic,
            collapseID: collapseID,
            payload: payload,
            pushType: pushType
        )
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw APNsClientError.transportFailed(deviceTokenPrefix: redactedDeviceToken(deviceToken))
        }
        return responseResult(statusCode: response.statusCode, body: data)
    }

    private func makeRequest(
        deviceToken: String,
        topic: String,
        collapseID: String,
        payload: Data,
        pushType: APNsPushType
    ) async throws -> URLRequest {
        guard isValidDeviceToken(deviceToken) else {
            throw APNsClientError.invalidDeviceToken
        }
        guard let url = URL(string: "https://\(configuration.environment.host)/3/device/\(deviceToken)") else {
            throw APNsClientError.invalidAPNsURL
        }

        let token = try await signer.providerToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("bearer \(token)", forHTTPHeaderField: "authorization")
        let effectiveTopic = pushType == .liveactivity && !topic.hasSuffix(".push-type.liveactivity")
            ? "\(topic).push-type.liveactivity"
            : topic
        request.setValue(effectiveTopic, forHTTPHeaderField: "apns-topic")
        request.setValue(pushType.rawValue, forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue(collapseID, forHTTPHeaderField: "apns-collapse-id")
        return request
    }

    private func responseResult(statusCode: Int, body: Data) -> APNsSendResult {
        if statusCode == 200 {
            return .success
        }

        let reason = APNsErrorReason.decode(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        if statusCode == 410 {
            return .unregistered(reason: reason)
        }
        return .failure(statusCode: statusCode, reason: reason)
    }

    private func isValidDeviceToken(_ deviceToken: String) -> Bool {
        !deviceToken.isEmpty && deviceToken.allSatisfy(\.isHexDigit)
    }

    private func redactedDeviceToken(_ deviceToken: String) -> String {
        String(deviceToken.prefix(8))
    }
}

private struct JWTHeader: Encodable {
    let alg: String
    let kid: String
}

private struct JWTPayload: Encodable {
    let iss: String
    let iat: Int
}

private struct APNsErrorReason: Decodable {
    let reason: String

    static func decode(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(APNsErrorReason.self, from: data).reason
    }
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
