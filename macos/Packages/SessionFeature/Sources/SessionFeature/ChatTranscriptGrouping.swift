enum ChatTranscriptBlock: Identifiable, Equatable {
    case single(ChatItem)
    case commandGroup(id: String, items: [ChatItem])

    var id: String {
        switch self {
        case .single(let item):
            item.id
        case .commandGroup(let id, _):
            id
        }
    }
}

enum ChatTranscriptGrouping {
    static func blocks(from items: [ChatItem]) -> [ChatTranscriptBlock] {
        makeBlocks(from: items)
    }

    private static func makeBlocks<Items: Sequence>(from items: Items) -> [ChatTranscriptBlock]
    where Items.Element == ChatItem {
        var blocks: [ChatTranscriptBlock] = []
        var pendingCommands: [ChatItem] = []

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

        for item in items {
            if case .commandExecution = item {
                pendingCommands.append(item)
            } else {
                appendPendingCommands()
                blocks.append(.single(item))
            }
        }
        appendPendingCommands()

        return blocks
    }

    /// 個別 item のジャンプ先を、実際にトップレベルへ描画される block identity に解決する。
    /// commandGroup 内の item は先頭 item.id に解決するため、折りたたみ中も scrollTo が空振りしない。
    static func scrollTargetID(containing itemID: String, in items: [ChatItem]) -> String {
        for block in blocks(from: items) {
            switch block {
            case .single(let item) where item.id == itemID:
                return block.id
            case .commandGroup(let id, let groupedItems)
                where groupedItems.contains(where: { $0.id == itemID }):
                return id
            default:
                continue
            }
        }

        // transcript 外の既存アンカー（例: chat-bottom）に対する従来の挙動を維持する。
        return itemID
    }

    /// Window の開始位置が commandGroup の途中なら、境界以降だけを部分ブロックとして表示する。
    /// 部分ブロックの id は全 transcript 上のグループ先頭 item.id に固定するため、window 展開で
    /// 表示 item が増えても identity は変わらない。入力は ArraySlice のまま走査し、全件コピーしない。
    static func visibleSlice(from items: [ChatItem], startingAt requestedStartIndex: Int) -> ChatTranscriptSlice {
        let startIndex = min(max(0, requestedStartIndex), items.count)
        guard startIndex < items.count else {
            return ChatTranscriptSlice(blocks: [], hiddenItemCount: items.count)
        }

        let contentBlocks = makeBlocks(from: items[startIndex...])
        var visibleBlocks = contentBlocks.map { block in
            ChatTranscriptVisibleBlock(id: block.id, content: block)
        }
        if isCommand(items[startIndex]) {
            var groupStartIndex = startIndex
            while groupStartIndex > 0, isCommand(items[groupStartIndex - 1]) {
                groupStartIndex -= 1
            }

            if groupStartIndex < startIndex, !visibleBlocks.isEmpty {
                visibleBlocks[0] = ChatTranscriptVisibleBlock(
                    id: items[groupStartIndex].id,
                    content: visibleBlocks[0].content
                )
            }
        }

        return ChatTranscriptSlice(blocks: visibleBlocks, hiddenItemCount: startIndex)
    }

    private static func isCommand(_ item: ChatItem) -> Bool {
        if case .commandExecution = item {
            return true
        }
        return false
    }
}

struct ChatTranscriptVisibleBlock: Identifiable, Equatable {
    let id: String
    let content: ChatTranscriptBlock
}

struct ChatTranscriptSlice: Equatable {
    let blocks: [ChatTranscriptVisibleBlock]
    let hiddenItemCount: Int
}
