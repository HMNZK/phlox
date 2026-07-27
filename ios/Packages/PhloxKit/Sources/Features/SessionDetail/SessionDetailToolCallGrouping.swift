import Foundation
import PhloxCore

/// SessionDetail transcript のトップレベル描画単位（task-1 契約）。
/// iOS では連続する 1 件以上の `.command` を `commandGroup` に集約する。
/// macOS の 2 件以上を集約する契約とは意図的に異なる。
public enum SessionDetailChatBlock: Identifiable, Equatable, Sendable {
    case single(ChatMessage)
    case commandGroup(id: String, items: [ChatMessage])

    public var id: String {
        switch self {
        case .single(let message):
            message.id
        case .commandGroup(let id, _):
            id
        }
    }
}

public struct SessionDetailVisibleBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public let content: SessionDetailChatBlock
}

public struct SessionDetailTranscriptBlockSlice: Equatable, Sendable {
    public let blocks: [SessionDetailVisibleBlock]
    public let hiddenBlockCount: Int
}

/// 連続する 1 件以上の `.command` メッセージを 1 ブロックへ集約する純関数（task-1 契約）。
public enum SessionDetailToolCallGrouping {
    public static func blocks(from messages: [ChatMessage]) -> [SessionDetailChatBlock] {
        makeBlocks(from: messages)
    }

    /// 個別 message のジャンプ先を、実際にトップレベルへ描画される block identity に解決する。
    public static func scrollTargetID(containing messageID: String, in messages: [ChatMessage]) -> String {
        for block in blocks(from: messages) {
            switch block {
            case .single(let message) where message.id == messageID:
                return block.id
            case .commandGroup(let id, let grouped)
                where grouped.contains(where: { $0.id == messageID }):
                return id
            default:
                continue
            }
        }

        return messageID
    }

    public static func blockCount(of messages: [ChatMessage]) -> Int {
        blocks(from: messages).count
    }

    /// 末尾の blockLimit ブロックを返す。窓境界は常に block 境界なので部分ブロックは生じない。
    public static func visibleSlice(
        from messages: [ChatMessage],
        blockLimit: Int
    ) -> SessionDetailTranscriptBlockSlice {
        let allBlocks = blocks(from: messages)
        let visibleCount = min(allBlocks.count, max(0, blockLimit))
        let visibleBlocks = allBlocks.suffix(visibleCount).map { block in
            SessionDetailVisibleBlock(id: block.id, content: block)
        }

        return SessionDetailTranscriptBlockSlice(
            blocks: visibleBlocks,
            hiddenBlockCount: allBlocks.count - visibleCount
        )
    }

    private static func makeBlocks<Items: Sequence>(from messages: Items) -> [SessionDetailChatBlock]
    where Items.Element == ChatMessage {
        var blocks: [SessionDetailChatBlock] = []
        var pendingCommands: [ChatMessage] = []

        func appendPendingCommands() {
            if let first = pendingCommands.first {
                blocks.append(.commandGroup(id: first.id, items: pendingCommands))
            }
            pendingCommands.removeAll(keepingCapacity: true)
        }

        for message in messages {
            if case .command = message {
                pendingCommands.append(message)
            } else {
                appendPendingCommands()
                blocks.append(.single(message))
            }
        }
        appendPendingCommands()

        return blocks
    }

}
