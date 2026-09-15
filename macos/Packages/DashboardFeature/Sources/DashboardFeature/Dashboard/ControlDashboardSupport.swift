import Foundation
import AgentDomain
import StructuredChatKit
import SessionFeature

/// Control API interrupt の写像結果（AppBootstrap.ControlActionDashboard witness 用）。
public enum ControlInterruptOutcome: Equatable, Sendable {
    case accepted
    case unsupported
    case notFound
}

/// Control API のモデル適用結果（AppBootstrap 側で HTTP status へ写像する）。
public enum ControlSetModelOutcome: Equatable, Sendable {
    case applied
    /// 候補一覧に無いモデル ID（→400）。
    case unknownModel
    /// codex の thread 未開始（→425。wait-ready 後に再送する）。
    case notReady
    /// モデル変更経路を持たないセッション（→404）。
    case unsupported
    /// セッション自体が存在しない（→404）。
    case notFound
    /// 適用は試みたが失敗（→500）。
    case failed
}

/// Control API usage の写像結果（AppBootstrap.ControlActionDashboard witness 用）。
public struct ControlSessionUsage: Equatable, Sendable {
    public let turn: TurnUsage?

    public init(turn: TurnUsage?) {
        self.turn = turn
    }
}

/// ControlServer に依存しない DashboardFeature 内部のモデル選択肢。
public struct DashboardControlModelOption: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// ControlServer に依存しない DashboardFeature 内部のセッションモデル設定。
public struct DashboardControlModelSettings: Equatable, Sendable {
    public let selectedModel: String?
    public let availableModels: [DashboardControlModelOption]

    public init(selectedModel: String?, availableModels: [DashboardControlModelOption]) {
        self.selectedModel = selectedModel
        self.availableModels = availableModels
    }
}

extension DashboardViewModel {
    public func controlInterruptSession(_ id: SessionID) async -> ControlInterruptOutcome {
        guard sessionNodes.contains(where: { $0.id == id }) else {
            return .notFound
        }
        guard let appServer = sessionNodes.first(where: { $0.id == id })?.appServer else {
            return .unsupported
        }
        await appServer.turnInterrupt()
        return .accepted
    }

    public func controlSubAgents(for id: SessionID) -> [SubAgentControlSummary]? {
        sessionNodes.first { $0.id == id }?.appServer?.subAgentControlSummaries()
    }

    public func controlSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? {
        guard let appServer = sessionNodes.first(where: { $0.id == id })?.appServer else {
            return nil
        }
        guard appServer.subAgents.contains(where: { $0.id == subAgentID }) else {
            return nil
        }
        return appServer.subAgentTranscript(for: subAgentID)
    }

    public func controlUsage(for id: SessionID) -> ControlSessionUsage? {
        guard let appServer = sessionNodes.first(where: { $0.id == id })?.appServer else {
            return nil
        }
        return ControlSessionUsage(turn: appServer.lastTurnUsage)
    }

    /// 契約6: 構造化セッションの差分/全量 transcript。非構造化/不在は nil（→404）。
    /// 差分の健全性判定は ChatSessionViewModel.transcriptDelta(since:) が担う。
    public func controlMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
        guard let appServer = sessionNodes.first(where: { $0.id == id })?.appServer else {
            return nil
        }
        return appServer.transcriptDelta(since: since)
    }

    public func controlModelSettings(for id: SessionID) -> DashboardControlModelSettings? {
        guard let appServer = sessionNodes.first(where: { $0.id == id })?.appServer else {
            return nil
        }
        // GET/POST の能力ゲートを一致させる: 適用できないセッションに選択肢を広告しない
        // （広告するのに POST が 404 になる乖離の防止）。候補の出所は spawn 型と codex で
        // 別だが、判定は `controlModelChoices` の空/非空に一本化する。
        let choices = appServer.controlModelChoices
        guard !choices.isEmpty else {
            return DashboardControlModelSettings(selectedModel: nil, availableModels: [])
        }
        return DashboardControlModelSettings(
            selectedModel: appServer.selectedModel,
            availableModels: choices.map {
                DashboardControlModelOption(id: $0.id, displayName: $0.displayName)
            }
        )
    }

    /// spawn 型（Claude/Cursor）は CLI フラグ差し替え、codex は app-server の
    /// updateThreadSettings。分岐は `ChatSessionViewModel.applyControlModel` に閉じている。
    public func controlSetModel(_ model: String, for id: SessionID) async -> ControlSetModelOutcome {
        guard let node = sessionNodes.first(where: { $0.id == id }) else { return .notFound }
        guard let appServer = node.appServer else { return .unsupported }
        switch await appServer.applyControlModel(model) {
        case .applied: return .applied
        case .unknownModel: return .unknownModel
        case .notReady: return .notReady
        case .unsupported: return .unsupported
        case .failed: return .failed
        }
    }
}
