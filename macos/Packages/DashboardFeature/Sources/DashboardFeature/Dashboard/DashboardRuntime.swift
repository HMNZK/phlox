import Foundation
import AgentDomain
import SessionFeature

public struct DashboardRuntimeSnapshot: Codable, Sendable {
    public var projects: [Project]
    public var sessions: [SessionRuntimeSessionSnapshot]
    public var availableAgentKinds: [AgentKind]
    public var hasRestoredSessions: Bool
    public var immovableSessionIDs: Set<SessionID>
    public var worktreeBranches: [SessionID: String]
    public var workspaceRoot: URL?
    public var workspaceCleanupWarning: WorkspaceCleanupWarning?
    public var workspaceCleanupFailureReason: String?
    public var discardedSessionCount: Int?
    public var worktreeCreationPath: String?
    public var usage: UsageRuntimeSnapshot?
    public var restoredSessionPresentation: RestoredSessionPresentation?

    public init(projects: [Project], sessions: [SessionRuntimeSessionSnapshot], availableAgentKinds: [AgentKind],
                hasRestoredSessions: Bool = true, immovableSessionIDs: Set<SessionID> = [],
                worktreeBranches: [SessionID: String] = [:], workspaceRoot: URL? = nil,
                workspaceCleanupWarning: WorkspaceCleanupWarning? = nil, workspaceCleanupFailureReason: String? = nil,
                discardedSessionCount: Int? = nil, worktreeCreationPath: String? = nil, usage: UsageRuntimeSnapshot? = nil,
                restoredSessionPresentation: RestoredSessionPresentation? = nil) {
        self.projects = projects
        self.sessions = sessions
        self.availableAgentKinds = availableAgentKinds
        self.hasRestoredSessions = hasRestoredSessions
        self.immovableSessionIDs = immovableSessionIDs
        self.worktreeBranches = worktreeBranches
        self.workspaceRoot = workspaceRoot
        self.workspaceCleanupWarning = workspaceCleanupWarning
        self.workspaceCleanupFailureReason = workspaceCleanupFailureReason
        self.discardedSessionCount = discardedSessionCount
        self.worktreeCreationPath = worktreeCreationPath
        self.usage = usage
        self.restoredSessionPresentation = restoredSessionPresentation
    }
}

public struct DashboardRuntimeSpawnRequest: Codable, Sendable {
    public var ref: AgentRef
    public var projectID: ProjectID?
    public var parentSessionID: SessionID?
    public var backend: SessionBackend
    public var launchContext: SessionLaunchContext
    public var extraEnv: [String: String]
    public var workingDirectoryOverride: String?
    public var isolationOverride: Bool?
    public var worktreeStartPoint: WorktreeStartPoint
    public var initialSettings: CodexAppServerSessionSettings?
    public var resumeHistoryEntry: ClaudeSessionHistoryEntry?
    public var keepsRowOnLaunchFailure: Bool
}

public enum DashboardRuntimeCommand: Codable, Sendable {
    case session(SessionID, UUID, SessionRuntimeSessionCommand)
    case spawn(DashboardRuntimeSpawnRequest)
    case launchNewChat(NewChatLaunchRequest)
    case restartNewChat(SessionID)
    case resumeChat(SessionID)
    case addProject(name: String, directoryPath: String)
    case renameProject(ProjectID, String)
    case renameSession(SessionID, String)
    case reorderSession(SessionID, SessionID)
    case moveSession(SessionID, ProjectID)
    case changeWorkspace(SessionID, URL)
    case removeSession(SessionID)
    case removeProject(ProjectID)
    case history(ProjectID, AgentRef)
    case persistRole(SessionID, String)
    case clearWorkspaceCleanupWarning
    case takeDiscardedSessionCountNotice
    case usage(UsageRuntimeCommand)
    case message(DashboardRuntimeMessageRequest)

    public var isImmediateSessionControl: Bool {
        guard case .session(_, _, let command) = self else { return false }
        switch command {
        case .interrupt, .terminate, .approval, .question, .declineQuestion,
             .stopSubAgent, .recoverLaunchDraft, .acknowledgeRecoveredDraft: return true
        default: return false
        }
    }
}

public enum DashboardRuntimeReply: Codable, Sendable {
    case none
    case sessionID(SessionID)
    case acceptedSession(SessionID)
    case projectID(ProjectID?)
    case bool(Bool)
    case history([ClaudeSessionHistoryEntry])
    case session(SessionRuntimeSessionCommandResult)
    case sendOutcome(DashboardViewModel.SendOutcome)
}

public struct DashboardRuntimeMessageRequest: Codable, Sendable {
    public enum Recipient: Codable, Sendable {
        case id(SessionID)
        case name(String)
    }
    public struct Image: Codable, Sendable {
        public var mediaType: String
        public var data: Data
    }
    public var recipient: Recipient
    public var text: String
    public var submit: Bool
    public var from: SessionID?
    public var inReplyTo: UUID?
    public var images: [Image]
}

public typealias DashboardRuntimeCommandHandler = @MainActor (DashboardRuntimeCommand) async throws -> DashboardRuntimeReply

public enum DashboardRuntimeError: Error, LocalizedError, Sendable {
    case invalidSnapshot(String)
    case unexpectedReply
    case ownedOperationUnavailable
    case sessionNotFound
    case commandQueueFull
    case removalFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot(let reason): "セッションの状態を復元できませんでした。\(reason)"
        case .unexpectedReply: "バックグラウンド実行プロセスから予期しない応答を受信しました"
        case .ownedOperationUnavailable: "この操作はバックグラウンド実行プロセスでのみ実行できます"
        case .sessionNotFound: "対象のセッションが見つかりません"
        case .commandQueueFull: "操作が混み合っています。処理が終わってからやり直してください"
        case .removalFailed(let reason): reason
        }
    }
}
