import Foundation

// PM3 task-8 純ロジック（ADR 0030:22 の規定対処）。
// 非 Lazy VStack を維持したまま「末尾 N 件のみ描画」の件数制限を担う純粋な値型。
// - items ≤ limit なら全件、超過時は末尾 limit 件＋隠れ件数。
// - expand() はユーザーの追加スクロールまたはアクセシビリティ操作で呼ばれ、limit が step 分増える。
//   増えるのは上限（maxStages 段）まで。上限を超えて遡ると、新しい側を外して窓をずらす（ADR 0229）。
// - reset() はセッション切替時に既定へ戻す。
//
// 設計の一線（ADR 0030 再入禁止）: この型はスクロール量・可視領域・GeometryReader 計測を
// 一切参照しない。窓を動かす契機はスクロール入力・ジャンプ・ボタンの明示操作だけで、
// レイアウト観測フィードバックに連動しない。
/// transcript の表示文脈（task-2 契約面）。窓の既定件数を文脈別に定める。
enum TranscriptPresentationContext: Equatable {
    /// 単一表示（初期描画コストを抑える 50 件）。
    case single
    /// グリッドタイル（全タイル常時描画のため小さい窓にする）。
    case gridTile
}

/// 会話のブロックの作り方（AgentStatusCardRouting）。Claude と Codex は状態カード、Cursor は今のまとめ方。
enum TranscriptBlockSource: Equatable {
    case grouped
    case statusCards(AgentStatusLiveState)

    func blocks(_ items: [ChatItem]) -> [ChatTranscriptBlock] {
        switch self {
        case .grouped: ChatTranscriptGrouping.blocks(from: items)
        case .statusCards(let live): AgentStatusCardBuilder.build(items: items, liveState: live)
        }
    }

    func visibleSlice(_ items: [ChatItem], blockLimit: Int) -> ChatTranscriptSlice {
        switch self {
        case .grouped: ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: blockLimit)
        case .statusCards(let live): AgentStatusCardBuilder.visibleSlice(items: items, liveState: live, blockLimit: blockLimit)
        }
    }

    func blockCount(_ items: [ChatItem]) -> Int {
        visibleSlice(items, blockLimit: 0).hiddenBlockCount
    }

    /// 末尾でない区間は実行中として組み立てない（全体の組み立てで実行中になるのは末尾の区間だけ。ADR 0229 §6）。
    var pinned: Self {
        guard case .statusCards(var live) = self else { return self }
        live.isProcessing = false
        return .statusCards(live)
    }

    /// 項目を含む区間。状態カードの会話は入力から次の入力の直前まで、まとめ方はコマンドの連続（ADR 0229 §6）。
    /// 区間を丸ごと組み立てれば、全体の組み立てと同じブロックになる。
    func segment(containing index: Int, in items: [ChatItem]) -> Range<Int> {
        switch self {
        case .grouped:
            guard case .commandExecution = items[index] else { return index..<(index + 1) }
            var lower = index
            var upper = index + 1
            while lower > items.startIndex, case .commandExecution = items[lower - 1] { lower -= 1 }
            while upper < items.endIndex, case .commandExecution = items[upper] { upper += 1 }
            return lower..<upper
        case .statusCards:
            let lower = items[...index].lastIndex(where: Self.isInput) ?? items.startIndex
            let upper = items[(index + 1)...].firstIndex(where: Self.isInput) ?? items.endIndex
            return lower..<upper
        }
    }

    private static func isInput(_ item: ChatItem) -> Bool {
        if case .userMessage = item { true } else { false }
    }
}

struct TranscriptWindow: Equatable {
    /// 既定の表示件数上限（50...500 の範囲の有限定数）。単一表示（`.single`）の既定値。
    static let defaultLimit: Int = 50
    /// グリッドタイル表示の既定件数上限。
    /// ADR 0116 で 40 → 16 に引き下げた。非 Lazy VStack のため窓内の全件が常に同時レイアウト
    /// 対象であり、この件数はそのまま「リサイズ時に CoreText で再 measure される item 数」と
    /// 「1 行更新で無効化される表示対象数」の母数になる。9 タイル同時表示では最大 40×9=360 件が
    /// メインスレッドのハング要因になっていた（Instruments 実測）ため、母数を約 60% 削減する。
    static let gridTileDefaultLimit: Int = 16
    /// 履歴追加1回あたりの拡張幅（50 以上の定数）。
    static let expandStep: Int = 50
    /// 窓の段数の上限（ADR 0229）。遡った後の 1 件追加が 50ms 前後に収まるよう計測から選んだ較正値。
    static let maxStages = 8

    private let presentationContext: TranscriptPresentationContext
    private(set) var limit: Int
    /// 窓の最後のブロックが含む最後の項目 id。nil なら末尾に追従する。値があるときは新しい側を描画から外している。
    /// 項目は終端の区間を探すのと、除去を見つけるのに使う。
    private(set) var lastItemID: String?
    /// 窓の最後のブロックの id。全体の組み立ての中で終端を決める。
    private var lastBlockID: String?

