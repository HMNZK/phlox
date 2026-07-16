import Foundation

/// 受信ペイロードの phlox 名前空間（契約 v1）。未知キー・未知 type は前方互換で受理する。
public struct PhloxPushPayload: Equatable, Sendable {
    public enum EventType: Equatable, Sendable {
        case sessionCompleted
        case approvalPending
        case unknown(String)
    }

    public let version: Int
    public let type: EventType
    public let sessionID: String
    public let sessionName: String?

    /// UNNotification の userInfo から解釈する。phlox dict または sessionId が無ければ nil。
    public init?(userInfo: [AnyHashable: Any]) {
        guard let phlox = userInfo["phlox"] as? [String: Any] else {
            return nil
        }
        guard let sessionID = phlox["sessionId"] as? String,
              Self.isValidSessionID(sessionID) else {
            return nil
        }

        let version: Int
        if let v = phlox["v"] as? Int {
            version = v
        } else if let v = phlox["v"] as? NSNumber {
            version = v.intValue
        } else {
            version = 1
        }

        let typeString = phlox["type"] as? String ?? ""
        let eventType: EventType = switch typeString {
        case "session_completed":
            .sessionCompleted
        case "approval_pending":
            .approvalPending
        default:
            .unknown(typeString)
        }

        self.version = version
        self.type = eventType
        self.sessionID = sessionID
        self.sessionName = phlox["sessionName"] as? String
    }

    private static func isValidSessionID(_ sessionID: String) -> Bool {
        guard 1...128 ~= sessionID.utf8.count else {
            return false
        }
        return sessionID.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45
                || byte == 95
        }
    }
}
