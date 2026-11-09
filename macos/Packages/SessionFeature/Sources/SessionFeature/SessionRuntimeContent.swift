import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit

public enum SessionRuntimeContentError: Error, LocalizedError, Sendable, Equatable {
    case staleContent
    case invalidRequest
    case notFound

    public var errorDescription: String? {
        switch self {
        case .staleContent: "本文が更新されました。取得し直してください。"
        case .invalidRequest: "本文の取得位置が不正です。"
        case .notFound: "指定された本文が見つかりません。"
        }
    }
}

public struct SessionRuntimeContentCursor: Codable, Sendable, Equatable {
    public let index: Int
    public let anchorID: String
    public let prefixDigest: String

    public init(index: Int, anchorID: String, prefixDigest: String) {
        self.index = index
        self.anchorID = anchorID
        self.prefixDigest = prefixDigest
    }
}

public struct SessionRuntimeContentRequest: Codable, Sendable {
    public enum Target: Codable, Sendable {
        case chatTail
        case chatTailChecking(cursor: SessionRuntimeContentCursor)
        case ptySnapshot(displayRevision: UInt64)
        case chatBefore(cursor: SessionRuntimeContentCursor)
        case pending(cursor: SessionRuntimeContentCursor?)
        case itemChunk(id: String, digest: String, offset: Int)
        case approvalChunk(id: UUID, digest: String, offset: Int)
        case chatPresentation(offset: Int, digest: String?)
    }

    public let sessionID: SessionID
    public let executionID: UUID
    public let target: Target

    public init(sessionID: SessionID, executionID: UUID, target: Target) {
        self.sessionID = sessionID
        self.executionID = executionID
        self.target = target
    }
}

public struct SessionRuntimeContentMarker: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case chatItem, approval }

    public let kind: Kind
    public let id: String
    public let digest: String
    public let totalBytes: Int
    public let preview: SessionRuntimeTextPreview

    public init(kind: Kind, id: String, digest: String, totalBytes: Int, preview: String) {
        self.kind = kind
        self.id = id
        self.digest = digest
        self.totalBytes = totalBytes
        self.preview = SessionRuntimeTextPreview(preview)
    }
}

public enum SessionRuntimeChatPageEntry: Codable, Sendable {
    case item(ChatItem)
    case oversized(SessionRuntimeContentMarker)
}

public struct SessionRuntimeChatPage: Codable, Sendable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let transcriptRevision: Int
    public let totalCount: Int
    public let startIndex: Int
    public let entries: [SessionRuntimeChatPageEntry]
    public let olderCursor: SessionRuntimeContentCursor?
    public let turnUsageByItemID: [String: TurnUsage]

    public init(sessionID: SessionID, executionID: UUID, transcriptRevision: Int,
                totalCount: Int, startIndex: Int, entries: [SessionRuntimeChatPageEntry],
                olderCursor: SessionRuntimeContentCursor?, turnUsageByItemID: [String: TurnUsage]) {
        self.sessionID = sessionID
        self.executionID = executionID
        self.transcriptRevision = transcriptRevision
        self.totalCount = totalCount
        self.startIndex = startIndex
        self.entries = entries
        self.olderCursor = olderCursor
        self.turnUsageByItemID = turnUsageByItemID
    }
}

public enum SessionRuntimePendingEntry: Codable, Sendable {
    case approval(ChatApprovalRequest)
    case question(ChatItem)
    case relatedItem(ChatItem)
    case oversized(SessionRuntimeContentMarker)
}

public struct SessionRuntimePendingPage: Codable, Sendable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let transcriptRevision: Int
    public let totalCount: Int
    public let entries: [SessionRuntimePendingEntry]
    public let nextCursor: SessionRuntimeContentCursor?

    public init(sessionID: SessionID, executionID: UUID, transcriptRevision: Int,
                totalCount: Int, entries: [SessionRuntimePendingEntry], nextCursor: SessionRuntimeContentCursor?) {
        self.sessionID = sessionID
        self.executionID = executionID
        self.transcriptRevision = transcriptRevision
        self.totalCount = totalCount
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

public struct SessionRuntimeContentChunk: Codable, Sendable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let id: String
    public let digest: String
    public let offset: Int
    public let totalBytes: Int
    public let bytes: Data
    public let nextOffset: Int?

    public init(sessionID: SessionID, executionID: UUID, id: String, digest: String,
                offset: Int, totalBytes: Int, bytes: Data, nextOffset: Int?) {
        self.sessionID = sessionID
        self.executionID = executionID
        self.id = id
        self.digest = digest
        self.offset = offset
        self.totalBytes = totalBytes
        self.bytes = bytes
        self.nextOffset = nextOffset
    }
}

public enum SessionRuntimeContentResponse: Codable, Sendable {
    case ptySnapshot(snapshot: SessionRuntimePTYSnapshot, displayRevision: UInt64)
    case chatPage(SessionRuntimeChatPage)
    case pendingPage(SessionRuntimePendingPage)
    case chunk(SessionRuntimeContentChunk)
    case presentationChunk(SessionRuntimeContentChunk)
}

/// 選択中の会話にだけ取得する表示・操作候補。本文と子エージェントの転写は含めない。
public struct SessionRuntimeChatPresentation: Codable, Sendable {
    public var sendFailure: ChatSessionViewModel.SendFailure?
    public var inFlightText: String?
    public var hasPendingFirstMessage = false
    public var launchFailure: ChatLaunchError?
    public var runningBackgroundTasks: [RunningBackgroundTask] = []
    public var restoreState: ChatRestoreState = .notRestored
    public var availableModels: [AppServerModel] = []
    public var availableSlashCommands: [String]?
    public var seedSlashCommands: [String]?
    public var permissionProfiles: [PermissionProfileSummary] = []
    public var availableSpawnAgentModels: [String] = []
    public var lastTurnUsage: TurnUsage?
    public var historyEntries: [ClaudeSessionHistoryEntry] = []
    public var historySummaries: [String: ChatHistorySummary] = [:]
    public var skillSelection: SessionRuntimeSkillSnapshot?
    public var codexSubAgents: CodexSubAgentState?
    public var codexSubAgentError: String?
    public var subAgents = SessionRuntimeSubAgentSnapshot()

    public init() {}
}

func boundedRuntimeDisplay(_ text: String) -> String {
    SessionRuntimeTextPreview(text, maximumBytes: 512).displayText
}