    private var contextDefaultLimit: Int { Self.defaultLimit(for: presentationContext) }
    private var maxLimit: Int { Self.maxStages * contextDefaultLimit }

    /// 表示すべき末尾スライスの開始 index と隠れ件数を返す。
    /// totalCount ≤ limit のとき (0, 0)。超過時は (totalCount - limit, totalCount - limit)。
    func visibleRange(totalCount: Int) -> (startIndex: Int, hiddenCount: Int) {
        let hidden = max(0, totalCount - limit)
        return (startIndex: hidden, hiddenCount: hidden)
    }

    /// 表示件数を step 分増やす。上限（`maxStages` 段）で止まる。
    mutating func expand() {
        limit = min(limit + TranscriptWindow.expandStep, maxLimit)
    }

    /// セッション切替時に自文脈の既定へ戻す。
    mutating func reset() {
        limit = contextDefaultLimit
        followTail()
    }

    /// 末尾追従に戻す。段数は保つ。
    mutating func followTail() {
        lastItemID = nil
        lastBlockID = nil
    }

    /// 終端より新しいブロックが無くなっていたら末尾追従に戻す（リバートや項目の除去の後）。
    /// 戻さないと、以後に届く項目が固定した窓の外に積まれ、最下部にいても描画されない。
    mutating func followTailIfNothingNewer(in items: [ChatItem], source: TranscriptBlockSource = .grouped) {
        guard lastItemID != nil else { return }
        if slice(of: items, source: source).hiddenNewerBlockCount == 0 {
            followTail()
        }
    }

    init(presentationContext: TranscriptPresentationContext = .single) {
        self.presentationContext = presentationContext
        self.limit = Self.defaultLimit(for: presentationContext)
    }

    /// 描画するブロックと、窓の前後で描画していないブロック数。
    /// 予算（ADR 0139）は窓の終端から古い側へ数える。終端が見つからなければ末尾に追従する。
    func slice(of items: [ChatItem], source: TranscriptBlockSource = .grouped) -> ChatTranscriptSlice {
        pinnedSlice(of: items, source: source) ?? budgeted(source.visibleSlice(items, blockLimit: limit), hiddenNewer: 0)
    }

    /// 終端のブロックを含む区間を丸ごと組み立て、終端より後ろを捨てる（ADR 0229 §6）。
    private func pinnedSlice(of items: [ChatItem], source: TranscriptBlockSource) -> ChatTranscriptSlice? {
        guard let lastItemID, let lastBlockID, let pin = items.lastIndex(where: { $0.id == lastItemID }) else { return nil }
        let segment = source.segment(containing: pin, in: items)
        let isTailSegment = segment.upperBound == items.endIndex
        // 終端より後ろの、同じ区間のブロックの分だけ多く組み立てる（1 項目は高々 1 ブロック）。
        let built = isTailSegment
            ? source.visibleSlice(items, blockLimit: limit + segment.count)
            : source.pinned.visibleSlice(Array(items[..<segment.upperBound]), blockLimit: limit + segment.count)
        guard let end = built.blocks.lastIndex(where: { $0.id == lastBlockID }) else { return nil }
        let throughEnd = built.blocks[...end].suffix(limit)
        let total = isTailSegment ? built.hiddenBlockCount + built.blocks.count : source.blockCount(items)
        return budgeted(
            ChatTranscriptSlice(blocks: Array(throughEnd), hiddenBlockCount: built.hiddenBlockCount + end + 1 - throughEnd.count),
            hiddenNewer: total - built.hiddenBlockCount - end - 1
        )
    }

    private func budgeted(_ candidate: ChatTranscriptSlice, hiddenNewer: Int) -> ChatTranscriptSlice {
        let count = TranscriptRenderBudget.allowedBlockCount(
            blocks: candidate.blocks.map(\.content),
            requestedLimit: limit,
            defaultLimit: contextDefaultLimit,
            minimumBlocks: TranscriptRenderBudget.minimumBlocks
        )
        return ChatTranscriptSlice(
            blocks: Array(candidate.blocks.suffix(count)),
            hiddenBlockCount: candidate.hiddenBlockCount + candidate.blocks.count - count,
            hiddenNewerBlockCount: hiddenNewer
        )
    }

