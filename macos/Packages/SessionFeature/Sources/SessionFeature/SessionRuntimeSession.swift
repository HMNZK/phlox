import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import TerminalUI

public enum SessionRuntimeSessionSnapshot: Codable, Sendable {
    case pty(SessionRuntimePTYSnapshot)
    case chat(SessionRuntimeChatSnapshot)

    public var id: SessionID {
        switch self { case .pty(let value): value.id; case .chat(let value): value.id }
    }
    public var startedAt: Date {
        switch self { case .pty(let value): value.startedAt; case .chat(let value): value.startedAt }
    }
    public var agentRef: AgentRef {
        switch self { case .pty(let value): value.agentRef; case .chat(let value): value.agentRef }
    }
    public var executionID: UUID {
        switch self { case .pty(let value): value.executionID; case .chat(let value): value.executionID }
    }
}

public struct SessionRuntimeTextPreview: Codable, Sendable, Equatable {
    public let text: String
    public let truncated: Bool

    public init(_ value: String, maximumBytes: Int = 512) {
        let bytes = Array(value.utf8.prefix(maximumBytes + 1))
        truncated = bytes.count > maximumBytes
        if !truncated {
            text = value
            return
        }
        var prefix = Array(bytes.prefix(maximumBytes))
        while String(bytes: prefix, encoding: .utf8) == nil { prefix.removeLast() }
        text = String(decoding: prefix, as: UTF8.self)
    }

    public var displayText: String { text + (truncated ? "…" : "") }
}

public enum SessionRuntimePendingInteractionOverview: Codable, Sendable, Equatable {
    case approval(id: UUID, prompt: SessionRuntimeTextPreview, requiresDetail: Bool, requestedAt: Date)
    case question(index: Int, prompt: SessionRuntimeTextPreview, isToolPermission: Bool, requestedAt: Date)
}

public struct SessionRuntimeSessionOverview: Codable, Sendable {
    public struct ChatState: Codable, Sendable {
        public struct Controls: Codable, Sendable {
            public var selectedModel: String?
            public var selectedEffort: String?
            public var selectedPermissionProfile: String?
            public var selectedApprovalPolicy: ApprovalPolicy?
            public var selectedCodexSandbox: SandboxPolicy?
            public var isPlanMode = false
            public var isPlanModeAvailable = false
            public var isCompacting = false
            public var isApplyingSpawnAgentPermission = false
            public var isTerminating = false
            public var usesStandardClaudeAuthentication = true
            public var acceptsImageAttachments = false
            public var canApplySpawnAgentSettings = false
            public var supportsCodexSettings = false
            public var isUsingBuiltinModelList = false
            public var hasHistoryProvider = false
            public var submitBaselineTurnSeq: Int?
            public var lastTurnCostUSD: Double?
            public var turnStartedAt: Date?
            public var lastEventAt: Date?
            public init() {}
        }

        public let transcriptRevision: Int
        public let lastNonAppendRevision: Int
        public let transcriptItemCount: Int
        public let pendingInteractionCount: Int
        public let pendingInteractions: [SessionRuntimePendingInteractionOverview]
        public let pendingIdentity: String
        public let presentationRevision: UInt64
        public let lastAgentText: SessionRuntimeTextPreview?
        public let processExit: ChatProcessExit?
        public let isStalled: Bool
        public let stalledSince: Date?
        public let completedTurnSeq: Int
        public let draftRecoveryID: UUID?
        public let isProcessing: Bool
        public let controls: Controls

        public init(transcriptRevision: Int, lastNonAppendRevision: Int = 0, transcriptItemCount: Int,
                    pendingInteractionCount: Int, pendingInteractions: [SessionRuntimePendingInteractionOverview],
                    pendingIdentity: String = "",
                    presentationRevision: UInt64 = 0,
                    lastAgentText: SessionRuntimeTextPreview?, processExit: ChatProcessExit?,
                    isStalled: Bool, stalledSince: Date?, completedTurnSeq: Int,
                    draftRecoveryID: UUID?, isProcessing: Bool, controls: Controls = .init()) {
            self.transcriptRevision = transcriptRevision
            self.lastNonAppendRevision = lastNonAppendRevision
            self.transcriptItemCount = transcriptItemCount
            self.pendingInteractionCount = pendingInteractionCount
            self.pendingInteractions = pendingInteractions
            self.pendingIdentity = pendingIdentity
            self.presentationRevision = presentationRevision
            self.lastAgentText = lastAgentText
            self.processExit = processExit
            self.isStalled = isStalled
            self.stalledSince = stalledSince
            self.completedTurnSeq = completedTurnSeq
            self.draftRecoveryID = draftRecoveryID
            self.isProcessing = isProcessing
            self.controls = controls
        }
    }

