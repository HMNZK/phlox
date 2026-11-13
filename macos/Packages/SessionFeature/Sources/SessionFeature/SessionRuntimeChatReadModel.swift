import AgentDomain
import ChatRenderKit
import Foundation
import StructuredChatKit

public struct SessionRuntimeChatReadCursor: Codable, Sendable, Equatable {
    public let scopeID: String
    public let revision: UInt64
    public let index: Int
    public let anchorID: String
}

public enum SessionRuntimeChatItemReference: Codable, Sendable, Equatable {
    case inline(ChatItem)
    case deferred(SessionRuntimeContentMarker)

    public var id: String {
        switch self {
        case .inline(let item): item.id
        case .deferred(let marker): marker.id
        }
    }
}

extension SessionRuntimeChatItemReference {
    /// 実行サービスが組み立てたページに含まれる、表示しない思考か。旧サービス（思考を除く前の版）が返す
    /// inline の思考と、大きさで後取得にされた思考の目印（`itemKind == "reasoning"`）の両方を判定する。
    /// 受信したページ・cursor・item ID は変えない。`itemKind` を持たない最古の目印は判別できない。
    func isHiddenReasoning(agent: AgentKind) -> Bool {
        guard AgentStatusCardRouting.hidesReasoning(agent) else { return false }
        switch self {
        case .inline(.reasoning): return true
        case .inline: return false
        case .deferred(let marker): return marker.kind == .chatItem && marker.itemKind == "reasoning"
        }
    }
}

extension SessionRuntimeChatReadBlock {
    func isHiddenReasoning(agent: AgentKind) -> Bool {
        if case .item(let reference) = content { reference.isHiddenReasoning(agent: agent) } else { false }
    }
}

extension SessionRuntimeCardEntry {
    func isHiddenReasoning(agent: AgentKind) -> Bool {
        if case .item(let reference) = self { reference.isHiddenReasoning(agent: agent) } else { false }
    }
}

public struct SessionRuntimeCardSummary: Codable, Sendable, Equatable {
    public let id: String
    public let inputID: String
    public let revision: UInt64
    public let contentRevision: Int
    public let header: AgentStatusHeader
    public let totalRowCount: Int
    public let hasTasks: Bool
    public var activeRowID: String? = nil
    public var changeCounts: ChatFileChangePresentation.Counts? = nil
}

public struct SessionRuntimeCommandGroupSummary: Codable, Sendable, Equatable {
    public let firstCommand: String?
    public let lastCommand: String?
    public let timestamp: Date
    public let hasNonBlankOutput: Bool
    public let exitCode: Int?
}

public struct SessionRuntimeActionSummary: Codable, Sendable, Equatable {
    public let id: String
    public let label: AgentStatusAction.Label
    public let state: AgentStatusWorkState
    public let startedAt: Date?
    public let duration: TimeInterval?
    public let totalItemCount: Int
    public var commandGroup: SessionRuntimeCommandGroupSummary? = nil
    public var contentRevision: Int = 0
}

public struct SessionRuntimeChatReadBlock: Codable, Sendable {
    public enum Content: Codable, Sendable {
        case item(SessionRuntimeChatItemReference)
        case commandGroup(SessionRuntimeActionSummary)
        case card(SessionRuntimeCardSummary)
    }

    public let id: String
    public let ownerInputID: String?
    public let content: Content
}

public struct SessionRuntimeChatReadRevealTarget: Codable, Sendable, Equatable {
    public let inputID: String?
    public let cardID: String?
    public let rowID: String?
    public let entryID: String?
    public let itemID: String
}

public struct SessionRuntimeChatReadPage: Codable, Sendable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let transcriptRevision: Int
    public let revision: UInt64
    public let totalBlockCount: Int
    public let startIndex: Int
    public let blocks: [SessionRuntimeChatReadBlock]
    public let olderCursor: SessionRuntimeChatReadCursor?
    public let newerCursor: SessionRuntimeChatReadCursor?
    public var revealTarget: SessionRuntimeChatReadRevealTarget? = nil
    public let latestHeader: AgentStatusHeader?
    public let turnUsageByItemID: [String: TurnUsage]
}

public struct SessionRuntimeCardRow: Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        case task(id: String, title: String, state: AgentStatusTask.State, startedAt: Date?, endedAt: Date?)
        case outside(state: AgentStatusWorkState)
    }

    public let id: String
    public let kind: Kind
    public let totalEntryCount: Int
    public let totalActionCount: Int
}

public struct SessionRuntimeCardRowsPage: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let card: SessionRuntimeCardSummary
    public let rows: [SessionRuntimeCardRow]
    public let nextCursor: SessionRuntimeChatReadCursor?
}

public enum SessionRuntimeCardEntry: Codable, Sendable, Equatable {
    case item(SessionRuntimeChatItemReference)
    case action(SessionRuntimeActionSummary)

    public var id: String {
        switch self {
        case .item(let reference): reference.id
        case .action(let action): action.id
        }
    }
}

public struct SessionRuntimeCardEntriesPage: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let inputID: String
    public let rowID: String
    public let revision: UInt64
    public let entries: [SessionRuntimeCardEntry]
    public let nextCursor: SessionRuntimeChatReadCursor?
}

public struct SessionRuntimeActionItemsPage: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let inputID: String?
    public let actionID: String
    public let revision: UInt64
    public let items: [SessionRuntimeChatItemReference]
    public let nextCursor: SessionRuntimeChatReadCursor?
}

public struct SessionRuntimeInputHistorySummary: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let preview: SessionRuntimeTextPreview
    public let timestamp: Date
    public let canRecall: Bool
    public let content: SessionRuntimeChatItemReference
}

public struct SessionRuntimeInputHistoryPage: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let executionID: UUID
    public let revision: UInt64
    public let totalCount: Int
    public let entries: [SessionRuntimeInputHistorySummary]
    public let olderCursor: SessionRuntimeChatReadCursor?
    public let newerCursor: SessionRuntimeChatReadCursor?
}

extension SessionRuntimeContentRequest.Target {
    public var requiresChatReadModel: Bool {
        switch self {
        case .chatReadTail, .chatReadBefore, .chatReadAfter, .chatReadAround, .chatReadAroundItem,
             .chatCardRows, .chatCardRowsAround, .chatRowEntries, .chatRowEntriesAround, .chatActionItems, .chatActionItemsFrom, .inputHistory, .inputHistoryAfter: true
        default: false
        }
    }
}

public enum SessionRuntimeChatReadLimits {
    public static let maximumResponseBytes = 256 * 1024
    public static let maximumInlineItemBytes = 8 * 1024
    public static let maximumItemsPerPage = 50
}
