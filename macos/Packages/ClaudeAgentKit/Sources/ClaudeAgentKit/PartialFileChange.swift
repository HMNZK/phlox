import Foundation

struct PartialFileChange {
    let itemId: String
    let kind: String
    private var phase = Phase.objectStart
    private var stringRole: StringRole?
    private var escaped = false
    private var token: [UInt8] = []
    private var tokenOverflow = false
    private var isFilePath = false
    private var depth = 0

    private enum Phase { case objectStart, key, colon, value, otherValue, done }
    private enum StringRole { case key, path, other }

    init(itemId: String, toolName: String) {
        self.itemId = itemId
        kind = toolName == "Write" ? "write" : "edit"
    }

    mutating func append(_ json: String) -> String? {
        for byte in json.utf8 {
            guard phase != .done else { return nil }
            if let role = stringRole {
                if role != .other, !tokenOverflow {
                    // shortcut: 64 KiB を超えるパスは完成 assistant で表示する。必要になったら上限を見直す。
                    let limit = role == .key ? 128 : 65_536
                    if token.count < limit {
                        token.append(byte)
                    } else {
                        token.removeAll(keepingCapacity: false)
                        tokenOverflow = true
                    }
                }
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    stringRole = nil
                    switch role {
                    case .key:
                        isFilePath = decodedToken() == "file_path"
                        phase = .colon
                    case .path:
                        phase = .done
                        return decodedToken()
                    case .other:
                        break
                    }
                    token.removeAll(keepingCapacity: false)
                }
                continue
            }
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
            switch phase {
            case .objectStart:
                phase = byte == 0x7B ? .key : .done
            case .key:
                guard byte == 0x22 else { phase = .done; continue }
                startString(.key)
            case .colon:
                phase = byte == 0x3A ? .value : .done
            case .value:
                if isFilePath {
                    guard byte == 0x22 else { phase = .done; continue }
                    startString(.path)
                } else {
                    phase = .otherValue
                    skipValueByte(byte)
                }
            case .otherValue:
                skipValueByte(byte)
            case .done:
                return nil
            }
        }
        return nil
    }

    private mutating func startString(_ role: StringRole) {
        stringRole = role
        escaped = false
        tokenOverflow = false
        token = role == .other ? [] : [0x22]
    }

    private mutating func skipValueByte(_ byte: UInt8) {
        switch byte {
        case 0x22:
            startString(.other)
        case 0x7B, 0x5B:
            depth += 1
        case 0x7D, 0x5D:
            if depth > 0 { depth -= 1 } else { phase = .done }
        case 0x2C where depth == 0:
            phase = .key
        default:
            break
        }
    }

    private func decodedToken() -> String? {
        guard !tokenOverflow else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(token), options: .fragmentsAllowed)) as? String
    }
}
