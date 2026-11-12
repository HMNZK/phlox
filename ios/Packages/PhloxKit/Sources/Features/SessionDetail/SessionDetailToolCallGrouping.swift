import Foundation
import PhloxCore

/// SessionDetail transcript のトップレベル描画単位（task-1 契約）。
/// iOS では連続する 1 件以上の `.command` を `commandGroup` に集約する。
/// macOS の 2 件以上を集約する契約とは意図的に異なる。
public enum SessionDetailChatBlock: Identifiable, Equatable, Sendable {
    case single(ChatMessage)
    case statusCard(MobileStatusTranscript.Card)
    case commandGroup(id: String, items: [ChatMessage])

    public var id: String {
        switch self {
        case .single(let message):
            message.id
        case .statusCard(let card):
            card.id
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
    public static func blocks(from messages: [ChatMessage], statusTranscript: MobileStatusTranscript? = nil) -> [SessionDetailChatBlock] {
        guard let statusTranscript else { return makeBlocks(from: messages) }
        let byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var referenced: Set<String> = []
        var result: [SessionDetailChatBlock] = []
        for block in statusTranscript.blocks {
            switch block {
            case .messages(let ids):
                result += makeBlocks(from: ids.compactMap { id in
                    guard referenced.insert(id).inserted else { return nil }
                    return byID[id]
                })
            case .card(let card):
                for row in card.rows {
                    for entry in row.entries {
                        switch entry {
                        case .message(let id): referenced.insert(id)
                        case .action(let action): referenced.formUnion(action.messageIDs)
                        }
                    }
                }
                result.append(.statusCard(card))
            }
        }
        // 差分の到着順で投影より先に届いた本文も保持する。
        result += makeBlocks(from: messages.filter { !referenced.contains($0.id) })
        return result
    }

    /// 個別 message のジャンプ先を、実際にトップレベルへ描画される block identity に解決する。
    public static func scrollTargetID(containing messageID: String, in messages: [ChatMessage], statusTranscript: MobileStatusTranscript? = nil) -> String {
        for block in blocks(from: messages, statusTranscript: statusTranscript) {
            switch block {
            case .single(let message) where message.id == messageID:
                return block.id
            case .commandGroup(let id, let grouped)
                where grouped.contains(where: { $0.id == messageID }):
                return id
            case .statusCard(let card) where card.rows.contains(where: { row in
                row.entries.contains { entry in
                    switch entry {
                    case .message(let id): id == messageID
                    case .action(let action): action.messageIDs.contains(messageID)
                    }
                }
            }):
                return card.id
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
        blockLimit: Int,
        statusTranscript: MobileStatusTranscript? = nil
    ) -> SessionDetailTranscriptBlockSlice {
        let allBlocks = blocks(from: messages, statusTranscript: statusTranscript)
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
