import Foundation

/// セッションが参照する CLI。組込 AgentKind と JSON 由来カスタム CLI を分離して扱う。
public enum AgentRef: Hashable, Sendable, Identifiable, Codable, CustomStringConvertible {
    case builtin(AgentKind)
    case custom(String)

    public init(_ kind: AgentKind) {
        self = .builtin(kind)
    }

    public var id: String {
        switch self {
        case .builtin(let kind):
            kind.rawValue
        case .custom(let id):
            id
        }
    }

    public var builtinKind: AgentKind? {
        if case .builtin(let kind) = self {
            kind
        } else {
            nil
        }
    }

    public var description: String { id }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let type = try? keyed.decode(String.self, forKey: .type),
           type == "custom" {
            let id = try keyed.decode(String.self, forKey: .id)
            self = .custom(id)
            return
        }

        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let kind = AgentKind(rawValue: raw) {
            self = .builtin(kind)
        } else {
            self = .custom(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .builtin(let kind):
            var container = encoder.singleValueContainer()
            try container.encode(kind.rawValue)
        case .custom(let id):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("custom", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }
}