    public struct PTYState: Codable, Sendable {
        public let completedTurnSeq: Int
        public let hasProducedOutput: Bool
        public let isRestored: Bool
        public let isReadyForInput: Bool
        public let nativeSessionID: String?
        public let displayRevision: UInt64

        public init(completedTurnSeq: Int, hasProducedOutput: Bool, isRestored: Bool, isReadyForInput: Bool,
                    nativeSessionID: String? = nil, displayRevision: UInt64 = 0) {
            self.completedTurnSeq = completedTurnSeq
            self.hasProducedOutput = hasProducedOutput
            self.isRestored = isRestored
            self.isReadyForInput = isReadyForInput
            self.nativeSessionID = nativeSessionID
            self.displayRevision = displayRevision
        }
    }

    public enum Kind: Codable, Sendable {
        case chat(ChatState)
        case pty(PTYState)
    }

    public let id: SessionID
    public let startedAt: Date
    public let agentRef: AgentRef
    public let workingDirectory: SessionRuntimeTextPreview?
    public let executionID: UUID
    public let title: SessionRuntimeTextPreview
    public let titleState: SessionTitleState
    public let projectID: ProjectID?
    public let parentSessionID: SessionID?
    public let launchContext: SessionLaunchContext
    public let status: SessionStatus
    public let displayStatus: SessionStatus
    public let statusRequiresDetail: Bool
    public let statusEnteredAt: Date?
    public let displayStatusEnteredAt: Date?
    public let hasUnseenCompletion: Bool
    public let lastOutputAt: Date?
    public let lastTurnCompletedAt: Date?
    public let kind: Kind

    public init(id: SessionID, startedAt: Date, agentRef: AgentRef, workingDirectory: String?,
                executionID: UUID, title: String, titleState: SessionTitleState? = nil,
                projectID: ProjectID?, parentSessionID: SessionID?,
                launchContext: SessionLaunchContext, status: SessionStatus, displayStatus: SessionStatus,
                statusEnteredAt: Date?, displayStatusEnteredAt: Date?,
                hasUnseenCompletion: Bool, lastOutputAt: Date?, lastTurnCompletedAt: Date?, kind: Kind) {
        self.id = id
        self.startedAt = startedAt
        self.agentRef = agentRef
        self.workingDirectory = workingDirectory.map { SessionRuntimeTextPreview($0, maximumBytes: 4096) }
        self.executionID = executionID
        self.title = SessionRuntimeTextPreview(title)
        let boundedTitle = SessionRuntimeTextPreview(titleState?.name ?? title)
        let boundedFlower = titleState?.flowerName.map { SessionRuntimeTextPreview($0).displayText }
        let derivedTitle = titleState?.fullDerivedTitle
        if titleState?.source == .derived, let derivedTitle,
           !SessionRuntimeTextPreview(derivedTitle, maximumBytes: 4096).truncated {
            self.titleState = SessionTitleState(name: boundedTitle.displayText, source: .derived,
                flowerName: boundedFlower, fullDerivedTitle: derivedTitle)
        } else if titleState?.source == .flower, let boundedFlower,
                  boundedTitle.displayText == boundedFlower {
            self.titleState = .generated(flowerName: boundedFlower)
        } else {
            self.titleState = .legacy(name: boundedTitle.displayText)
        }
        self.projectID = projectID
        self.parentSessionID = parentSessionID
        self.launchContext = launchContext
        let boundedStatus: (SessionStatus) -> (SessionStatus, Bool) = { status in
            switch status {
            case .awaitingApproval(let prompt):
                let preview = SessionRuntimeTextPreview(prompt)
                return (.awaitingApproval(prompt: preview.text), preview.truncated)
            case .error(let message):
                let preview = SessionRuntimeTextPreview(message)
                return (.error(message: preview.text), preview.truncated)
            default:
                return (status, false)
            }
        }
        let raw = boundedStatus(status)
        let displayed = boundedStatus(displayStatus)
        self.status = raw.0
        self.displayStatus = displayed.0
        self.statusRequiresDetail = raw.1 || displayed.1
        self.statusEnteredAt = statusEnteredAt
        self.displayStatusEnteredAt = displayStatusEnteredAt
        self.hasUnseenCompletion = hasUnseenCompletion
        self.lastOutputAt = lastOutputAt
        self.lastTurnCompletedAt = lastTurnCompletedAt
        self.kind = kind
    }
}

