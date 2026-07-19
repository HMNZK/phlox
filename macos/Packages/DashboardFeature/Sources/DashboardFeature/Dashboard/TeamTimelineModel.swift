import Foundation
import AgentDomain
import SessionFeature

public enum TeamTimelineContent: Equatable, Sendable {
    case chatItem(ChatItem)
    case terminalText(String)
}

public struct TeamTimelineSourceMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date?
    public let content: TeamTimelineContent

    public init(id: String, timestamp: Date?, content: TeamTimelineContent) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
    }

    public static func chatItem(_ item: ChatItem) -> TeamTimelineSourceMessage {
        TeamTimelineSourceMessage(
            id: item.id,
            timestamp: TeamTimelineModel.timestamp(for: item),
            content: .chatItem(item)
        )
    }
}

public struct TeamTimelineSource: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let displayName: String
    public let agentDescriptor: AgentDescriptor
    public let messages: [TeamTimelineSourceMessage]

    public init(
        id: SessionID,
        displayName: String,
        agentDescriptor: AgentDescriptor,
        messages: [TeamTimelineSourceMessage]
    ) {
        self.id = id
        self.displayName = displayName
        self.agentDescriptor = agentDescriptor
        self.messages = messages
    }
}

public struct TeamTimelineItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionID: SessionID
    public let sessionDisplayName: String
    public let agentDescriptor: AgentDescriptor
    public let sourceMessageID: String
    public let timestamp: Date?
    public let content: TeamTimelineContent

    public init(
        id: String,
        sessionID: SessionID,
        sessionDisplayName: String,
        agentDescriptor: AgentDescriptor,
        sourceMessageID: String,
        timestamp: Date?,
        content: TeamTimelineContent
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sessionDisplayName = sessionDisplayName
        self.agentDescriptor = agentDescriptor
        self.sourceMessageID = sourceMessageID
        self.timestamp = timestamp
        self.content = content
    }
}

public enum TeamTimelineModel {
    public static func merge(_ sources: [TeamTimelineSource]) -> [TeamTimelineItem] {
        let flattened = sources.enumerated().flatMap { sessionOrder, source in
            source.messages.enumerated().map { itemOrder, message in
                OrderedMessage(
                    source: source,
                    message: message,
                    sessionOrder: sessionOrder,
                    itemOrder: itemOrder
                )
            }
        }

        return flattened
            .sorted(by: orderedBefore)
            .map { ordered in
                TeamTimelineItem(
                    id: "\(ordered.source.id.rawValue.uuidString):\(ordered.message.id)",
                    sessionID: ordered.source.id,
                    sessionDisplayName: ordered.source.displayName,
                    agentDescriptor: ordered.source.agentDescriptor,
                    sourceMessageID: ordered.message.id,
                    timestamp: ordered.message.timestamp,
                    content: ordered.message.content
                )
            }
    }

    public static func timestamp(for item: ChatItem) -> Date? {
        switch item {
        case .userMessage(_, _, let timestamp, _),
             .agentMessage(_, _, let timestamp),
             .reasoning(_, _, let timestamp),
             .commandExecution(_, _, _, let timestamp),
             .fileChange(_, _, let timestamp),
             .error(_, _, let timestamp),
             .turnCost(_, _, let timestamp),
             .userQuestion(_, _, _, _, _, let timestamp):
            timestamp
        case .subAgentMarker:
            nil
        }
    }

    private static func orderedBefore(_ lhs: OrderedMessage, _ rhs: OrderedMessage) -> Bool {
        switch (lhs.message.timestamp, rhs.message.timestamp) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            if lhs.sessionOrder != rhs.sessionOrder {
                return lhs.sessionOrder < rhs.sessionOrder
            }
            return lhs.itemOrder < rhs.itemOrder
        }
    }

    private struct OrderedMessage {
        let source: TeamTimelineSource
        let message: TeamTimelineSourceMessage
        let sessionOrder: Int
        let itemOrder: Int
    }
}
