import Foundation

/// セッションが参照する組込 CLI。
public enum AgentRef: Hashable, Sendable, Identifiable, Codable, CustomStringConvertible {
    case builtin(AgentKind)

    public init(_ kind: AgentKind) {
        self = .builtin(kind)
    }

    public var id: String {
        switch self { case .builtin(let kind): kind.rawValue }
    }

    public var builtinKind: AgentKind {
        switch self { case .builtin(let kind): kind }
    }

    public var description: String { id }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let kind = AgentKind(rawValue: raw) {
            self = .builtin(kind)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown agent kind: \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        let kind: AgentKind
        switch self { case .builtin(let value): kind = value }
        var container = encoder.singleValueContainer()
        try container.encode(kind.rawValue)
    }
}
