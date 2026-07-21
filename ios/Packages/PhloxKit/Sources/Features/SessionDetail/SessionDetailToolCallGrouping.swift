import Foundation
import PhloxCore

/// SessionDetail transcript のトップレベル描画単位（phlox-ux-5fixes task-5 契約）。
/// Mac の `ChatTranscriptBlock`（single / commandGroup）に対応する iOS 版。
/// 契約の正本: tasks/task-5.md（受け入れテスト AcceptanceIOSToolCallGroupingTests が凍結）。
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
    public let hiddenItemCount: Int
}

/// 連続する `.command` メッセージを 1 ブロックへ集約する純関数（task-5 契約）。
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

    /// Window の開始位置が commandGroup の途中なら、境界以降だけを部分ブロックとして表示する。
    /// 部分ブロックの id は全 transcript 上のグループ先頭 message.id に固定する。
    public static func visibleSlice(
        from messages: [ChatMessage],
        startingAt requestedStartIndex: Int
    ) -> SessionDetailTranscriptBlockSlice {
        let startIndex = min(max(0, requestedStartIndex), messages.count)
        guard startIndex < messages.count else {
            return SessionDetailTranscriptBlockSlice(blocks: [], hiddenItemCount: messages.count)
        }

        let contentBlocks = makeBlocks(from: messages[startIndex...])
        var visibleBlocks = contentBlocks.map { block in
            SessionDetailVisibleBlock(id: block.id, content: block)
        }
        if isCommand(messages[startIndex]) {
            var groupStartIndex = startIndex
            while groupStartIndex > 0, isCommand(messages[groupStartIndex - 1]) {
                groupStartIndex -= 1
            }

            if groupStartIndex < startIndex, !visibleBlocks.isEmpty {
                visibleBlocks[0] = SessionDetailVisibleBlock(
                    id: messages[groupStartIndex].id,
                    content: visibleBlocks[0].content
                )
            }
        }

        return SessionDetailTranscriptBlockSlice(blocks: visibleBlocks, hiddenItemCount: startIndex)
    }

    private static func makeBlocks<Items: Sequence>(from messages: Items) -> [SessionDetailChatBlock]
    where Items.Element == ChatMessage {
        var blocks: [SessionDetailChatBlock] = []
        var pendingCommands: [ChatMessage] = []

        func appendPendingCommands() {
            switch pendingCommands.count {
            case 0:
                break
            case 1:
                blocks.append(.single(pendingCommands[0]))
            default:
                blocks.append(.commandGroup(id: pendingCommands[0].id, items: pendingCommands))
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

    private static func isCommand(_ message: ChatMessage) -> Bool {
        if case .command = message {
            return true
        }
        return false
    }
}
