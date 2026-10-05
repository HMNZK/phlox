import AppKit
import ChatRenderKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("ソース色付けの再現可能な性能測定", .serialized)
@MainActor
struct CodeSyntaxPerformanceTests {
    private static let samples: [(String, String)] = [
        ("swift", "let n = 42; let title = \"sample\" // コメント\nlet block = \"\"\"\n複数行文字列\n\"\"\"\n"),
        ("ime.swift", "let n = 42; let title = \"sample\" // コメント\nlet block = \"\"\"\n複数行文字列\n\"\"\"\n"),
        ("json", "{\"id\":42,\"name\":\"sample\",\"enabled\":true,\"values\":[1,2,3,null]}\n"),
        ("md", "# 見出し\n本文 **強調** と [参照](https://example.com)\n```swift\nlet block = \"\"\"\n複数行文字列\n\"\"\"\n```\n"),
        ("mixed.md", "# 見出し\n```swift\nlet s = \"\"\"\n複数行文字列\n\"\"\"\n```\n```json\n{\"a\":1,\"b\":true}\n```\n```html\n<div class=\"a\"><script>const n = 42;</script></div>\n```\n```yaml\nname: sample\nitems: [1, 2]\n```\n")
    ]

    @Test
    func oversizedAndLongLineDocumentsRemainPlain() {
        for text in [String(repeating: "let x = 1\n", count: 100_001), "let x = \"" + String(repeating: "x", count: 10_001)] {
            let tokens = ChatCodeTokenizer.tokens(for: text, path: "fixture.swift")
            #expect(tokens.map(\.text).joined() == text)
            #expect(tokens.allSatisfy { $0.kind == .plain })
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHLOX_SYNTAX_PERFORMANCE"] == "1"))
    func measureEditorInputAndHighlightCompletion() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent(".build/syntax-performance.json")
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        var theme = arguments
        theme[ThemeStore.themeKey] = AppTheme.phlox.id
        defaults.setVolatileDomain(theme, forName: UserDefaults.argumentDomain)
        var results: [[String: Any]] = []
        var failed = false
        for (path, unit) in Self.samples {
            let isIME = path == "ime.swift"
            for size in isIME ? [1_000_000] : [10_000, 100_000, 1_000_000] {
                let fixture = Self.fixture(unit, bytes: size)
                let fixtureRoot = root.appendingPathComponent(".build/syntax-performance-fixtures")
                try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
                let filename = "fixture.\(path)"
                try Data(fixture.utf8).write(to: fixtureRoot.appendingPathComponent(filename))
                let state = FileTabDocument(path: filename, root: fixtureRoot.path)
                await state.loadIfNeeded()
                #expect(state.isLoaded)
                #expect(state.setPresentation(.source))
                let record = Measurements()
                let plainHostSync = try Self.plainEditorCreationTime(state)
                let hostStart = ContinuousClock.now
                let host = NSHostingView(rootView: CodeTextEditor(
                    getText: { state.draft }, setText: {
                        let start = ContinuousClock.now
                        state.draft = $0
                        record.bindingUpdates.append(Self.milliseconds(since: start))
                    }, path: filename))
                host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
                host.layoutSubtreeIfNeeded()
                let view = try #require(Self.editor(in: host))
                let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
                let hostSync = Self.milliseconds(since: hostStart)
                coordinator.highlights.onApplicationBatch = { record.batches.append($0) }
                coordinator.highlights.onBackgroundCalculation = { record.backgrounds.append($0) }
                coordinator.highlights.onHighlightComplete = { _ in
                    record.completedAt = ContinuousClock.now
                    record.completed = true
                }
                let initialStart = ContinuousClock.now
                // makeNSView で開始した初回計算の完了を、そのまま観測する。
                try await waitForCompletion(record, context: "\(path) \(size) 初回")
                let initialCompletion = Self.milliseconds(from: initialStart, to: try #require(record.completedAt))
                let initialBatch = Self.percentile95(record.batches)
                let initialBackground = record.backgrounds.last ?? 0
                // 元の入力欄を組み立てる費用と、色付けの背景計算を予約する同期処理を分ける。
                let coldHighlights = CodeSyntaxHighlights()
                let schedulingStart = ContinuousClock.now
                coldHighlights.update(view, path: filename)
                let initialScheduling = Self.milliseconds(since: schedulingStart)
                coldHighlights.cancel()
                var themeBatches: [Double] = []
                var themeCompletions: [Double] = []
                var themeUpdates: [Double] = []
                for selectedTheme in [AppTheme.phloxLight.id, AppTheme.phlox.id] {
                    record.completed = false
                    record.batches.removeAll(keepingCapacity: true)
                    theme[ThemeStore.themeKey] = selectedTheme
                    defaults.setVolatileDomain(theme, forName: UserDefaults.argumentDomain)
                    let start = ContinuousClock.now
                    coordinator.updateHighlights(view, path: filename)
                    themeUpdates.append(Self.milliseconds(since: start))
                    try await waitForCompletion(record, context: "\(path) \(size) テーマ")
                    themeCompletions.append(Self.milliseconds(from: start, to: try #require(record.completedAt)))
                    themeBatches.append(contentsOf: record.batches)
                }
                var measuredSizes: [Int] = []
                for index in 0..<110 {
                    let operation = (index / 3) % 3
                    let deletion = !isIME && operation == 1
                    let replacement = isIME ? "日本語" : deletion ? "" : operation == 0 ? "x" : "\nlet pasted = 123\n"
                    var prepared = fixture
                    while prepared.utf8.count + replacement.utf8.count > size { prepared.removeLast() }
                    if view.string != prepared {
                        record.completed = false
                        let delta = Self.difference(from: view.string, to: prepared)
                        view.insertText(delta.text, replacementRange: delta.range)
                        try await waitForCompletion(record, context: "\(path) \(size) 準備 \(index)")
                    }
                    let position = [0, view.string.utf16.count / 2, view.string.utf16.count][index % 3]
                    let location = deletion ? min(position, max(0, view.string.utf16.count - 1)) : position
                    let range = NSRange(location: location, length: deletion ? 1 : 0)
                    // 入力前にカーソル位置と可視範囲を整え、移動に伴うレイアウトを計時へ混ぜない。
                    view.setSelectedRange(range)
                    view.scrollRangeToVisible(range)
                    if let container = view.textContainer {
                        let visible = view.visibleRect.offsetBy(dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y)
                        view.layoutManager?.ensureLayout(forBoundingRect: visible, in: container)
                    }
                    try await Task.sleep(for: .milliseconds(1))
                    if isIME {
                        view.setMarkedText("にほんご", selectedRange: NSRange(location: 4, length: 0), replacementRange: range)
                        view.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                        #expect(view.hasMarkedText())
                    }
                    record.completed = false
                    record.batches.removeAll(keepingCapacity: true)
                    record.bindingUpdates.removeAll(keepingCapacity: true)
                    record.backgrounds.removeAll(keepingCapacity: true)
                    let start = ContinuousClock.now
                    view.insertText(replacement, replacementRange: isIME ? NSRange(location: NSNotFound, length: 0) : range)
                    let input = Self.milliseconds(since: start)
                    if isIME { #expect(!view.hasMarkedText()) }
                    let documentUpdate = record.bindingUpdates.reduce(0, +)
                    try await waitForCompletion(record, context: "\(path) \(size) 操作 \(index)")
                    let completion = Self.milliseconds(from: start, to: try #require(record.completedAt))
                    // 原文の検証は完了時刻を確定してから行い、背景 Task の開始を遅らせない。
                    #expect(Data(state.draft.utf8) == Data(view.string.utf8))
                    if index >= 10 {
                        record.inputs.append(input)
                        record.documentUpdates.append(documentUpdate)
                        record.otherInputWork.append(input - documentUpdate)
                        record.completions.append(completion)
                        record.measuredBatches.append(contentsOf: record.batches)
                        record.measuredBackgrounds.append(contentsOf: record.backgrounds)
                        measuredSizes.append(view.string.utf8.count)
                    }
                }
                coordinator.highlights.cancel()
                withExtendedLifetime(host) {}
                let input = Self.percentile95(record.inputs)
                let batch = Self.percentile95(record.measuredBatches)
                let completion = Self.percentile95(record.completions)
                let themeBatch = Self.percentile95(themeBatches)
                let themeUpdate = Self.percentile95(themeUpdates)
                let passed = input <= 16 && batch <= 16 && initialBatch <= 16 && themeBatch <= 16
                    && themeUpdate <= 16 && initialScheduling <= 16 && completion <= 150
                failed = failed || !passed
                let row: [String: Any] = ["種類": path, "バイト数": size, "入力回数": record.inputs.count,
                    "操作後最小バイト数": measuredSizes.min() ?? 0, "操作後最大バイト数": measuredSizes.max() ?? 0,
                    "属性適用回数": record.measuredBatches.count, "入力p95_ms": input,
                    "文書setter_p95_ms": Self.percentile95(record.documentUpdates),
                    "文書setter以外の入力p95_ms": Self.percentile95(record.otherInputWork),
                    "初回属性適用p95_ms": initialBatch, "初回完了_ms": initialCompletion,
                    "初回背景計算_ms": initialBackground, "編集背景計算p95_ms": Self.percentile95(record.measuredBackgrounds),
                    "plain入力欄生成とlayout_ms": plainHostSync, "初回入力欄生成とlayout_ms": hostSync,
                    "初回色付け同期予約_ms": initialScheduling,
                    "テーマ切替属性適用p95_ms": themeBatch, "テーマ切替完了_ms": themeCompletions,
                    "テーマ切替同期更新p95_ms": themeUpdate,
                    "属性適用p95_ms": batch, "完了p95_ms": completion, "基準達成": passed]
                results.append(row)
                print("性能 \(path) \(size) byte: 入力 \(input) ms、属性適用 \(batch) ms、完了 \(completion) ms、達成 \(passed)")
                try save(results, to: output)
            }
        }
        #expect(!failed, "性能基準未達。数値は \(output.path)")
    }

    private final class Measurements {
        var completed = false
        var completedAt: ContinuousClock.Instant?
        var batches: [Double] = []
        var inputs: [Double] = []
        var completions: [Double] = []
        var measuredBatches: [Double] = []
        var bindingUpdates: [Double] = []
        var documentUpdates: [Double] = []
        var otherInputWork: [Double] = []
        var backgrounds: [Double] = []
        var measuredBackgrounds: [Double] = []
    }

    private func waitForCompletion(_ record: Measurements, context: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !record.completed {
            guard ContinuousClock.now < deadline else { throw MeasurementError.timeout(context) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private enum MeasurementError: Error { case timeout(String) }

    private static func editor(in view: NSView) -> CurrentLineTextView? {
        if let editor = view as? CurrentLineTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    private static func plainEditorCreationTime(_ document: FileTabDocument) throws -> Double {
        let start = ContinuousClock.now
        let host = NSHostingView(rootView: CodeTextEditor(
            getText: { document.draft }, setText: { document.draft = $0 }, path: "baseline.txt"))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        let view = try #require(editor(in: host))
        let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
        let duration = milliseconds(since: start)
        coordinator.highlights.cancel()
        withExtendedLifetime(host) {}
        return duration
    }

    private static func difference(from source: String, to target: String) -> (range: NSRange, text: String) {
        let before = Array(source.utf16)
        let after = Array(target.utf16)
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        // 差分の端が UTF-16 のサロゲートペアの途中に来たら、両方を置き換える。
        if prefix > 0, prefix < before.count, (0xD800...0xDBFF).contains(before[prefix - 1]) {
            prefix -= 1
        }
        if suffix > 0, before.count > suffix, (0xDC00...0xDFFF).contains(before[before.count - suffix]) {
            suffix -= 1
        }
        let range = NSRange(location: prefix, length: before.count - prefix - suffix)
        let text = String(decoding: after[prefix..<(after.count - suffix)], as: UTF16.self)
        return (range, text)
    }

    private static func fixture(_ unit: String, bytes: Int) -> String {
        let count = bytes / unit.utf8.count
        let text = String(repeating: unit, count: count)
        // 末尾の余りは短いコメント行にし、UTF-8 の途中で切らない。
        let remainder = bytes - text.utf8.count
        return text + String(repeating: " \n", count: remainder / 2) + (remainder % 2 == 0 ? "" : " ")
    }

    private static func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[Int(ceil(Double(values.count) * 0.95)) - 1]
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        milliseconds(from: start, to: .now)
    }

    private static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: end).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private func save(_ rows: [[String: Any]], to output: URL) throws {
        var machine = utsname()
        uname(&machine)
        let capacity = MemoryLayout.size(ofValue: machine.machine)
        let model = withUnsafePointer(to: &machine.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        let payload: [String: Any] = ["機種": Self.hardware("hw.model"), "CPU": Self.hardware("machdep.cpu.brand_string"),
            "アーキテクチャ": model, "OS": ProcessInfo.processInfo.operatingSystemVersionString,
            "構成": Self.configuration, "ウォームアップ回数": 10, "測定": rows]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }

    private static func hardware(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return "確認できず" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "確認できず" }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static var configuration: String {
        #if DEBUG
        "Swift Package Debug"
        #else
        "Swift Package Release"
        #endif
    }
}
