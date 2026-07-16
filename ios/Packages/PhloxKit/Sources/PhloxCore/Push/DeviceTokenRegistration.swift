import Foundation

/// POST /device-tokens の body（契約 v1 のキー名そのまま）。
public struct DeviceTokenRegistration: Codable, Equatable, Sendable {
    public let deviceToken: String
    public let bundleId: String
    public let environment: String

    public init(deviceToken: String, bundleId: String, environment: APNsEnvironment) {
        self.deviceToken = deviceToken
        self.bundleId = bundleId
        self.environment = environment.rawValue
    }
}
