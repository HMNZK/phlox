import Foundation

// PM3 task-8 純ロジック（ADR 0030:22 の規定対処）。
// 非 Lazy VStack を維持したまま「末尾 N 件のみ描画」の件数制限を担う純粋な値型。
// - items ≤ limit なら全件、超過時は末尾 limit 件＋隠れ件数。
// - expand() はユーザー操作（「以前のメッセージを表示」ボタン）でのみ呼ばれ、limit が step 分増える。
// - reset() はセッション切替時に既定へ戻す。
//
// 設計の一線（ADR 0030 再入禁止）: この型はスクロール量・可視領域・GeometryReader 計測を
// 一切参照しない。window の拡張契機は expand() の明示呼び出し（＝ボタン操作）のみで、
// レイアウト観測フィードバックに連動しない。visibleRange は totalCount のみから決まる純関数なので、
// ストリーミングで item が増えても末尾を含み続ける（AutoFollow と自然に整合する）。
struct TranscriptWindow: Equatable {
    /// 既定の表示件数上限（50...500 の範囲の有限定数）。
    static let defaultLimit: Int = 200
    /// 「以前のメッセージを表示」1回あたりの拡張幅（50 以上の定数）。
    static let expandStep: Int = 200

    private(set) var limit: Int = TranscriptWindow.defaultLimit

    /// 表示すべき末尾スライスの開始 index と隠れ件数を返す。
    /// - Parameter totalCount: 全 item 数（負は想定しないが 0 で安全）。
    /// - Returns: (startIndex: 表示開始位置 = 隠れ件数, hiddenCount: 隠れている先頭側の件数)。
    ///   totalCount ≤ limit のとき (0, 0)。超過時は (totalCount - limit, totalCount - limit)。
    ///   隠れ件数は負にならない（クランプ）。startIndex は常に 0...totalCount に収まり、
    ///   表示件数 = totalCount - startIndex = min(totalCount, limit)。
    func visibleRange(totalCount: Int) -> (startIndex: Int, hiddenCount: Int) {
        let hidden = max(0, totalCount - limit)
        return (startIndex: hidden, hiddenCount: hidden)
    }

    /// ユーザー操作でのみ呼ぶ: 表示件数を step 分増やす（単調増加・縮まない）。
    mutating func expand() {
        limit += TranscriptWindow.expandStep
    }

    /// セッション切替時に既定へ戻す。
    mutating func reset() {
        limit = TranscriptWindow.defaultLimit
    }

    /// ユーザー起点のジャンプでのみ呼ぶ: 指定 index が可視スライスに含まれるまで limit を引き上げる。
    /// 既に可視なら何もしない。scroll 量・可視領域には連動しない（ADR 0030）——契機はジャンプ操作のみ。
    ///
    /// index `i` が可視 ⇔ `i >= totalCount - limit`（＝ `limit >= totalCount - i`）。
    /// 隠れ域のときだけ limit を `(totalCount - index) + expandStep` へ引き上げる。
    /// **マージン（+expandStep）の理由（stage2 指摘）**: reveal と遅延 scrollTo の間に
    /// ストリーミングで item が増えると startIndex が前進し、ぴったり `totalCount - index` では
    /// ターゲットが再び隠れ域へ落ちて scrollTo が no-op になる。expandStep 件までの成長に耐える
    /// 余裕を持たせる。既に可視の index では limit を一切変えない（no-op）。単調増加・縮まない。
    mutating func reveal(index: Int, totalCount: Int) {
        guard index >= 0, index < totalCount else { return }
        let currentStart = max(0, totalCount - limit)
        guard index < currentStart else { return } // 既に可視 → no-op（limit 不変）
        let requiredLimit = (totalCount - index) + TranscriptWindow.expandStep
        if limit < requiredLimit {
            limit = requiredLimit
        }
    }
}