    /// 上端で遡る（ADR 0217・0229）。上限未満なら段を足し、上限なら窓を 1 段分古い側へずらす。
    /// 戻り値は遡る前の先頭ブロックの id（位置を保つ目印）。遡る履歴がなければ何もせず nil。
    mutating func loadEarlier(in items: [ChatItem], source: TranscriptBlockSource = .grouped) -> String? {
        let current = slice(of: items, source: source)
        guard current.hiddenBlockCount > 0, let top = current.blocks.first else { return nil }
        guard limit >= maxLimit else {
            expand()
            return top.id
        }
        let blocks = current.blocks.map(\.content)
        // 予算に収まらない重いブロックが古い側に続くと、1 段分を外しても描画数が同じだけ減って先頭が動かない。
        // 古い側が現れるまで外す範囲を広げる（ADR 0229 §2）。
        for keep in stride(from: blocks.count - stageCount(blocks.reversed()), to: 0, by: -1) {
            pin(to: blocks[..<keep], in: items)
            if slice(of: items, source: source).hiddenBlockCount < current.hiddenBlockCount { return top.id }
        }
        let all = source.blocks(items)
        if let index = all.firstIndex(where: { $0.id == top.id }) {
            pin(to: all[..<index], in: items)
        }
        return top.id
    }

    /// 下端で引く（ADR 0229）。窓を 1 段分新しい側へずらし、末尾に届いたら追従に戻す。
    /// 戻り値は引く前の最後のブロックの id（位置を保つ目印）。新しい側を外していなければ nil。
    mutating func loadNewer(in items: [ChatItem], source: TranscriptBlockSource = .grouped) -> String? {
        guard let bottom = lastBlockID else { return nil }
        let blocks = source.blocks(items)
        guard let last = blocks.firstIndex(where: { $0.id == bottom }) else {
            followTail()
            return nil
        }
        pin(to: blocks[..<(last + 1 + stageCount(blocks[(last + 1)...]))], of: blocks, in: items)
        return bottom
    }

    /// 飛び先が窓の外なら、飛び先から新しい側へ上限より 1 段少ない分を描く窓にする（ADR 0229）。
    /// 件数と予算の両方で数えるので飛び先は必ず窓に入り、末尾追従になっても 1 段分の追加までは押し出されない。
    /// 窓を変えたら true。
    mutating func reveal(itemID: String, in items: [ChatItem], source: TranscriptBlockSource = .grouped) -> Bool {
        guard !slice(of: items, source: source).blocks.contains(where: { $0.content.contains(itemID: itemID) }) else { return false }
        let blocks = source.blocks(items)
        guard let target = ChatTranscriptGrouping.blockIndex(ofItemWithID: itemID, inBlocks: blocks) else { return false }
        let count = Self.forwardCount(
            blocks[target...],
            budget: TranscriptRenderBudget.defaultUnits * (Self.maxStages - 1),
            maxCount: maxLimit - contextDefaultLimit
        )
        limit = maxLimit
        pin(to: blocks[..<(target + count)], of: blocks, in: items)
        return true
    }

    /// 全体の組み立て `all` の先頭部分 `kept` の最後のブロックを窓の終端にする。全体の最後まで届いたら末尾追従にする。
    private mutating func pin(to kept: ArraySlice<ChatTranscriptBlock>, of all: [ChatTranscriptBlock], in items: [ChatItem]) {
        guard kept.endIndex < all.endIndex else {
            followTail()
            return
        }
        pin(to: kept, in: items)
    }

    /// `blocks`（全体の組み立ての連続した一部）の最後のブロックを窓の終端にする。
    /// 項目を含まないブロック（作業の無い実行中のカード）は終端にできないので手前へ寄せる。
    private mutating func pin(to blocks: ArraySlice<ChatTranscriptBlock>, in items: [ChatItem]) {
        for block in blocks.reversed() {
            guard let item = items.last(where: { block.contains(itemID: $0.id) }) else { continue }
            lastItemID = item.id
            lastBlockID = block.id
            return
        }
    }

    /// 先頭から 1 段分（既定の予算 1 つと既定件数）に収まるブロック数。窓が必ず動くよう、ブロックがあれば最低 1 件。
    private func stageCount<Blocks: Sequence>(_ blocks: Blocks) -> Int where Blocks.Element == ChatTranscriptBlock {
        Self.forwardCount(Array(blocks)[...], budget: TranscriptRenderBudget.defaultUnits, maxCount: contextDefaultLimit)
    }

    /// 先頭から予算と件数の両方に収まるブロック数。先頭の 1 件は予算を超えても数える。
    private static func forwardCount(_ blocks: ArraySlice<ChatTranscriptBlock>, budget: Int, maxCount: Int) -> Int {
        var used = 0
        var count = 0
        for block in blocks.prefix(maxCount) {
            let weight = TranscriptRenderBudget.weight(of: block)
            guard count == 0 || weight <= budget - used else { break }
            used += weight
            count += 1
        }
        return count
    }
}

extension TranscriptWindow {
    /// 表示文脈別の既定表示件数。
    static func defaultLimit(for context: TranscriptPresentationContext) -> Int {
        switch context {
        case .single:
            return defaultLimit
        case .gridTile:
            return gridTileDefaultLimit
        }
    }

    /// 表示文脈つきの生成。reset() は自文脈の既定値へ戻る。
    init(context: TranscriptPresentationContext) {
        self.init(presentationContext: context)
    }
}
