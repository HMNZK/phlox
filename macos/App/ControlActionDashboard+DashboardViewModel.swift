import Foundation
import AgentDomain
import AppBootstrap
import ControlServer
import DashboardFeature
import SessionFeature

@MainActor
enum ControlDashboardSupport {
    static weak var usageMonitor: UsageMonitor?
}

/// DashboardViewModel を Control API ハンドラ（AppBootstrap）の依存プロトコルへ適合させる。
/// 型もプロトコルも他モジュール由来のため retroactive 適合（合成は App 層の責務）。
extension DashboardViewModel: @retroactive ControlActionDashboard {
    public var controlSessionSummaries: [ControlSessionSummary] {
        sessionNodes.map { node in
            let session = node.controllable
            let project = node.projectID.flatMap { projectID in
                projects.first { $0.id == projectID }
            }
            return ControlSessionSummary(
                id: session.id,
                name: session.name,
                agentID: node.agentRef.id,
                status: session.status,
                workspaceName: node.workspaceName,
                projectID: project?.id.description,
                projectName: project?.name
            )
        }
    }

    /// `spawnNewSession(ref:projectID:from:backend:)` は projectID 付きシグネチャのため
    /// プロトコル要件を直接 witness できない。薄いラッパで委譲する。
    /// backend はモバイルが構造化(.appServer)/ターミナル(.pty)を選べるように透過する。
    /// （.appServer を非構造化エージェントに要求した場合は spawnNewSession 側のガードが弾く。）
    public func spawnSession(
        ref: AgentRef,
        from: SessionID?,
        backend: SessionBackend,
        workingDirectory: String?
    ) async throws -> SessionID {
        try await spawnNewSession(
            ref: ref,
            from: from,
            backend: backend,
            launchContext: .orchestration,
            workingDirectoryOverride: workingDirectory
        )
    }

    // MARK: - 承認 witness（MC-3b: Codex 構造化承認ブリッジ）

    /// 全 appServer セッションの保留中承認を ControlServer.ApprovalDTO に写像する。
    /// マッピング本体は DashboardFeature の中立型（ControlApproval）で行い、ここで Control 層型に変換する。
    public func listApprovals() async -> [ApprovalDTO] {
        controlApprovals().map { approval in
            ApprovalDTO(
                id: approval.id.uuidString,
                sessionID: approval.sessionID.rawValue.uuidString,
                kind: approval.kind,
                prompt: approval.prompt
            )
        }
    }

    /// id の承認に decision を応答する。decision の rawValue を DashboardFeature 側へ渡し、
    /// CodexAppServerKit.ApprovalDecision へ変換のうえ ChatApprovalBroker 経由で構造化応答を返す。
    public func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool {
        await respondToControlApproval(idString: id, decisionRawValue: decision.rawValue)
    }

    public func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome {
        await controlInterruptSession(id)
    }

    public func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? {
        controlSubAgents(for: id)
    }

    public func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? {
        controlSubAgentMessages(for: id, subAgentID: subAgentID)
    }

    public func sessionUsage(for id: SessionID) -> ControlSessionUsage? {
        controlUsage(for: id)
    }

    public func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
        controlMessagesDelta(for: id, since: since)
    }

    public func sessionModelSettings(for id: SessionID) -> ControlSessionModelSettings? {
        guard let settings = controlModelSettings(for: id) else {
            return nil
        }
        return ControlSessionModelSettings(
            selectedModel: settings.selectedModel,
            availableModels: settings.availableModels.map {
                ControlModelOption(id: $0.id, displayName: $0.displayName)
            }
        )
    }

    public func setSessionModel(_ model: String, for id: SessionID) async -> Bool {
        await controlSetModel(model, for: id)
    }

    public var controlCLIUsages: [AgentKind: CLIUsage] {
        ControlDashboardSupport.usageMonitor?.usages ?? [:]
    }

    // sendMessage の要件は DashboardViewModel 本体（DashboardFeature）の
    // 同シグネチャ public メソッドが直接 witness する。ここに同シグネチャの
    // 転送ラッパを書くと呼び出しが自分自身へ解決され無限再帰する
    // （2026-07-12 実発生: Control send 1回でメモリ暴走→システムクラッシュ）。書かないこと。
}
