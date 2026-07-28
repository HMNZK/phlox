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
            if let first = pendingCommands.first {
                blocks.append(.commandGroup(id: first.id, items: pendingCommands))
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

    static func blockCount(of items: [ChatItem]) -> Int {
        blocks(from: items).count
    }

    static func blockIndex(ofItemWithID itemID: String, in items: [ChatItem]) -> Int? {
        for (index, block) in blocks(from: items).enumerated() {
            switch block {
            case .single(let item) where item.id == itemID:
                return index
            case .commandGroup(_, let groupedItems) where groupedItems.contains(where: { $0.id == itemID }):
                return index
            default:
                continue
            }
        }
        return nil
    }

    static func visibleSlice(from items: [ChatItem], blockLimit: Int) -> ChatTranscriptSlice {
        visibleSlice(fromBlocks: blocks(from: items), blockLimit: blockLimit)
    }

    /// 既にブロック化済みの配列からスライスを作る。
    /// 呼び出し側が表示件数の決定（`TranscriptRenderBudget`）のために blocks を先に必要とするとき、
    /// この overload を使って `makeBlocks` の二度手間を避ける（body 評価ごとに全 item を
    /// 2 回走査するのは、まさにここで削ろうとしている切替コストに乗る）。
    static func visibleSlice(fromBlocks allBlocks: [ChatTranscriptBlock], blockLimit: Int) -> ChatTranscriptSlice {
        let visibleCount = min(allBlocks.count, max(0, blockLimit))
        let visibleBlocks = allBlocks.suffix(visibleCount).map {
            ChatTranscriptVisibleBlock(id: $0.id, content: $0)
        }

        return ChatTranscriptSlice(
            blocks: visibleBlocks,
            hiddenBlockCount: allBlocks.count - visibleCount
        )
    }
}

struct ChatTranscriptVisibleBlock: Identifiable, Equatable {
    let id: String
    let content: ChatTranscriptBlock
}

struct ChatTranscriptSlice: Equatable {
    let blocks: [ChatTranscriptVisibleBlock]
    let hiddenBlockCount: Int
}
