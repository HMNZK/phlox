import AppKit
import ChatRenderKit
import DesignSystem
import SessionFeature

/// 字句計算は背景で行い、本文へ触れず前景色の差分だけを反映する。
@MainActor
final class CodeSyntaxHighlights {
    private struct Run: Sendable {
        var range: NSRange
        let kind: ChatCodeTokenKind
    }

    private struct Snapshot: Sendable {
        let code: String
        let runs: [Run]
        let path: String
        let themeID: String
        let viewID: ObjectIdentifier
    }

    private var work: Task<Void, Never>?
    private var generation = 0
    private var source: String?
    private var themeID: String?
    private var applied: Snapshot?
    private var editedRanges: [NSRange] = []
    private weak var currentView: NSTextView?
    private(set) var path = ""
    private(set) var isApplying = false
    var onApplicationBatch: ((Double) -> Void)?
    var onHighlightComplete: ((Double) -> Void)?
    var onBackgroundCalculation: ((Double) -> Void)?

    func cancel() {
        if isApplying { applied = nil }
        generation += 1
        work?.cancel()
        work = nil
        isApplying = false
        source = nil
    }

    func invalidate() {
        cancel()
        applied = nil
        editedRanges = []
        source = nil
    }

    func recordEdit(_ range: NSRange, replacementLength: Int) {
        let end = NSMaxRange(range)
        let delta = replacementLength - range.length
        var ranges = editedRanges.map { previous -> NSRange in
            let previousEnd = NSMaxRange(previous)
            if previousEnd <= range.location { return previous }
            if previous.location >= end {
                return NSRange(location: previous.location + delta, length: previous.length)
            }
            let start = min(previous.location, range.location)
            let finish = max(range.location + replacementLength, previousEnd + delta)
            return NSRange(location: start, length: finish - start)
        }
        ranges.append(NSRange(location: range.location, length: replacementLength))
        ranges.sort { $0.location < $1.location }
        editedRanges = []
        for range in ranges {
            if let last = editedRanges.last, NSMaxRange(last) >= range.location {
                editedRanges[editedRanges.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                editedRanges.append(range)
            }
        }
        source = nil
    }

    func update(_ view: NSTextView, path: String, debounce: Bool = false) {
        let code = view.string
        let theme = ThemeStore.active.id
        if currentView !== view { applied = nil }
        if view.hasMarkedText() {
            if editedRanges.isEmpty { invalidate() }
            else { cancel() }
            currentView = view
            self.path = path
            return
        }
        guard currentView !== view || source.map({ ($0 as NSString).isEqual(to: code) }) != true
                || self.path != path || themeID != theme else { return }
        cancel()
        self.path = path
        currentView = view
        source = code
        themeID = theme
        let revision = generation
        let viewID = ObjectIdentifier(view)
        let previous = applied.flatMap {
            $0.path == path && $0.themeID == theme && $0.viewID == viewID ? $0 : nil
        }
        let edits = editedRanges
        let start = ContinuousClock.now
        work = Task { [weak self, weak view] in
            if debounce {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            let calculation = Task.detached(priority: .userInitiated) {
                let calculationStart = ContinuousClock.now
                let scanCode = String(decoding: code.utf8, as: UTF8.self)
                var runs: [Run] = []
                var location = 0
                for token in ChatCodeTokenizer.tokens(for: scanCode, path: path) {
                    if Task.isCancelled { return (scanCode, [Run](), [Run](), 0.0) }
                    let length = token.text.utf16.count
                    if length == 0 { continue }
                    if let last = runs.last, last.kind == token.kind {
                        runs[runs.count - 1].range.length += length
                    } else {
                        runs.append(Run(range: NSRange(location: location, length: length), kind: token.kind))
                    }
                    location += length
                }
                // 長いコメント等も、一回の属性操作が文書全体へ広がらないよう分ける。
                let original = scanCode as NSString
                var pieces: [Run] = []
                pieces.reserveCapacity(runs.count)
                for run in runs {
                    if run.range.length <= 4_096 {
                        pieces.append(run)
                        continue
                    }
                    var offset = run.range.location
                    let end = NSMaxRange(run.range)
                    while offset < end {
                        let proposed = min(end, offset + 4_096)
                        let boundary = proposed < end
                            ? min(end, NSMaxRange(original.rangeOfComposedCharacterSequence(at: proposed - 1)))
                            : end
                        pieces.append(Run(range: NSRange(location: offset, length: boundary - offset), kind: run.kind))
                        offset = boundary
                    }
                }
                let changed = previous.map { Self.changedRuns(pieces, code: scanCode, previous: $0, edits: edits) } ?? pieces
                return (scanCode, pieces, changed, Self.milliseconds(since: calculationStart))
            }
            let result = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }
            guard let self, let view, !Task.isCancelled, self.generation == revision else { return }
            self.onBackgroundCalculation?(result.3)
            guard !Task.isCancelled, self.generation == revision else { return }
            self.applied = nil
            self.editedRanges = []
            self.isApplying = true
            let applied = await self.apply(result.2, to: view, revision: revision, code: code)
            guard self.generation == revision else { return }
            self.isApplying = false
            guard applied, !Task.isCancelled else { self.source = nil; return }
            self.applied = Snapshot(code: result.0, runs: result.1, path: path, themeID: theme, viewID: viewID)
            self.onHighlightComplete?(Self.milliseconds(since: start))
        }
    }

    /// 共通部分の一時属性は AppKit の編集による移動を利用し、変化した字句だけを返す。
    nonisolated private static func changedRuns(_ runs: [Run], code: String, previous: Snapshot, edits: [NSRange]) -> [Run] {
        let old = Array(previous.code.utf16)
        let new = Array(code.utf16)
        let shared = min(old.count, new.count)
        var prefix = 0
        while prefix < shared, old[prefix] == new[prefix] {
            prefix += 1
            if prefix & 4_095 == 0, Task.isCancelled { return [] }
        }
        // 削除して同じ文字を再入力した場合は、本文が同じでも一時属性が失われ得る。
        if prefix == old.count, prefix == new.count { return runs }
        let oldText = previous.code as NSString
        let newText = code as NSString
        for text in [oldText, newText] where prefix < text.length {
            prefix = min(prefix, text.rangeOfComposedCharacterSequence(at: prefix).location)
        }
        if prefix > 0, prefix < shared, old[prefix - 1] == 13, old[prefix] == 10 { prefix -= 1 }
        var suffix = 0
        while suffix < shared - prefix, old[old.count - suffix - 1] == new[new.count - suffix - 1] {
            suffix += 1
            if suffix & 4_095 == 0, Task.isCancelled { return [] }
        }
        var adjustment = 1
        while suffix > 0, adjustment > 0 {
            adjustment = 0
            for text in [oldText, newText] {
                let boundary = text.length - suffix
                let range = text.rangeOfComposedCharacterSequence(at: boundary)
                if range.location < boundary { adjustment = max(adjustment, NSMaxRange(range) - boundary) }
                if boundary > 0, text.character(at: boundary - 1) == 13, text.character(at: boundary) == 10 {
                    adjustment = max(adjustment, 1)
                }
            }
            suffix -= min(suffix, adjustment)
        }
        let oldEnd = old.count - suffix
        let newEnd = new.count - suffix
        let delta = new.count - old.count
        // 編集で属性を継承・除去される可能性がある段落は、同じ種類でも反映する。
        var dirty = edits.map { range in
            let start = min(range.location, newText.length)
            let length = min(range.length, newText.length - start)
            return newText.lineRange(for: NSRange(location: start, length: length))
        }
        dirty.append(newText.lineRange(for: NSRange(location: prefix, length: newEnd - prefix)))
        dirty.sort { $0.location < $1.location }
        var paragraphs: [NSRange] = []
        for range in dirty {
            if let last = paragraphs.last, NSMaxRange(last) >= range.location {
                paragraphs[paragraphs.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                paragraphs.append(range)
            }
        }
        var mapped: [Run] = []
        mapped.reserveCapacity(previous.runs.count)
        for run in previous.runs {
            let start = run.range.location
            let end = NSMaxRange(run.range)
            if start < prefix {
                mapped.append(Run(range: NSRange(location: start, length: min(end, prefix) - start), kind: run.kind))
            }
            if end > oldEnd {
                let tail = max(start, oldEnd)
                mapped.append(Run(range: NSRange(location: tail + delta, length: end - tail), kind: run.kind))
            }
        }
        var changed: [Run] = []
        var oldIndex = 0
        for run in runs {
            var offset = run.range.location
            let end = NSMaxRange(run.range)
            while offset < end {
                while oldIndex < mapped.count, NSMaxRange(mapped[oldIndex].range) <= offset { oldIndex += 1 }
                let previous = oldIndex < mapped.count ? mapped[oldIndex] : nil
                let boundary: Int
                let same: Bool
                if let previous, previous.range.location <= offset {
                    boundary = min(end, NSMaxRange(previous.range))
                    same = previous.kind == run.kind
                } else {
                    boundary = min(end, previous?.range.location ?? end)
                    same = false
                }
                let span = NSRange(location: offset, length: boundary - offset)
                if same {
                    for paragraph in paragraphs {
                        if paragraph.location >= NSMaxRange(span) { break }
                        let range = NSIntersectionRange(span, paragraph)
                        if range.length > 0 { changed.append(Run(range: range, kind: run.kind)) }
                    }
                } else {
                    changed.append(Run(range: span, kind: run.kind))
                }
                offset = boundary
            }
        }
        return changed
    }

    private func apply(_ runs: [Run], to view: NSTextView, revision: Int, code: String) async -> Bool {
        let initialStart = ContinuousClock.now
        guard let storage = view.textStorage, let layout = view.layoutManager else { return false }
        let length = code.utf16.count
        guard !view.hasMarkedText(), (view.string as NSString).isEqual(to: code) else { return false }
        var index = 0
        var colors: [(ChatCodeTokenKind, NSColor)] = []
        while index < runs.count {
            let start = index == 0 ? initialStart : ContinuousClock.now
            guard !Task.isCancelled, generation == revision else { return false }
            // 本文同期と編集通知は同じ MainActor 上で世代を更新する。
            // yield ごとの全文比較は大きな文書の入力を妨げるため行わない。
            guard !view.hasMarkedText(), storage.length == length else {
                source = nil
                isApplying = false
                return false
            }
            let selection = view.selectedRanges
            let origin = view.enclosingScrollView?.contentView.bounds.origin
            let typing = view.typingAttributes
            repeat {
                let run = runs[index]
                let color: NSColor?
                if run.kind == .plain {
                    color = nil
                } else {
                    var cached: NSColor?
                    for entry in colors {
                        if entry.0 == run.kind {
                            cached = entry.1
                            break
                        }
                    }
                    if let cached {
                        color = cached
                    } else {
                        let resolved = NSColor(CodeSyntaxColor.color(for: run.kind))
                        colors.append((run.kind, resolved))
                        color = resolved
                    }
                }
                // 表示だけの属性を使い、本文のフォント属性を断片化しない。
                var offset = run.range.location
                while offset < NSMaxRange(run.range) {
                    var effective = NSRange()
                    let value = layout.temporaryAttribute(.foregroundColor, atCharacterIndex: offset,
                                                          effectiveRange: &effective)
                    let range = NSIntersectionRange(effective, run.range)
                    if let color {
                        if (value as? NSColor) != color {
                            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
                        }
                    } else if value != nil {
                        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
                    }
                    offset = NSMaxRange(range)
                }
                index += 1
            } while index < runs.count && Self.milliseconds(since: start) < 4
            if view.selectedRanges != selection { view.selectedRanges = selection }
            if !NSDictionary(dictionary: view.typingAttributes).isEqual(NSDictionary(dictionary: typing)) {
                view.typingAttributes = typing
            }
            if let origin, let clip = view.enclosingScrollView?.contentView, clip.bounds.origin != origin {
                clip.scroll(to: origin)
            }
            let matches = index != runs.count || (view.string as NSString).isEqual(to: code)
            onApplicationBatch?(Self.milliseconds(since: start))
            if !matches { return false }
            if index < runs.count { await Task.yield() }
        }
        return !view.hasMarkedText()
    }

    nonisolated private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }
}
