import Foundation
import DesignSystem

// PM3 task-6（監査 P2/P4）: ChatMessageCells の body 評価毎の重い再計算を潰すための
// 内容キー・メモ化キャッシュと FileChange 表示ポリシー。
//
// ── ハザード対策（tasks/task-6.md）──────────────────────────────────────────────
// H1 stale ヒット: キー = 入力文字列そのもの（内容同一性）。item.id や本文長は使わない。
//    → ストリーミングで本文が伸びても、同長別内容でも、キーが内容そのものなので取り違えが原理的に起きない。
// H2 ADR 0010（描画中の観測 state 変更で無効化ループ）: 保管は static NSCache（非観測ストレージ）。
//    SwiftUI の @Observable/@State/@ObservedObject を一切経由しないため、body 評価中に
//    キャッシュへ書き込んでも view 無効化を誘発しない（NSCache は SwiftUI の観測グラフに乗らない）。
// スレッド安全: NSCache 自体がスレッドセーフ。miss カウンタのみ NSLock で保護する
//    （ComposerSuggestionSourceCache と同じ @unchecked Sendable 方式）。

/// 入力文字列の「内容そのもの」をキーに計算結果をメモ化する汎用キャッシュ。
///
/// - キーは `String`（= 内容同一性）。NSCache のキーには NSString の内容等価性を使う。
/// - 値（構造体・AttributedString 等）は class Box に包んで NSCache に格納する。
/// - `missCount` は「実際に compute が走った回数」。メモ化が効いているかを白箱テストで観測するための計測値。
final class ContentMemoCache<Value>: @unchecked Sendable {
    private final class Box {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    private let cache = NSCache<NSString, Box>()
    private let lock = NSLock()
    private var misses = 0

    init() {
        // キー=全文内容のため、ストリーミング中の中間文字列が無制限に溜まると一時メモリが膨らむ。上限で LRU 退避させる。
        cache.countLimit = 512
    }

    /// 計測: compute（キャッシュミス）が走った回数。
    var missCount: Int {
        lock.withLock { misses }
    }

    /// `key` に対する結果を返す。未キャッシュなら `compute(key)` を1回だけ実行して格納する。
    func value(for key: String, compute: (String) -> Value) -> Value {
        let nsKey = key as NSString
        if let hit = cache.object(forKey: nsKey) {
            return hit.value
        }
        let computed = compute(key)
        lock.withLock { misses += 1 }
        cache.setObject(Box(computed), forKey: nsKey)
        return computed
    }
}

/// ChatMessageCells が body 評価で参照する派生値のメモ化窓口。
/// 各キャッシュはグローバルの `static let`（非観測）で、内容同一性をキーにする。
enum ChatMessageRenderCache {
    static let markdownCache = ContentMemoCache<[ChatMarkdownBlock]>()
    static let diffCache = ContentMemoCache<[ClassifiedDiffLine]>()
    static let highlightCache = ContentMemoCache<AttributedString>()

    /// fenced code block の分割（`ChatMarkdownFormatter.splitFencedCodeBlocks` をメモ化）。
    static func markdownBlocks(_ text: String) -> [ChatMarkdownBlock] {
        markdownCache.value(for: text) { ChatMarkdownFormatter.splitFencedCodeBlocks($0) }
    }

    /// diff 行分類（`DiffLineClassifier.classify` をメモ化）。
    static func diffLines(_ diff: String) -> [ClassifiedDiffLine] {
        diffCache.value(for: diff) { DiffLineClassifier.classify($0) }
    }

    /// シンタックスハイライト（`ChatCodeHighlighter.computeHighlight` をメモ化）。
    /// AttributedString は DSColor の解決済み Color を保持するため、キーには現在テーマも含める。
    static func highlightedCode(_ code: String) -> AttributedString {
        let key = highlightCacheKey(code: code, themeID: ThemeStore.active.id)
        return highlightCache.value(for: key) { _ in ChatCodeHighlighter.computeHighlight(code) }
    }

    static func highlightCacheKey(code: String, themeID: String) -> String {
        "\(themeID)\u{0}\(code)"
    }
}

/// FileChangeCell の表示ポリシー: 大きい diff は既定折りたたみ・表示行数に上限を持つ。
/// 閾値・上限はここで一元定義する（P4）。
enum FileChangeDisplayPolicy {
    /// 折りたたみ閾値: diff の総行数がこれを超えたら既定で折りたたむ。
    static let collapseThresholdLines: Int = 200
    /// 展開時に一度に描画する diff 行数の上限（超過分は「さらに表示」で展開する）。
    static let visibleLineLimit: Int = 500

    /// 既定展開の判定。閾値以下は展開、閾値超は折りたたみ。
    static func defaultExpanded(lineCount: Int) -> Bool {
        lineCount <= collapseThresholdLines
    }

    /// 表示中の展開状態を純導出する。ユーザーが明示トグルしていればそれを尊重（`userOverride`）、
    /// 未操作なら現在の行数から既定を導出する。
    /// これにより、同一 item.id のまま diff が置換され行数が変わっても（Cursor の started→completed 等）、
    /// 未操作なら既定折りたたみが自動追随する（`@State(initialValue:)` の identity 固定バグを回避）。
    static func isExpanded(userOverride: Bool?, lineCount: Int) -> Bool {
        userOverride ?? defaultExpanded(lineCount: lineCount)
    }
}