public struct SessionRuntimePTYSnapshot: Codable, Sendable {
    public let id: SessionID
    public let startedAt: Date
    public let agentRef: AgentRef
    public let workingDirectory: String?
    public var executionID = UUID()
    public var nativeSessionID: String?
    public var titleState: SessionTitleState = .legacy(name: "")
    public var projectID: ProjectID?
    public var parentSessionID: SessionID?
    public var launchContext: SessionLaunchContext = .interactive
    public var status: SessionStatus = .starting
    public var statusEnteredAt: Date?
    public var hasUnseenCompletion = false
    public var hasProducedOutput = false
    public var lastOutputAt: Date?
    public var lastTurnCompletedAt: Date?
    public var submitBaselineTurnSeq: Int?
    public var completedTurnSeq = 0
    public var activeTurnId: String?
    public var isRestored = false
    public var isReadyForInput = false
    public var display: TerminalRuntimeDisplaySnapshot

    public init(id: SessionID, startedAt: Date, agentRef: AgentRef,
                workingDirectory: String?, display: TerminalRuntimeDisplaySnapshot) {
        self.id = id
        self.startedAt = startedAt
        self.agentRef = agentRef
        self.workingDirectory = workingDirectory
        self.display = display
    }
}

public struct SessionRuntimeChatSnapshot: Codable, Sendable {
    public let id: SessionID
    public let startedAt: Date
    public let agentRef: AgentRef
    public let workingDirectory: String?
    public var executionID = UUID()
    public var titleState: SessionTitleState = .legacy(name: "")
    public var projectID: ProjectID?
    public var parentSessionID: SessionID?
    public var launchContext: SessionLaunchContext = .interactive
    public var status: SessionStatus = .starting
    public var statusEnteredAt: Date?
    public var hasUnseenCompletion = false
    public var processExit: ChatProcessExit?
    public var isStalled = false
    public var stalledSince: Date?
    public var threadId: String?
    public var chatNativeSessionId: String?
    public var appServerUserAgent: String?
    public var transcript: [ChatItem] = []
    public var transcriptRevision = 0
    public var rawEventLog: [String] = []
    public var pendingApprovals: [ChatApprovalRequest] = []
    public var sendFailure: ChatSessionViewModel.SendFailure?
    public var inFlightText: String?
    public var completedTurnSeq = 0
    public var lastOutputAt: Date?
    public var lastTurnCompletedAt: Date?
    public var lastTurnUsage: TurnUsage?
    public var turnUsageByItemID: [String: TurnUsage] = [:]
    public var lastTurnCostUSD: Double?
    public var launchFailure: ChatLaunchError?
    public var pendingFirstMessage: ChatItem?
    public var draftRecoveryID: UUID?
    public var submitBaselineTurnSeq: Int?
    public var runningBackgroundTasks: [RunningBackgroundTask] = []
    public var restoreState: ChatRestoreState = .notRestored
    public var availableModels: [AppServerModel] = []
    public var availableSlashCommands: [String]?
    public var seedSlashCommands: [String]?
    public var permissionProfiles: [PermissionProfileSummary] = []
    public var selectedModel: String?
    public var selectedEffort: String?
    public var selectedPermissionProfile: String?
    public var selectedApprovalPolicy: ApprovalPolicy?
    public var selectedCodexSandbox: SandboxPolicy?
    public var isPlanMode = false
    public var isPlanModeAvailable = false
    public var availableSpawnAgentModels: [String] = []
    public var isCompacting = false
    public var isApplyingSpawnAgentPermission = false
    public var isTerminating = false
    public var usesStandardClaudeAuthentication = true
    public var acceptsImageAttachments = false
    public var canApplySpawnAgentSettings = false
    public var supportsCodexSettings = false
    public var isUsingBuiltinModelList = false
    public var hasHistoryProvider = false
    public var historyEntries: [ClaudeSessionHistoryEntry] = []
    public var historySummaries: [String: ChatHistorySummary] = [:]
    public var turnStartedAt: Date?
    public var lastEventAt: Date?
    public var skillSelection: SessionRuntimeSkillSnapshot?
    public var plan: SessionRuntimePlanSnapshot?
    public var codexSubAgents: CodexSubAgentState?
    public var codexSubAgentError: String?
    public var subAgents = SessionRuntimeSubAgentSnapshot()

