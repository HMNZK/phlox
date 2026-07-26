import Foundation

/// `settings.json` のような「自分が知らないキーも壊さずに持ち回りたい」JSON を扱うための値型。
///
/// `[String: Any]` のまま扱うと `Sendable` にできず、Swift 6 の並行性チェックを通せない。
/// 既知のキーだけを構造体へマップする方式も採れないので（未知キーが落ちる）、
/// JSON をそのまま表現できる列挙型を置いて、更新は「この列挙型の上の書き換え」で行う。
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - 取り出しヘルパー

public extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(exactly: value.rounded())
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// 文字列配列として読む。要素に文字列以外が混ざっていたらそれは捨てる（設定ファイルは手書きされうる）。
    var stringArrayValue: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap(\.stringValue)
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON として解釈できない値です"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - オブジェクトの部分更新

public extension JSONValue {
    /// トップレベルがオブジェクトのときに、キー1つだけを差し替えた新しい値を返す。
    /// `value` が `nil` ならそのキーを削除する。トップレベルがオブジェクトでなければ新規オブジェクトを作る。
    func settingTopLevel(_ key: String, to value: JSONValue?) -> JSONValue {
        var object = objectValue ?? [:]
        if let value {
            object[key] = value
        } else {
            object.removeValue(forKey: key)
        }
        return .object(object)
    }

    /// 入れ子のキーを辿って値を読む（`["display", "zenMode"]` など）。
    func value(at path: [String]) -> JSONValue? {
        path.reduce(self as JSONValue?) { current, key in current?[key] }
    }

    /// 入れ子のキー1つだけを差し替えた新しい値を返す。途中のオブジェクトが無ければ作る。
    /// `value` が `nil` ならそのキーを削除する（途中の空オブジェクトは残す＝他ツールの前提を壊さない）。
    func setting(_ path: [String], to value: JSONValue?) -> JSONValue {
        guard let key = path.first else { return value ?? self }
        if path.count == 1 { return settingTopLevel(key, to: value) }
        let child = self[key] ?? .object([:])
        return settingTopLevel(key, to: child.setting(Array(path.dropFirst()), to: value))
    }
}

// MARK: - シリアライズ

public enum JSONValueCoder {
    /// 設定ファイルの読み書きで使う共通のエンコーダ。キー順を固定して差分ノイズを抑える。
    public static func encode(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)  // 末尾改行（他のツールが行単位で扱えるように）
        return data
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
