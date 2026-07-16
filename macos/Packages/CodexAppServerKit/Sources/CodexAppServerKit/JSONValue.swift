import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        // Int(value) は 1e300 / NaN / ∞ / Int.max 超えで fatal error になる。
        // Int(exactly:) は表現不能・非整数を nil にし、正常整数は従来値を返す。
        return Int(exactly: value)
    }
}

extension JSONEncoder {
    static let appServer: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let appServer = JSONDecoder()
}

func encodeToJSONValue<T: Encodable & Sendable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder.appServer.encode(value)
    return try JSONDecoder.appServer.decode(JSONValue.self, from: data)
}

func decodeFromJSONValue<T: Decodable & Sendable>(_ value: JSONValue, as type: T.Type = T.self) throws -> T {
    let data = try JSONEncoder.appServer.encode(value)
    return try JSONDecoder.appServer.decode(T.self, from: data)
}
