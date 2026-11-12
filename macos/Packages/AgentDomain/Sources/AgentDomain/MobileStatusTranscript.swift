import Foundation

/// Mac の状態カードの組み立て結果。本文は既存 messages の ID だけを参照する。
public struct MobileStatusTranscript: Codable, Equatable, Sendable {
    public let blocks: [Block]

    public init(blocks: [Block]) { self.blocks = blocks }

    public enum Block: Codable, Equatable, Sendable {
        case messages(ids: [String])
        case card(Card)
    }

    public enum CardState: String, Codable, Equatable, Sendable {
        case running, stalled, awaitingReply, completed, interrupted, error, superseded, ended
    }

    public enum RowKind: String, Codable, Equatable, Sendable { case task, outside }
    public enum RowState: String, Codable, Equatable, Sendable {
        case pending, inProgress, running, completed, interrupted, failed, unknown
    }
    public enum WorkState: String, Codable, Equatable, Sendable {
        case running, completed, interrupted, failed, unknown
    }

    public enum Entry: Codable, Equatable, Sendable {
        case message(id: String)
        case action(Action)
    }

    public struct Card: Codable, Equatable, Sendable {
        public let id: String
        public let state: CardState
        public let title: String
        public let startedAt: Date
        public let endedAt: Date?
        public let activityState: AgentActivityState
        public let silence: TimeInterval?
        public let rows: [Row]

        public init(id: String, state: CardState, title: String, startedAt: Date, endedAt: Date?, activityState: AgentActivityState, silence: TimeInterval?, rows: [Row]) {
            self.id = id
            self.state = state
            self.title = title
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.activityState = activityState
            self.silence = silence
            self.rows = rows
        }
    }

    public struct Row: Codable, Equatable, Sendable {
        public let id: String
        public let kind: RowKind
        public let title: String
        public let state: RowState
        public let autoExpanded: Bool
        public let startedAt: Date?
        public let endedAt: Date?
        public let entries: [Entry]

        public init(id: String, kind: RowKind, title: String, state: RowState, autoExpanded: Bool, startedAt: Date?, endedAt: Date?, entries: [Entry]) {
            self.id = id
            self.kind = kind
            self.title = title
            self.state = state
            self.autoExpanded = autoExpanded
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.entries = entries
        }
    }

    public struct Action: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let state: WorkState
        public let startedAt: Date?
        public let duration: TimeInterval?
        public let messageIDs: [String]
        public let symbolName: String

        public init(id: String, title: String, state: WorkState, startedAt: Date?, duration: TimeInterval?, messageIDs: [String], symbolName: String) {
            self.id = id
            self.title = title
            self.state = state
            self.startedAt = startedAt
            self.duration = duration
            self.messageIDs = messageIDs
            self.symbolName = symbolName
        }
    }
}
