import AppKit
import QuartzCore
import SwiftUI
import XCTest
@testable import DashboardFeature

/// 実際のファイルタブを画面外で動かす。GPU合成と実入力の待ち時間は含めない。
final class MarkdownScrollPerformanceTests: XCTestCase {

    @MainActor
    func testLinkHoverDoesNotEvaluateEditorOrRebuildContent() async throws {
        _ = NSApplication.shared
        let fixture = Self.output.appendingPathComponent("link-evaluations")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try Data("# 見出し\n\n[参照](https://example.com)\n".utf8).write(to: fixture.appendingPathComponent("link.md"))
        let document = FileTabDocument(path: "link.md", root: fixture.path)
        await document.loadIfNeeded()
        await document.refreshMarkdownAnalysis()
        let bodies = BodyEvaluations()
        let contents = BodyEvaluations()
        let resolutions = BodyEvaluations()
        let host = NSHostingView(rootView: MarkdownBlockEditor(document: document, openURL: { _ in .discarded },
            linkDestination: { url in
                resolutions.count += 1
                return FileLinkDestination(url: url, decision: .openBrowser(url))
            }, onBodyEvaluation: { bodies.count += 1 }, onContentEvaluation: { contents.count += 1 })
            .environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let row = try XCTUnwrap(Self.descendants(host).compactMap { $0 as? MarkdownBlockSelectionObserver.SelectionView }
            .first { $0.onLinkHoverChange != nil })
        bodies.count = 0
        contents.count = 0
        row.onLinkHoverChange?(URL(string: "https://example.com")!)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(resolutions.count, 1, "リンク先の非同期解決も実行する")
        row.onLinkHoverChange?(nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(bodies.count, 0, "リンクの入退出と行き先更新で親bodyを評価しない")
        XCTAssertEqual(contents.count, 0, "リンクのホバーで本文を構築しない")
    }

    @MainActor
    func testLinkHoverSuppressesBlockHoverBackground() async throws {
        _ = NSApplication.shared
        let fixture = Self.output.appendingPathComponent("link-hover")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try Data("# 見出し\n\n本文。\n".utf8).write(to: fixture.appendingPathComponent("link.md"))
        let document = FileTabDocument(path: "link.md", root: fixture.path)
        await document.loadIfNeeded()
        await document.refreshMarkdownAnalysis()
        let host = NSHostingView(rootView: MarkdownBlockEditor(document: document, openURL: { _ in .discarded },
            hoveredLink: URL(string: "https://example.com/other")!).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderBack(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let before = try Self.image(host)
        let row = try XCTUnwrap(Self.descendants(host)
            .compactMap { $0 as? MarkdownBlockSelectionObserver.SelectionView }.first { $0.onHoverChange != nil })
        row.onHoverChange?(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(try Self.image(host), before, "リンクのホバー中はブロックの背景を出さない")
    }

    @MainActor
    func testHoverPreservesTextSelectionViewsAndDocument() async throws {
        _ = NSApplication.shared
        let fixture = Self.output.appendingPathComponent("hover-regression")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let original = Data(("# 見出し\n\n本文と **強調**。\n\n| 列 | 値 |\n| --- | --- |\n| 内容 | 1 |\n\n"
            + String(repeating: "後続の段落。\n\n", count: 120)).utf8)
        try original.write(to: fixture.appendingPathComponent("hover.md"))
        let document = FileTabDocument(path: "hover.md", root: fixture.path)
        await document.loadIfNeeded()
        await document.refreshMarkdownAnalysis()
        XCTAssertGreaterThan(document.markdownBlocks.count, 120)
        let evaluations = BodyEvaluations()
        let contents = BodyEvaluations()
        let host = NSHostingView(rootView: MarkdownBlockEditor(document: document, openURL: { _ in .discarded },
            onBodyEvaluation: { evaluations.count += 1 },
            onContentEvaluation: { contents.count += 1 }).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderBack(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let before = try Self.image(host)
        let row = try XCTUnwrap(Self.descendants(host)
            .compactMap { $0 as? MarkdownBlockSelectionObserver.SelectionView }.first { $0.onHoverChange != nil })
        let fields = Self.descendants(host).compactMap { $0 as? NSTextField }
        XCTAssertFalse(fields.isEmpty)
        let version = document.version
        evaluations.count = 0
        contents.count = 0
        row.onHoverChange?(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNotEqual(try Self.image(host), before, "ホバーの背景を表示する")
        row.onHoverChange?(false)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(try Self.image(host), before, "退出すると背景を戻す")
        XCTAssertEqual(evaluations.count, 0, "ホバーで文書全体を再評価しない")
        XCTAssertEqual(contents.count, 0, "ホバー更新のクロージャ内で本文を構築しない")
        XCTAssertEqual(Self.descendants(host).compactMap { $0 as? NSTextField }.map(ObjectIdentifier.init),
                       fields.map(ObjectIdentifier.init), "文字選択部品を再生成しない")
        row.onHoverChange?(true)
        let scroll = try XCTUnwrap(Self.descendants(host).compactMap { $0 as? NSScrollView }.first)
        let content = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(content.bounds.height - scroll.contentView.bounds.height, 2000)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: content.bounds.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(row.visibleRect.isEmpty, "ホバーした行を表示範囲外にする")
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(try Self.image(host), before, "撤去して戻った行にホバー背景を残さない")
        XCTAssertEqual(evaluations.count, 0, "スクロールとホバーで親bodyを評価しない")
        XCTAssertEqual(Data(document.draft.utf8), original)
        XCTAssertEqual(document.version, version)
    }

    @MainActor
    func testScrollFrames() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PHLOX_SCROLL_PERFORMANCE"] == "1",
                          "PHLOX_SCROLL_PERFORMANCE=1 のRelease実行時だけ計測")
        #if DEBUG
        XCTFail("スクロール性能は -c release で計測してください")
        return
        #else
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = Self.output
        let fixtures = output.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        let input = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHLOX_SCROLL_FIXTURE"] ?? "/tmp/capweave-DESIGN.md")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "測定用の文書がありません: \(input.path)")
        let data = try Data(contentsOf: input)
        try data.write(to: fixtures.appendingPathComponent("DESIGN.md"))
        let design = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = design.components(separatedBy: "\n")
        // 表の行だけ段落へ置き換え、見出し・フェンス・長い行・行数を維持する。
        let withoutTables = lines.map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
                ? line.replacingOccurrences(of: "|", with: " ") : line
        }.joined(separator: "\n")
        try Data(withoutTables.utf8).write(to: fixtures.appendingPathComponent("without-tables.md"))
        try Data(String(repeating: "# 小文書\n\n本文と **強調**。\n\n", count: 20).utf8)
            .write(to: fixtures.appendingPathComponent("small.md"))
        var results: [[String: Any]] = []
        let hover = ProcessInfo.processInfo.environment["PHLOX_SCROLL_HOVER"] != "0"
        for filename in ["DESIGN.md", "without-tables.md", "small.md"] {
            for source in [false, true] {
                let document = FileTabDocument(path: filename, root: fixtures.path)
                await document.loadIfNeeded()
                XCTAssertTrue(document.isLoaded)
                if source { XCTAssertTrue(document.setPresentation(.source)) }
                let original = Data(document.draft.utf8)
                let version = document.version
                let evaluations = BodyEvaluations()
                let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
                    isFocused: false, openFile: { _, _ in },
                    markdownEditor: MarkdownBlockEditor(document: document, openURL: { _ in .discarded },
                                                       onBodyEvaluation: { evaluations.count += 1 }))
                    .environment(\.colorScheme, .dark))
                host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host
                window.orderBack(nil)
                defer { window.contentView = nil; window.close() }
                try await Task.sleep(for: .milliseconds(500))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                evaluations.count = 0
                let scroll = try XCTUnwrap(Self.descendants(host).compactMap { $0 as? NSScrollView }.first)
                let content = try XCTUnwrap(scroll.documentView)
                XCTAssertGreaterThan(content.bounds.height, scroll.contentView.bounds.height)
                var frames: [Double] = []
                var tableFrames: [Double] = []
                var tableCreations: [Int] = []
                var layouts: [Double] = []
                var drawings: [Double] = []
                var hoverLookups: [Double] = []
                var slowFrames: [[String: Any]] = []
                var hoveredView: MarkdownBlockSelectionObserver.SelectionView?
                var previousFields = Set(Self.descendants(host).compactMap { $0 as? NSTextField }.map(ObjectIdentifier.init))
                var y: CGFloat = 0
                // 初回の下りと、生成済みブロックを通る上りを両方測る。
                for direction: CGFloat in [1, -1] {
                    var steps = 0
                    while steps < 2400 {
                        let maximum = max(0, content.bounds.height - scroll.contentView.bounds.height)
                        let next = min(maximum, max(0, y + 64 * direction))
                        if next == y { break }
                        let start = ContinuousClock.now
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: next))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        host.layoutSubtreeIfNeeded()
                        if hover, !source {
                            // カーソルを動かさず、本文中央を通る行の実際の更新クロージャを呼ぶ。
                            let lookupStart = ContinuousClock.now
                            let target = Self.hoverTarget(in: host)
                            hoverLookups.append(Self.milliseconds(lookupStart.duration(to: .now)))
                            if target !== hoveredView {
                                if hoveredView?.window === window { hoveredView?.onHoverChange?(false) }
                                target?.onHoverChange?(true)
                                hoveredView = target
                            }
                        }
                        Self.flushLayout()
                        host.layoutSubtreeIfNeeded()
                        let laidOut = ContinuousClock.now
                        host.displayIfNeeded()
                        window.displayIfNeeded()
                        CATransaction.flush()
                        let drawn = ContinuousClock.now
                        layouts.append(Self.milliseconds(start.duration(to: laidOut)))
                        drawings.append(Self.milliseconds(laidOut.duration(to: drawn)))
                        frames.append(Self.milliseconds(start.duration(to: drawn)))
                        y = scroll.contentView.bounds.minY
                        if !source {
                            // 計測の外で、遅いフレームと文字部品の生成の関係を記録する。
                            let fields = Self.descendants(host).compactMap { $0 as? NSTextField }
                            let created = fields.filter { !previousFields.contains(ObjectIdentifier($0)) }
                            let tables = Self.descendants(host).compactMap { $0 as? MarkdownBlockSelectionObserver.SelectionView }
                                .filter(\.isTable)
                            if tables.contains(where: { !$0.visibleRect.isEmpty }) {
                                tableFrames.append(frames.last!)
                                tableCreations.append(created.filter { field in
                                    tables.contains { $0.bounds.intersects($0.convert(field.bounds, from: field)) }
                                }.count)
                            }
                            if frames.last! > 16.7 {
                                slowFrames.append(["y": y, "direction": direction, "ms": frames.last!,
                                    "fields": fields.count, "created_fields": created.count,
                                    "created_text": created.prefix(5).map { String($0.stringValue.prefix(100)) }])
                            }
                            previousFields = Set(fields.map(ObjectIdentifier.init))
                        } else if let frame = frames.last, frame > 16.7 {
                            slowFrames.append(["y": y, "direction": direction, "ms": frame])
                        }
                        steps += 1
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    XCTAssertLessThan(steps, 2400, "文書末尾まで到達しない")
                }
                XCTAssertFalse(frames.isEmpty)
                let mode = source ? "ソース" : "レンダリング"
                let record: [String: Any] = ["file": filename, "mode": mode,
                    "bytes": document.draft.utf8.count, "frames": frames.count,
                    "p50_ms": Self.percentile(frames, 0.50), "p95_ms": Self.percentile(frames, 0.95),
                    "max_ms": frames.max() ?? 0, "over_16_7": frames.filter { $0 > 16.7 }.count,
                    "layout_p95_ms": Self.percentile(layouts, 0.95),
                    "draw_p95_ms": Self.percentile(drawings, 0.95),
                    "editor_bodies": evaluations.count, "hover": hover,
                    "table_frames": tableFrames.count,
                    "table_p50_ms": Self.percentile(tableFrames, 0.50),
                    "table_p95_ms": Self.percentile(tableFrames, 0.95),
                    "table_max_ms": tableFrames.max() ?? 0,
                    "table_over_16_7": tableFrames.filter { $0 > 16.7 }.count,
                    "table_created_fields_max": tableCreations.max() ?? 0,
                    "hover_lookup_p95_ms": Self.percentile(hoverLookups, 0.95)]
                print("ブロック表示のbody評価: \(evaluations.count)、仮想ホバー: \(hover)")
                results.append(record)
                print("スクロール計測: \(record)")
                let label = ProcessInfo.processInfo.environment["PHLOX_SCROLL_LABEL"] ?? "latest"
                try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("\(label).json"), options: .atomic)
                try JSONSerialization.data(withJSONObject: slowFrames, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("\(label)-\(filename)-\(source ? "source" : "rendered")-slow.json"))
                XCTAssertEqual(Data(document.draft.utf8), original, "スクロールで原文を変えない")
                XCTAssertEqual(document.version, version, "スクロールで文書の版を変えない")
                XCTAssertLessThanOrEqual(Self.percentile(frames, 0.95), 16.7, "\(filename) \(mode) のフレームp95")
            }
        }
        #endif
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor private static func hoverTarget(in view: NSView) -> MarkdownBlockSelectionObserver.SelectionView? {
        if let target = view as? MarkdownBlockSelectionObserver.SelectionView,
           target.onHoverChange != nil,
           target.bounds.contains(target.convert(NSPoint(x: 400, y: 300), from: nil)) { return target }
        for child in view.subviews {
            if let target = hoverTarget(in: child) { return target }
        }
        return nil
    }

    private static var output: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/scroll-performance")
    }

    @MainActor private static func image(_ host: NSView) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return Data(bytes: try XCTUnwrap(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @MainActor private static func flushLayout() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.0001))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[max(0, Int(ceil(Double(sorted.count) * fraction)) - 1)]
    }
}

@MainActor private final class BodyEvaluations {
    var count = 0
}
