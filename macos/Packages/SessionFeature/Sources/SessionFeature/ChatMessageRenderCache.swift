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
    static let diffCodeCache = ContentMemoCache<DiffCodeViewData>()
    static let shellHighlightCache = ContentMemoCache<AttributedString>()
    static let commandExecutionCache = ContentMemoCache<CommandGroupExecutionDisplayData>()

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

    static func highlightedShell(_ command: String) -> AttributedString {
        let key = "\(ThemeStore.active.id)\u{0}shell\u{0}\(command)"
        return shellHighlightCache.value(for: key) { _ in ChatCodeHighlighter.computeShellHighlight(command) }
    }

    static func commandExecution(command: String?, output: String) -> CommandGroupExecutionDisplayData {
        let commandText = command ?? ""
        let key = "\(ThemeStore.active.id)\u{0}\(commandText)\u{0}\(output)"
        return commandExecutionCache.value(for: key) { _ in
            CommandGroupExecutionDisplayData(command: command, output: output)
        }
    }

    /// diff の行番号・表示可否・構文ハイライトを内容とパス単位でメモ化する。
    static func diffCodeView(diff: String, path: String) -> DiffCodeViewData {
        let key = "\(ThemeStore.active.id)\u{0}\(path)\u{0}\(diff)"
        return diffCodeCache.value(for: key) { _ in
            DiffCodeViewData(diff: diff, path: path)
        }
    }
}

struct DiffCodeViewData {
    let lines: [DiffCodeLine]
    let hasLineNumbers: Bool
    let lineNumberWidth: Int
    /// hunk・ファイルヘッダを除いた表示対象の行数。
    let sourceLineCount: Int

    init(lines: [DiffCodeLine], hasLineNumbers: Bool, lineNumberWidth: Int, sourceLineCount: Int) {
        self.lines = lines
        self.hasLineNumbers = hasLineNumbers
        self.lineNumberWidth = lineNumberWidth
        self.sourceLineCount = sourceLineCount
    }

    init(diff: String, path: String) {
        let classified = DiffLineClassifier.classify(diff)
        lines = classified.filter { $0.isDisplayable && $0.kind != .hunk }.map { line in
            DiffCodeLine(
                line: line,
                body: ChatCodeHighlighter.computeDiffHighlight(line.diffBody, path: path)
            )
        }
        let numbers = lines.compactMap { $0.line.displayLineNumber }
        hasLineNumbers = !numbers.isEmpty
        lineNumberWidth = numbers.map { String($0).count }.max() ?? 0
        sourceLineCount = lines.count
    }

    func prefix(sourceLineCount: Int) -> DiffCodeViewData {
        DiffCodeViewData(
            lines: Array(lines.prefix(sourceLineCount)),
            hasLineNumbers: hasLineNumbers,
            lineNumberWidth: lineNumberWidth,
            sourceLineCount: min(self.sourceLineCount, sourceLineCount)
        )
    }
}

struct DiffCodeLine: Identifiable {
    let line: ClassifiedDiffLine
    let body: AttributedString

    var id: Int { line.id }
}

extension ClassifiedDiffLine {
    /// 先頭の diff マーカーを除いた、構文ハイライト対象の本文。
    var diffBody: String {
        switch kind {
        case .addition, .deletion:
            String(text.dropFirst())
        case .context:
            text.first == " " ? String(text.dropFirst()) : text
        case .fileHeader, .hunk:
            text
        }
    }
}

/// FileChangeCell の表示ポリシー: diff は既定折りたたみ・表示行数に上限を持つ。
enum FileChangeDisplayPolicy {
    /// transcript の描画予算算定で使う重み判定。カードの既定展開状態には使わない。
    static let collapseThresholdLines: Int = 200
    /// 展開時に一度に描画する diff 行数の上限（超過分は「さらに表示」で展開する）。
    static let visibleLineLimit: Int = 500

    /// transcript の描画予算用の従来判定。カード表示は `isExpanded` が常に折りたたみを返す。
    static func defaultExpanded(lineCount: Int) -> Bool {
        lineCount <= collapseThresholdLines
    }

    /// 表示中の展開状態を純導出する。ユーザーが明示トグルしていればそれを尊重（`userOverride`）、
    /// 未操作なら常に折りたたむ。
    static func isExpanded(userOverride: Bool?, lineCount: Int) -> Bool {
        userOverride ?? false
    }
}
