import AgentDomain
import Foundation

/// 承認待ちの 1 件（カンプ ⑦⑧）。`GET /approvals`（新設）が返す論理表現の集約モデル。
/// wire/JSON デコードは E3-1（PhloxNetworking DTO）の責務。
public struct Approval: Identifiable, Sendable, Equatable {
    public let id: String
    public let sessionID: String
    public let kind: AgentKind
    /// 「ControlServer.swift を削除し…承認しますか？」等の承認プロンプト本文。
    public let prompt: String

    public init(
        id: String,
        sessionID: String,
        kind: AgentKind,
        prompt: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.prompt = prompt
    }
}
