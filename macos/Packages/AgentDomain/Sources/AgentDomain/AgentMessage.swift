import Foundation

public struct AgentMessage: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var fromSession: SessionID?
    public var fromName: String?
    public let toSession: SessionID
    public var toName: String?
    public let text: String
    public let submit: Bool
    public let createdAt: Date
    public var delivered: Bool
    public var inReplyTo: UUID?

    public init(
        id: UUID = UUID(),
        fromSession: SessionID? = nil,
        fromName: String? = nil,
        toSession: SessionID,
        toName: String? = nil,
        text: String,
        submit: Bool,
        createdAt: Date,
        delivered: Bool = false,
        inReplyTo: UUID? = nil
    ) {
        self.id = id
        self.fromSession = fromSession
        self.fromName = fromName
        self.toSession = toSession
        self.toName = toName
        self.text = text
        self.submit = submit
        self.createdAt = createdAt
        self.delivered = delivered
        self.inReplyTo = inReplyTo
    }
}

public enum Recipient: Sendable, Equatable {
    case id(SessionID)
    case name(String)
}
