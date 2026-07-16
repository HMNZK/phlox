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
        // GET/POST の能力ゲートを一致させる: 実際に適用できない（SpawnAgentSettingsControlling
        // 欠如）セッションに選択肢を広告しない（広告するのに POST が 404 になる乖離の防止）。
        guard appServer.canApplySpawnAgentSettings,
              !appServer.availableSpawnAgentModels.isEmpty
        else {
            return DashboardControlModelSettings(selectedModel: nil, availableModels: [])
        }
        return DashboardControlModelSettings(
            selectedModel: appServer.selectedModel,
            availableModels: appServer.availableSpawnAgentModels.map { model in
                DashboardControlModelOption(
                    id: model,
                    displayName: appServer.spawnAgentModelDisplayName(model)
                )
            }
        )
    }

    /// `setSpawnAgentModel` は model/permission/effort を揃えて controller に渡す安全経路。
    public func controlSetModel(_ model: String, for id: SessionID) async -> Bool {
        guard let appServer = sessionNodes.first(where: { $0.id == id })?.appServer,
              appServer.canApplySpawnAgentSettings
        else {
            return false
        }
        await appServer.setSpawnAgentModel(model)
        return true
    }
}
