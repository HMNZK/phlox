import Foundation

/// Mac（Phlox プロキシ）への HTTP API 窓口（DI シーム）。
///
/// 実体は `actor PhloxAPIClient`（PhloxNetworking / E3-1）。全 7 エンドポイントの論理操作を提供する。
/// wire DTO・エンドポイントパス・PhloxError 正規化は PhloxNetworking 側に閉じ、戻り値は PhloxCore の
/// 集約モデル（`Session` / `Approval`、E1-3）で表現する。
public protocol PhloxAPI: Sendable {
    /// GET /sessions
    func listSessions() async throws -> [Session]
    /// POST /sessions（新規起動）
    func spawn(_ request: SpawnRequest) async throws -> Session
    /// GET /agents/{kind}/models（起動前に選択可能なモデル一覧）
    func agentModels(kind: AgentKind) async throws -> AgentModels
    /// GET /usage（エージェント別のアカウント使用量）
    func cliUsage() async throws -> [CLIUsage]
    /// GET /sessions/{id}/ready（入力受付可能になるまで Mac 側でロングポーリング待機）。ready 値を返す。
    /// spawn 直後は CLI 起動前で送信が実行されないため、初期プロンプト送信前に使う。
    func waitUntilReady(sessionID: String) async throws -> Bool
    /// POST /send（to,text）（送信）
    func send(_ request: SendRequest) async throws -> SendResult
    /// GET /sessions/{id}/output（出力スナップショット）
    func output(sessionID: String) async throws -> String
    /// GET /sessions/{id}/messages（構造化チャットスナップショット）。
    /// 非構造化/不在のセッションは 404 → `PhloxError.notFound` を投げる（呼び出し側でターミナル output にフォールバック）。
    func messages(sessionID: String) async throws -> [ChatMessage]
    /// DELETE /sessions/{id}
    func remove(sessionID: String) async throws
    /// PATCH /sessions/{id}（セッション名変更）
    func rename(sessionID: String, name: String) async throws
    /// GET /approvals
    func approvals() async throws -> [Approval]
    /// POST /approvals/{id}（承認/却下/セッション内自動承認/取消）
    func respond(approvalID: String, decision: ApprovalDecision) async throws

    // MARK: - API 拡張契約 v1（docs/specs/mobile-api-extensions-contract.md）
    // 既定実装（下の extension）が 501 を投げる。実装は task-7（PhloxAPIClient）。

    /// POST /sessions/{id}/interrupt（実行中ターンの停止。契約 §1）
    func interrupt(sessionID: String) async throws
    /// GET /sessions/{id}/subagents（契約 §2）
    func subAgents(sessionID: String) async throws -> [SubAgentSummary]
    /// GET /sessions/{id}/subagents/{subAgentId}/messages（契約 §3）
    func subAgentMessages(sessionID: String, subAgentID: String) async throws -> [ChatMessage]
    /// GET /sessions/{id}/usage（契約 §4。ターンが無ければ nil）
    func usage(sessionID: String) async throws -> TurnUsage?
    /// GET /sessions/{id}/messages?since=…&wait=…（契約 §6。差分取得）
    func messagesDelta(sessionID: String, since: String?, wait: Int?) async throws -> MessagesDelta

    /// POST /sessions/{id}/question（AskUserQuestion への回答。契約: PhloxQuestionWireContract。
    /// task-0 で追加・実装は task-4）
    func respondToQuestion(sessionID: String, requestId: String, answers: [String: [String]]) async throws
}

/// 拡張メソッドの既定実装（未実装の合図として 501 を投げる）。
/// 既存の全 conformer（PhloxAPIClient / MockAPI / StubPhloxAPI）のコンパイルを壊さないための
/// 暫定面で、実装が入り次第それぞれが上書きする。
public extension PhloxAPI {
    func agentModels(kind: AgentKind) async throws -> AgentModels {
        throw PhloxError.server(status: 501, message: "agentModels: 未実装")
    }

    func cliUsage() async throws -> [CLIUsage] {
        throw PhloxError.server(status: 501, message: "cliUsage: 未実装")
    }

    func interrupt(sessionID: String) async throws {
        throw PhloxError.server(status: 501, message: "interrupt: 未実装（task-7）")
    }

    func subAgents(sessionID: String) async throws -> [SubAgentSummary] {
        throw PhloxError.server(status: 501, message: "subAgents: 未実装（task-7）")
    }

    func subAgentMessages(sessionID: String, subAgentID: String) async throws -> [ChatMessage] {
        throw PhloxError.server(status: 501, message: "subAgentMessages: 未実装（task-7）")
    }

    func usage(sessionID: String) async throws -> TurnUsage? {
        throw PhloxError.server(status: 501, message: "usage: 未実装（task-7）")
    }

    func messagesDelta(sessionID: String, since: String?, wait: Int?) async throws -> MessagesDelta {
        throw PhloxError.server(status: 501, message: "messagesDelta: 未実装（task-7）")
    }

    func rename(sessionID: String, name: String) async throws {
        throw PhloxError.server(status: 501, message: "rename: 未実装")
    }

    func respondToQuestion(sessionID: String, requestId: String, answers: [String: [String]]) async throws {
        throw PhloxError.server(status: 501, message: "respondToQuestion: 未実装（task-4）")
    }
}
