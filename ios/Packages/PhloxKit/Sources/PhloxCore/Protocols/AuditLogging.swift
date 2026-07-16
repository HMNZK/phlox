import Foundation

/// 監査対象の操作（E3-6）。プロンプト本文は保持せず、`send` は要約長のみを残す（プライバシー保護）。
public enum AuditOperation: Sendable, Equatable {
    case spawn(sessionID: String, agentKind: AgentKind)
    /// 送信。本文は記録せず、文字数（要約長）のみ。
    case send(sessionID: String, summaryLength: Int)
    case approve(approvalID: String, decision: ApprovalDecision)
    case remove(sessionID: String, cascadeCount: Int)
    case authFailed
}

/// 重要操作の監査ログ（DI シーム / E3-6）。端末内のみ・外部送信しない。
public protocol AuditLogging: Sendable {
    func record(_ operation: AuditOperation) async
    /// 直近の記録を新しい順で最大 `limit` 件返す。
    func recentEntries(limit: Int) async -> [AuditEntry]
}
