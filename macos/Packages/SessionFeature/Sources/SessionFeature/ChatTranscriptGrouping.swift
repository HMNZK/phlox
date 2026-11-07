import DesignSystem

enum ChatTranscriptBlock: Identifiable, Equatable {
    case single(ChatItem)
    case commandGroup(id: String, items: [ChatItem])
    /// エージェント状態カード（AgentStatusCardBuilder が組み立て、AgentStatusCardView が描く。Claude と Codex だけ）。
    case statusCard(AgentStatusCard)

    var id: String {
        switch self {
        case .single(let item):
            item.id
        case .commandGroup(let id, _):
            id
        case .statusCard(let card):
            card.id
        }
    }

    func contains(itemID: String) -> Bool {
        switch self {
        case .single(let item):
            item.id == itemID
        case .commandGroup(_, let items):
            items.contains { $0.id == itemID }
        case .statusCard(let card):
            card.contains(itemID: itemID)
        }
    }

    var typographyRole: TranscriptTypography.BlockRole {
        switch self {
        case .commandGroup, .statusCard:
            .process
        case .single(let item):
            switch item {
            case .userMessage:
                .user
            case .agentMessage:
                .answer
            case .reasoning, .commandExecution, .fileChange, .subAgentMarker, .taskList, .userQuestion:
                .process
            case .error, .turnCost:
                .auxiliary
            }
        }
    }
}

enum ChatTranscriptGrouping {
    static func blocks<Items: Sequence>(from items: Items) -> [ChatTranscriptBlock]
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
    /// 状態カードの中の item はカードの id に解決する。
    static func scrollTargetID(containing itemID: String, in items: [ChatItem]) -> String {
        scrollTargetID(containing: itemID, inBlocks: blocks(from: items))
    }

    static func scrollTargetID(containing itemID: String, inBlocks blocks: [ChatTranscriptBlock]) -> String {
        for block in blocks where block.contains(itemID: itemID) {
            return block.id
        }

        // transcript 外の既存アンカー（例: chat-bottom）に対する従来の挙動を維持する。
        return itemID
    }

    static func blockIndex(ofItemWithID itemID: String, inBlocks blocks: [ChatTranscriptBlock]) -> Int? {
        blocks.firstIndex { $0.contains(itemID: itemID) }
    }

    static func blockCount<Items: Sequence>(of items: Items) -> Int where Items.Element == ChatItem {
        var count = 0
        var isInCommandGroup = false
        for item in items {
            if case .commandExecution = item {
                if !isInCommandGroup { count += 1 }
                isInCommandGroup = true
            } else {
                count += 1
                isInCommandGroup = false
            }
        }
        return count
    }

    static func visibleSlice(from items: [ChatItem], blockLimit: Int) -> ChatTranscriptSlice {
        visibleSlice(from: items[...], blockLimit: blockLimit)
    }

    static func visibleSlice(from items: ArraySlice<ChatItem>, blockLimit: Int) -> ChatTranscriptSlice {
        let limit = max(0, blockLimit)
        var visibleBlocks: [ChatTranscriptVisibleBlock] = []
        visibleBlocks.reserveCapacity(min(items.count, limit))
        var blockCount = 0
        var index = items.endIndex

        while index > items.startIndex {
            let end = index
            index -= 1
            if case .commandExecution = items[index] {
                while index > items.startIndex {
                    guard case .commandExecution = items[index - 1] else { break }
                    index -= 1
                }
                if visibleBlocks.count < limit {
                    let id = items[index].id
                    visibleBlocks.append(ChatTranscriptVisibleBlock(
                        id: id,
                        content: .commandGroup(id: id, items: Array(items[index..<end]))
                    ))
                }
            } else if visibleBlocks.count < limit {
                let item = items[index]
                visibleBlocks.append(ChatTranscriptVisibleBlock(id: item.id, content: .single(item)))
            }
            blockCount += 1
        }

        visibleBlocks.reverse()
        return ChatTranscriptSlice(blocks: visibleBlocks, hiddenBlockCount: blockCount - visibleBlocks.count)
    }

    /// 既にブロック化済みの配列からスライスを作る。
    /// 呼び出し側が表示件数の決定（`TranscriptRenderBudget`）のために blocks を先に必要とするとき、
    /// この overload を使って `blocks(from:)` の二度手間を避ける（body 評価ごとに全 item を
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
    /// 窓より古い側で描画していないブロック数。
    let hiddenBlockCount: Int
    /// 窓より新しい側で描画していないブロック数（ADR 0228）。
    var hiddenNewerBlockCount = 0
}
