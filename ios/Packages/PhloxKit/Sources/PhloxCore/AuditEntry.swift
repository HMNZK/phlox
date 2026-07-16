import Foundation

/// 監査ログの 1 エントリ。ファイル保存のため Codable。
/// **Bearer トークン・プロンプト本文は含めない**（`detail` は要約のみ）。
public struct AuditEntry: Sendable, Equatable, Codable {
    public let timestamp: Date
    /// 操作種別: "spawn" / "send" / "approve" / "remove" / "authFailed"。
    public let operation: String
    public let sessionID: String?
    /// 補助情報（agentKind / "len=N" / "approvalID:decision" / "cascade=N"）。本文は含めない。
    public let detail: String

    public init(timestamp: Date, operation: String, sessionID: String?, detail: String) {
        self.timestamp = timestamp
        self.operation = operation
        self.sessionID = sessionID
        self.detail = detail
    }

    /// `AuditOperation` を本文非保持のエントリへ変換する。
    public init(_ operation: AuditOperation, at timestamp: Date) {
        switch operation {
        case .spawn(let sessionID, let agentKind):
            self.init(timestamp: timestamp, operation: "spawn", sessionID: sessionID, detail: agentKind.rawValue)
        case .send(let sessionID, let summaryLength):
            // 本文は保存せず長さのみ。
            self.init(timestamp: timestamp, operation: "send", sessionID: sessionID, detail: "len=\(summaryLength)")
        case .approve(let approvalID, let decision):
            self.init(timestamp: timestamp, operation: "approve", sessionID: nil, detail: "\(approvalID):\(decision.rawValue)")
        case .remove(let sessionID, let cascadeCount):
            self.init(timestamp: timestamp, operation: "remove", sessionID: sessionID, detail: "cascade=\(cascadeCount)")
        case .authFailed:
            self.init(timestamp: timestamp, operation: "authFailed", sessionID: nil, detail: "")
        }
    }
}
