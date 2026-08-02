import Foundation

/// ペアリング済み、または QR 発行済みで未ペアリングの端末。
public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public let token: MobileToken
    public let requesterSessionID: SessionID
    public let issuedAt: Date
    public var pairedAt: Date?

    public init(
        id: UUID,
        name: String,
        token: MobileToken,
        requesterSessionID: SessionID,
        issuedAt: Date,
        pairedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.token = token
        self.requesterSessionID = requesterSessionID
        self.issuedAt = issuedAt
        self.pairedAt = pairedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case token
        case requesterSessionID
        case issuedAt
        case pairedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        token = MobileToken(value: try container.decode(String.self, forKey: .token))
        requesterSessionID = try container.decode(SessionID.self, forKey: .requesterSessionID)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        pairedAt = try container.decodeIfPresent(Date.self, forKey: .pairedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(token.value, forKey: .token)
        try container.encode(requesterSessionID, forKey: .requesterSessionID)
        try container.encode(issuedAt, forKey: .issuedAt)
        try container.encodeIfPresent(pairedAt, forKey: .pairedAt)
    }
}
