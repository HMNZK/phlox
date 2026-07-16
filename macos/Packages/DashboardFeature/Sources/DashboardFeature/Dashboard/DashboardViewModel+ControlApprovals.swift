import Foundation
import AgentDomain
import CodexAppServerKit
import SessionFeature

/// MC-3b: Control API（/approvals）に橋渡しする 1 承認分の中立データ。
///
/// DashboardFeature は ControlServer / AppBootstrap に依存しない（AppBootstrap → DashboardFeature の
/// 一方向を保ち循環を作らない）ため、ControlServer.ApprovalDTO への写像は App 層 witness で行う。
/// ここでは Control 層に依存しない中立型のみを公開する。
public struct ControlApproval: Sendable, Equatable {
    /// 元となる ChatApprovalRequest.id。
    public let id: UUID
    /// 承認を抱えている appServer セッションの id。
    public let sessionID: SessionID
    /// エージェント種別（AgentRef.id。組込 Codex なら AgentKind.codex.rawValue == "codex"）。
    public let kind: String
    /// 承認要求の内容（ChatApprovalRequest.prompt）。
    public let prompt: String

    public init(id: UUID, sessionID: SessionID, kind: String, prompt: String) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.prompt = prompt
    }
}

extension DashboardViewModel {
    /// 全 appServer セッションの保留中承認を中立型へ写像する。PTY/非 appServer は対象外。
    ///
    /// Codex の構造化承認（ChatApprovalBroker 経由）だけを列挙する。Claude/Cursor の PTY 推測打鍵は
    /// 対象にしない（PoC で不可確定）。
    static func controlApprovals(from sessions: [ChatSessionViewModel]) -> [ControlApproval] {
        sessions.flatMap { session in
            session.pendingApprovals.map { request in
                ControlApproval(
                    id: request.id,
                    sessionID: session.id,
                    kind: session.agentRef.id,
                    prompt: request.prompt
                )
            }
        }
    }

    /// id の承認に decision を応答する。対応する appServer セッションへ委譲し、
    /// ChatSessionViewModel.respondToApproval → ChatApprovalBroker で**実際の構造化応答**を返す。
    /// 一致 id を持つセッションがあれば true、無ければ false。
    static func respondToControlApproval(
        in sessions: [ChatSessionViewModel],
        id: UUID,
        decision: AgentDomain.ApprovalDecision
    ) async -> Bool {
        guard let session = sessions.first(where: { vm in
            vm.pendingApprovals.contains(where: { $0.id == id })
        }) else {
            return false
        }
        await session.respondToApproval(id, decision: decision)
        return true
    }

    /// witness 実装が参照する appServer セッション群。
    var appServerSessions: [ChatSessionViewModel] {
        sessionNodes.compactMap(\.appServer)
    }

    /// MC-3a witness の実体（列挙）。App 層が ControlApproval を ControlServer.ApprovalDTO に写像する。
    public func controlApprovals() -> [ControlApproval] {
        Self.controlApprovals(from: appServerSessions)
    }

    /// MC-3a witness の実体（応答）。Control/AppServer 双方で共有する AgentDomain の decision を渡す。
    public func respondToControlApproval(id: UUID, decision: AgentDomain.ApprovalDecision) async -> Bool {
        await Self.respondToControlApproval(in: appServerSessions, id: id, decision: decision)
    }

    /// 文字列 id / decision rawValue で応答する版。
    ///
    /// App 層 witness・E2E ハーネスが decision の rawValue だけを渡せるようにする。
    /// id が UUID として不正、または decision rawValue が AgentDomain.ApprovalDecision に復元できない場合は false。
    public func respondToControlApproval(idString: String, decisionRawValue: String) async -> Bool {
        guard let uuid = UUID(uuidString: idString),
              let decision = AgentDomain.ApprovalDecision(rawValue: decisionRawValue)
        else { return false }
        return await Self.respondToControlApproval(in: appServerSessions, id: uuid, decision: decision)
    }
}
