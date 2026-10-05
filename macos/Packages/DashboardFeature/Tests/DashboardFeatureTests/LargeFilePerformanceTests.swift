import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("大きいファイルタブの更新性能", .serialized)
@MainActor
struct LargeFilePerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHLOX_LARGE_FILE_PERFORMANCE"] == "1"))
    func measureDocumentAndSwiftUIUpdates() async throws {
        #if DEBUG
        Issue.record("ファイルタブの性能は -c release で計測してください")
        #else
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent(".build/large-file-performance")
        let fixtures = output.appendingPathComponent("document-fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        var names: [String] = []
        let environment = ProcessInfo.processInfo.environment
        let sizes = environment["PHLOX_LARGE_FILE_SIZES"]?.split(separator: ",").compactMap { Int($0) }
            ?? [1, 2, 5, 10, 20, 50]
        for size in sizes {
            let name = "\(size)MB.swift"
            let unit = "let number = 42 // sample\n"
            let bytes = size * 1_000_000
            let text = String(repeating: unit, count: bytes / unit.utf8.count)
                + String(repeating: " ", count: bytes % unit.utf8.count)
            try Data(text.utf8).write(to: fixtures.appendingPathComponent(name))
            names.append(name)
        }
        for name in ["real-550KB.html", "real-6.6MB.html"] {
            if environment["PHLOX_LARGE_FILE_SYNTHETIC_ONLY"] == "1" { continue }
            let sample = URL(fileURLWithPath: "/tmp/large-file-samples/\(name)")
            if FileManager.default.fileExists(atPath: sample.path) {
                try Data(contentsOf: sample).write(to: fixtures.appendingPathComponent(name))
                names.append(name)
            } else { print("実ファイル未提供のため計測対象外: \(sample.path)") }
        }
        var rows: [[String: Any]] = []
        for name in names {
            let start = ContinuousClock.now
            let document = FileTabDocument(path: name, root: fixtures.path)
            await document.loadIfNeeded()
            let load = Self.ms(start)
            let bytes = try Data(contentsOf: fixtures.appendingPathComponent(name))
            if bytes.count > WorkingTreeText.maximumReadableFileSize {
                #expect(document.loadState == .tooLarge)
                rows.append(["文書": name, "バイト数": bytes.count, "拒否": true, "読込判定_ms": load])
                continue
            }
            #expect(document.isLoaded)
            #expect(document.setPresentation(.source))
            let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
                isFocused: false, openFile: { _, _ in }))
            host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            let view = try #require(Self.editor(host))
            let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
            var completedAt: ContinuousClock.Instant?
            coordinator.highlights.onHighlightComplete = { _ in completedAt = .now }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            if WorkingTreeText.shouldHighlight(document.draft, bomByteCount: document.bom.count) {
                try await wait { completedAt != nil }
            } else { await Task.yield() }
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let opening = Self.ms(start)
            if document.isReadOnly {
                #expect(!view.isEditable)
                #expect(view.isSelectable)
                #expect(view.undoManager == nil)
                let scroll = try #require(view.enclosingScrollView)
                let initialOrigin = scroll.contentView.bounds.origin
                var frames: [Double] = []
                var slowestFrame = (location: 0, move: 0.0, draw: 0.0)
                for position in 0..<3 {
                    for iteration in 0..<25 {
                        let location = (view.textStorage!.length - 1) * (position * 25 + iteration) / 74
                        let frameStart = ContinuousClock.now
                        view.scrollRangeToVisible(NSRange(location: location, length: 1))
                        let move = Self.ms(frameStart)
                        host.layoutSubtreeIfNeeded()
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let duration = Self.ms(frameStart)
                        if duration > (frames.max() ?? 0) {
                            slowestFrame = (location, move, duration - move)
                        }
                        frames.append(duration)
                    }
                }
                #expect(scroll.contentView.bounds.origin != initialOrigin)
                if name == "real-6.6MB.html" {
                    #expect(document.readOnlyText?.hasOmittedLines == true)
                    #expect(frames.max()! <= 100, "実6.6 MBの初回を含むスクロール最大は100 ms以内")
                }
                #expect(!document.hasUnsavedChanges)
                #expect(try Data(contentsOf: fixtures.appendingPathComponent(name)) == bytes)
                coordinator.highlights.cancel()
                rows.append(["文書": name, "バイト数": bytes.count, "拒否": false, "閲覧のみ": true,
                    "読込_ms": load, "開く_ms": opening, "スクロールフレームp95_ms": Self.p95(frames),
                    "スクロールフレーム最大_ms": frames.max()!, "スクロール回数": frames.count,
                    "最遅位置_UTF16": slowestFrame.location, "最遅移動_ms": slowestFrame.move,
                    "最遅描画_ms": slowestFrame.draw])
                print("ファイルタブ計測: \(rows.last!)")
                withExtendedLifetime(host) {}
                continue
            }
            let tail = (view.string as NSString).rangeOfComposedCharacterSequence(at: view.textStorage!.length - 1)
            completedAt = nil
            view.insertText("", replacementRange: tail)
            if WorkingTreeText.shouldHighlight(document.draft, bomByteCount: document.bom.count) {
                try await wait { completedAt != nil }
            } else { await Task.yield() }
            host.layoutSubtreeIfNeeded()
            view.undoManager?.removeAllActions()
            let baseline = Data(document.draft.utf8)
            var input: [Double] = []
            var redraw: [Double] = []
            var dirty: [Double] = []
            var completions: [Double] = []
            for position in 0..<3 {
                for iteration in 0..<25 {
                    let range = NSRange(location: [0, view.textStorage!.length / 2, view.textStorage!.length][position], length: 0)
                    view.setSelectedRange(range)
                    view.scrollRangeToVisible(range)
                    host.layoutSubtreeIfNeeded()
                    completedAt = nil
                    let start = ContinuousClock.now
                    view.insertText("x", replacementRange: range)
                    let duration = Self.ms(start)
                    try await Task.sleep(for: .milliseconds(1))
                    host.layoutSubtreeIfNeeded()
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let drawing = Self.ms(start)
                    let dirtyStart = ContinuousClock.now
                    #expect(document.isDirty)
                    let dirtyDuration = Self.ms(dirtyStart)
                    // 属性の背景更新を次の操作へ混ぜない。
                    if WorkingTreeText.shouldHighlight(document.draft, bomByteCount: document.bom.count) {
                        try await wait { completedAt != nil }
                    }
                    let completion = completedAt.map { Self.ms(start, $0) }
                    completedAt = nil
                    view.undoManager?.undo()
                    if WorkingTreeText.shouldHighlight(document.draft, bomByteCount: document.bom.count) {
                        try await wait { completedAt != nil }
                    } else { await Task.yield() }
                    host.layoutSubtreeIfNeeded()
                    #expect(Data(document.draft.utf8) == baseline)
                    if iteration >= 5 {
                        input.append(duration)
                        redraw.append(drawing)
                        dirty.append(dirtyDuration)
                        if let completion { completions.append(completion) }
                    }
                    view.undoManager?.removeAllActions()
                }
            }
            coordinator.highlights.cancel()
            #expect(Self.p95(redraw) <= 100, "読込上限内の測定ファイルは入力→描画p95が100 ms以内: \(name)")
            document.draft = try WorkingTreeText.decode(bytes).text
            #expect(!document.isDirty)
            #expect(try await document.save() == .saved)
            #expect(try Data(contentsOf: fixtures.appendingPathComponent(name)) == bytes)
            rows.append(["文書": name, "バイト数": bytes.count, "拒否": false,
                "読込_ms": load, "開く_ms": opening, "入力p95_ms": Self.p95(input),
                "入力から次描画p95_ms": Self.p95(redraw), "dirty参照p95_ms": Self.p95(dirty), "入力回数": input.count])
            if !completions.isEmpty { rows[rows.count - 1]["色付け完了p95_ms"] = Self.p95(completions) }
            let label = ProcessInfo.processInfo.environment["PHLOX_LARGE_FILE_LABEL"] ?? "final"
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("document-\(label).json"), options: .atomic)
            print("ファイルタブ計測: \(rows.last!)")
            withExtendedLifetime(host) {}
        }
        let label = ProcessInfo.processInfo.environment["PHLOX_LARGE_FILE_LABEL"] ?? "final"
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("document-\(label).json"), options: .atomic)
        #expect(rows.count == names.count)
        #endif
    }


    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHLOX_LARGE_FILE_PERFORMANCE"] == "1"),
          .enabled(if: FileManager.default.fileExists(atPath: "/tmp/large-file-samples/real-6.6MB.html")),
          arguments: ["paste", "font", "external", "boundary"])
    func longLineKeepsPreparedGlyphsAfterChanges(change: String) async throws {
        #if DEBUG
        Issue.record("文字形の性能は -c release で計測してください")
        #else
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let sample = URL(fileURLWithPath: "/tmp/large-file-samples/real-6.6MB.html")
        let line = try WorkingTreeText.decodeUTF8(Data(contentsOf: sample))
        func middleInput(changed: Bool) throws -> Double {
            var text = changed && ["paste", "external", "boundary"].contains(change) ? "<html>\n" : "<html>\n" + line
            if changed && change == "boundary" {
                text += String(repeating: " ", count: 1_000_000 - text.utf8.count)
            }
            let host = NSHostingView(rootView: CodeTextEditor(
                getText: { text }, setText: { text = $0 }, path: "page.html"))
            host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            let view = try #require(Self.editor(host))
            let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
            defer { coordinator.highlights.cancel() }
            if !changed {
                // 基準の文字形を独立に準備し、製品の準備を全て外す変異も検出する。
                view.layoutManager?.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: view.textStorage!.length))
            }
            if changed {
                switch change {
                case "paste", "boundary":
                    view.insertText(line, replacementRange: NSRange(location: view.textStorage!.length, length: 0))
                case "external":
                    text += line
                    CodeTextEditor.synchronizeText(text, with: view, beforeReplacement: { coordinator.highlights.invalidate() })
                    coordinator.updateHighlights(view, path: "page.html")
                default:
                    view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                    coordinator.updateHighlights(view, path: "page.html")
                }
            }
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let range = NSRange(location: view.textStorage!.length / 2, length: 0)
            view.setSelectedRange(range)
            view.scrollRangeToVisible(range)
            let start = ContinuousClock.now
            view.insertText("x", replacementRange: range)
            return Self.ms(start)
        }
        let opened = try middleInput(changed: false)
        let changed = try middleInput(changed: true)
        print("文字形回帰 \(change): 変更後 \(changed) ms / 開いた直後 \(opened) ms")
        #expect(changed <= max(16, opened * 2), "変更後も文字形の準備が残る: \(changed) vs \(opened)")
        #endif
    }

    private static func editor(_ view: NSView) -> CurrentLineTextView? {
        if let editor = view as? CurrentLineTextView { return editor }
        return view.subviews.lazy.compactMap { editor($0) }.first
    }

    private static func ms(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant = .now) -> Double {
        let elapsed = start.duration(to: end).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private static func p95(_ values: [Double]) -> Double {
        values.sorted()[Int(ceil(Double(values.count) * 0.95)) - 1]
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CompletionError.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private enum CompletionError: Error { case timeout }
}
