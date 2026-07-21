import AgentDomain

// SessionStatus は sibling Phlox の共有 AgentDomain（SSOT）で定義されたリッチ enum。
// ここでは再定義せず、iOS UI が必要とする「あなたの番」導出だけを拡張で足す。
public extension SessionStatus {
    /// このステータスがユーザーの操作（承認・応答）を要求するか。
    ///
    /// `.awaitingApproval` と `.awaitingUserQuestion` のみ `true`。
    /// それ以外（starting/idle/running/completed/error）は `false`。
    /// 一覧画面の「あなたの番」セクション（カンプ ②）のフィルタと、`Session.needsAttention` の
    /// 導出はすべてこの 1 箇所を経由し、判定がぶれないようにする。
    var needsAttention: Bool {
        switch self {
        case .awaitingApproval, .awaitingUserQuestion:
            return true
        default:
            return false
        }
    }
}
