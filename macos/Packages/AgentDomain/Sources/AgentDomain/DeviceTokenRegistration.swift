import Foundation

/// APNs デバイストークン登録の environment（契約1: `sandbox` | `production`）。
public enum DeviceTokenEnvironment: String, Codable, Equatable, Sendable {
    case sandbox
    case production
}

public enum DeviceTokenType: String, Codable, Equatable, Sendable {
    case device
    case liveActivityPushToStart = "liveactivity-push-to-start"
    case liveActivityUpdate = "liveactivity-update"
}

/// APNs デバイストークン登録（契約1の POST /device-tokens body）。
public struct DeviceTokenRegistration: Codable, Equatable, Sendable {
    public let deviceToken: String
    public let bundleId: String
    public let environment: DeviceTokenEnvironment
    public let tokenType: DeviceTokenType
    public let activityId: String?
    public let sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case deviceToken
        case bundleId
        case environment
        case tokenType
        case activityId
        case sessionId
    }

    /// hex 検証に通った場合のみ生成する。大文字 hex は正規化せず拒否する（契約1は小文字を要求）。
    public init?(
        deviceToken: String,
        bundleId: String,
        environment: DeviceTokenEnvironment,
        tokenType: DeviceTokenType = .device,
        activityId: String? = nil,
        sessionId: String? = nil
    ) {
        guard Self.isValidHexDeviceToken(deviceToken) else { return nil }
        guard tokenType != .liveActivityUpdate || (activityId != nil && sessionId != nil) else { return nil }
        self.deviceToken = deviceToken
        self.bundleId = bundleId
        self.environment = environment
        self.tokenType = tokenType
        self.activityId = activityId
        self.sessionId = sessionId
    }

    /// deviceToken が契約1どおりの hex（空でない・偶数長・`[0-9a-f]` のみ）かを検証する。
    public static func isValidHexDeviceToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.count.isMultiple(of: 2) else { return false }
        return value.allSatisfy { char in
            char >= "0" && char <= "9" || char >= "a" && char <= "f"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deviceToken = try container.decode(String.self, forKey: .deviceToken)
        guard Self.isValidHexDeviceToken(deviceToken) else {
            throw DecodingError.dataCorruptedError(
                forKey: .deviceToken,
                in: container,
                debugDescription: "deviceToken must be non-empty even-length lowercase hex"
            )
        }
        self.deviceToken = deviceToken
        self.bundleId = try container.decode(String.self, forKey: .bundleId)
        self.environment = try container.decode(DeviceTokenEnvironment.self, forKey: .environment)
        self.tokenType = try container.decodeIfPresent(DeviceTokenType.self, forKey: .tokenType) ?? .device
        self.activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        guard tokenType != .liveActivityUpdate || (activityId != nil && sessionId != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .tokenType,
                in: container,
                debugDescription: "liveactivity-update requires activityId and sessionId"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceToken, forKey: .deviceToken)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(environment, forKey: .environment)
        if tokenType != .device {
            try container.encode(tokenType, forKey: .tokenType)
        }
        try container.encodeIfPresent(activityId, forKey: .activityId)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
    }
}
