import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public struct SessionActivityAttributes: Codable, Equatable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let sessionId: String
        public let sessionName: String
        public let status: String
        public let summary: String

        public init(sessionId: String, sessionName: String, status: String, summary: String) {
            self.sessionId = sessionId
            self.sessionName = sessionName
            self.status = status
            self.summary = summary
        }
    }

    public let sessionId: String
    public let sessionName: String

    public init(sessionId: String, sessionName: String) {
        self.sessionId = sessionId
        self.sessionName = sessionName
    }
}

#if canImport(ActivityKit) && os(iOS)
extension SessionActivityAttributes: ActivityAttributes {}
#endif

/// Mac 側の APNs encoder と同じキーを固定するシーム契約用モデル。
public struct SessionLiveActivityPushEnvelope: Codable, Equatable, Sendable {
    public struct APS: Codable, Equatable, Sendable {
        public let timestamp: Int
        public let event: String
        public let contentState: SessionActivityAttributes.ContentState
        public let staleDate: Int
        public let dismissalDate: Int?
        public let attributesType: String?
        public let attributes: SessionActivityAttributes?

        public init(
            timestamp: Int,
            event: String,
            contentState: SessionActivityAttributes.ContentState,
            staleDate: Int,
            dismissalDate: Int? = nil,
            attributesType: String? = nil,
            attributes: SessionActivityAttributes? = nil
        ) {
            self.timestamp = timestamp
            self.event = event
            self.contentState = contentState
            self.staleDate = staleDate
            self.dismissalDate = dismissalDate
            self.attributesType = attributesType
            self.attributes = attributes
        }

        enum CodingKeys: String, CodingKey {
            case timestamp
            case event
            case contentState = "content-state"
            case staleDate = "stale-date"
            case dismissalDate = "dismissal-date"
            case attributesType = "attributes-type"
            case attributes
        }
    }

    public let aps: APS

    public init(aps: APS) {
        self.aps = aps
    }
}