    public init(id: SessionID, startedAt: Date, agentRef: AgentRef, workingDirectory: String?) {
        self.id = id
        self.startedAt = startedAt
        self.agentRef = agentRef
        self.workingDirectory = workingDirectory
    }
}

public struct SessionRuntimeSkillSnapshot: Codable, Sendable {
    public var skills: [SkillMetadata]
    public var fingerprints: [String: String]
    public var isLoading: Bool
    public var isStale: Bool
    public var errorMessage: String?
}

public struct SessionRuntimePlanSnapshot: Codable, Sendable {
    public var threadId: String
    public var turnId: String
    public var tasks: [AgentTaskItem]
    public var explanation: String?
}

public struct SessionRuntimeSubAgentSnapshot: Codable, Sendable {
    public var subAgents: [SubAgentRef] = []
    public var transcripts: [String: [ChatItem]] = [:]
    public var dismissedIDs: Set<String> = []
    public var stoppableIDs: Set<String> = []
    public var stopPendingIDs: Set<String> = []
    public init() {}
}

public enum SessionRuntimeSessionCommand: Codable, Sendable {
    case send(text: String, submit: Bool, attachments: [ComposerAttachment], skill: SkillIdentity?)
    case sendControlSkill(text: String, submit: Bool, attachments: [ComposerAttachment], skill: SkillIdentity)
    case input(Data)
    case resize(cols: UInt16, rows: UInt16)
    case interrupt
    case terminate
    case approval(UUID, decision: ApprovalDecision)
    case question(requestId: String, answers: [String: [String]])
    case declineQuestion(requestId: String)
    case revert(userMessageID: String)
    case recoverLaunchDraft(UUID)
    case acknowledgeRecoveredDraft(UUID)
    case startFromHistory(ClaudeSessionHistoryEntry)
    case resumeHistory(ClaudeSessionHistoryEntry, approvalPolicy: ApprovalPolicy, sandbox: SandboxPolicy, settings: CodexAppServerSessionSettings?)
    case model(String, effort: String?)
    case permission(String)
    case planMode(Bool)
    case spawnModel(String?)
    case spawnPermission(String?)
    case spawnEffort(String?)
    case cycleEffort
    case retryModels
    case refreshSkills
    case refreshSubAgents
    case stopSubAgent(String)
    case dismissSubAgent(String)
    case markCompletionSeen
    case markCompletionSeenIfCurrent(String)
    case consumeSubmitBaseline
    case rename(SessionTitleState)
}

public enum SessionRuntimeSessionCommandResult: Codable, Sendable {
    case none
    case bool(Bool)
    case text(String?)
    case draft(text: String?, attachments: [ComposerAttachment])
    case accepted(UUID)
}

public typealias SessionRuntimeSessionCommandHandler = @MainActor (UUID, SessionRuntimeSessionCommand) async throws -> SessionRuntimeSessionCommandResult

public enum SessionRuntimeProjectionError: Error, LocalizedError, Sendable {
    case wrongSession
    case notAProjection
    case unsupportedCommand
    case invalidReply
    case staleRequest
    case staleExecution
    case pendingDraftRecovery

    public var errorDescription: String? {
        switch self {
        case .wrongSession: "別のセッションの状態を受信しました"
        case .notAProjection: "実行側の状態を表示用の状態で置き換えることはできません"
        case .unsupportedCommand: "このセッションでは利用できない操作です"
        case .invalidReply: "セッションの応答形式が一致しません"
        case .staleRequest: "この承認または質問は既に解決しています"
        case .staleExecution: "再起動前のセッションへの操作は実行できません"
        case .pendingDraftRecovery: "前の送信に失敗した本文と画像を復元してから送信してください"
        }
    }
}
