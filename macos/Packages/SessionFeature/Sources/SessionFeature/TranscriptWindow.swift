import Foundation

// PM3 task-8 純ロジック（ADR 0030:22 の規定対処）。
// 非 Lazy VStack を維持したまま「末尾 N 件のみ描画」の件数制限を担う純粋な値型。
// - items ≤ limit なら全件、超過時は末尾 limit 件＋隠れ件数。
// - expand() はユーザーの追加スクロールまたはアクセシビリティ操作で呼ばれ、limit が step 分増える。
//   増えるのは上限（maxStages 段）まで。上限を超えて遡ると、新しい側を外して窓をずらす（ADR 0228）。
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

    /// 窓の終端より新しい区間があるので、窓の最後の区間は実行中として組み立てない（ADR 0228 §6）。
    var pinned: Self {
        guard case .statusCards(var live) = self else { return self }
        live.isProcessing = false
        return .statusCards(live)
    }

    /// 状態カードの会話では、窓の終端を入力の直前に合わせる（カードを区間の途中で切らない。ADR 0228 §6）。
    /// 古い側へ合わせるときは先頭のブロックを残し、区切りが無ければそのまま返す。
    func inputBoundary(atOrBefore index: Int, in blocks: [ChatTranscriptBlock]) -> Int {
        guard case .statusCards = self, index > 1 else { return index }
        return (1...index).last { Self.isInput(blocks[$0]) } ?? index
    }

    func inputBoundary(atOrAfter index: Int, in blocks: [ChatTranscriptBlock]) -> Int {
        guard case .statusCards = self else { return index }
        return (index..<blocks.count).first { Self.isInput(blocks[$0]) } ?? blocks.count
    }

    private static func isInput(_ block: ChatTranscriptBlock) -> Bool {
        if case .single(.userMessage) = block { true } else { false }
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
    /// 窓の段数の上限（ADR 0228）。遡った後の 1 件追加が 50ms 前後に収まるよう計測から選んだ較正値。
    static let maxStages = 8

    private let presentationContext: TranscriptPresentationContext
    private(set) var limit: Int
    /// 窓の最後の項目 id。nil なら末尾に追従する。値があるときは新しい側を描画から外している。
    private(set) var lastItemID: String?

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
        lastItemID = nil
    }

    /// 末尾追従に戻す。段数は保つ。
    mutating func followTail() {
        lastItemID = nil
    }

    /// 終端より新しい項目が無くなっていたら末尾追従に戻す（リバートや項目の除去の後）。
    /// 戻さないと、以後に届く項目が固定した窓の外に積まれ、最下部にいても描画されない。
    mutating func followTailIfNothingNewer(in items: [ChatItem]) {
        guard let lastItemID else { return }
        if items.last?.id == lastItemID || !items.contains(where: { $0.id == lastItemID }) {
            followTail()
        }
    }

    init(presentationContext: TranscriptPresentationContext = .single) {
        self.presentationContext = presentationContext
        self.limit = Self.defaultLimit(for: presentationContext)
    }

    /// 描画するブロックと、窓の前後で描画していないブロック数。
    /// 予算（ADR 0139）は窓の終端から古い側へ数える。終端の id が見つからなければ末尾に追従する。
    func slice(of items: [ChatItem], source: TranscriptBlockSource = .grouped) -> ChatTranscriptSlice {
        let end = lastItemID.flatMap { id in items.lastIndex { $0.id == id } }.map { $0 + 1 } ?? items.endIndex
        let isPinned = end < items.endIndex
        let candidate = isPinned
            ? source.pinned.visibleSlice(Array(items[..<end]), blockLimit: limit)
            : source.visibleSlice(items, blockLimit: limit)
        let count = TranscriptRenderBudget.allowedBlockCount(
            blocks: candidate.blocks.map(\.content),
            requestedLimit: limit,
            defaultLimit: contextDefaultLimit,
            minimumBlocks: TranscriptRenderBudget.minimumBlocks
        )
        let renderedAndOlder = candidate.hiddenBlockCount + candidate.blocks.count
        return ChatTranscriptSlice(
            blocks: Array(candidate.blocks.suffix(count)),
            hiddenBlockCount: renderedAndOlder - count,
            hiddenNewerBlockCount: isPinned ? source.blockCount(items) - renderedAndOlder : 0
        )
    }

    /// 上端で遡る（ADR 0217・0228）。上限未満なら段を足し、上限なら窓を 1 段分古い側へずらす。
    /// 戻り値は遡る前の先頭ブロックの id（位置を保つ目印）。遡る履歴がなければ何もせず nil。
    mutating func loadEarlier(in items: [ChatItem], source: TranscriptBlockSource = .grouped) -> String? {
        let current = slice(of: items, source: source)
        guard current.hiddenBlockCount > 0, let top = current.blocks.first else { return nil }
        guard limit >= maxLimit else {
            expand()
            return top.id
        }
        let blocks = current.blocks.map(\.content)
        let keep = source.inputBoundary(atOrBefore: blocks.count - stageCount(blocks.reversed()), in: blocks)
        if let pin = Self.itemID(before: blocks[keep], in: items) {
            lastItemID = pin
        }
        return top.id
    }

    /// 下端で引く（ADR 0228）。窓を 1 段分新しい側へずらし、末尾に届いたら追従に戻す。
    /// 戻り値は引く前の最後のブロックの id（位置を保つ目印）。新しい側を外していなければ nil。
    mutating func loadNewer(in items: [ChatItem], source: TranscriptBlockSource = .grouped) -> String? {
        guard lastItemID != nil else { return nil }
        let bottom = slice(of: items, source: source).blocks.last?.id
        let blocks = source.blocks(items)
        guard let last = blocks.firstIndex(where: { $0.id == bottom }) else {
            followTail()
            return nil
        }
        let end = source.inputBoundary(atOrAfter: last + 1 + stageCount(blocks[(last + 1)...]), in: blocks)
        lastItemID = end < blocks.count ? Self.itemID(before: blocks[end], in: items) : nil
        return bottom
    }

    /// 飛び先が窓の外なら、飛び先から新しい側へ上限より 1 段少ない分を描く窓にする（ADR 0228）。
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
        let end = source.inputBoundary(atOrAfter: target + count, in: blocks)
        limit = maxLimit
        lastItemID = end < blocks.count ? Self.itemID(before: blocks[end], in: items) : nil
        return true
    }

    /// ブロックの最初の項目の 1 つ前の項目 id（窓の終端にする）。
    private static func itemID(before block: ChatTranscriptBlock, in items: [ChatItem]) -> String? {
        guard let first = items.firstIndex(where: { block.contains(itemID: $0.id) }), first > items.startIndex else { return nil }
        return items[first - 1].id
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
