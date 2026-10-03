import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("マークダウンのブロック入力と画面に出さない描画", .serialized)
@MainActor
struct MarkdownBlockEditorTests {
    @Test
    func longBlockKeepsAnInternalScrollHeightLimit() {
        #expect(MarkdownBlockEditor.editorHeight("短い本文") >= 54)
        #expect(MarkdownBlockEditor.editorHeight(Array(repeating: "長い本文", count: 100).joined(separator: "\n")) == 200)
    }

    @Test(arguments: [320.0, 640.0])
    func renderedAndEditingBlocksHaveDifferentOffscreenImages(width: Double) throws {
        let document = FileTabDocument(path: "offscreen.md", root: "/")
        document.draft = "# 見出し\n\n本文と [参照](https://example.com)\n"
        let rendered = try snapshot(document, width: width)
        let paragraph = try #require(document.markdownBlocks.last)
        #expect(document.beginBlockEdit(range: paragraph.range))
        let editing = try snapshot(document, width: width)

        #expect(rendered.png != editing.png)
        #expect(editing.editorCount == 1)
        #expect(rendered.editorCount == 0)
        #expect(editing.editorFrames.allSatisfy { $0.width <= width && $0.height <= 200 })
        #expect(document.activeBlockEdit != nil)
    }

    @Test
    func accessibilityKeepsRenderedBlockChildren() throws {
        let document = FileTabDocument(path: "accessibility.md", root: "/")
        document.draft = "# 見出し\n\n- 最初の項目\n- 次の項目\n\n[参照](https://example.com) と `コード`\n"
        let rendered = try snapshot(document, width: 480)
        #expect(rendered.blockIDs.contains("markdown-block-0"))
        // ブロックを一つの読み上げ要素へ潰さず、リストやリンクの子を残す。
        #expect(rendered.blocksWithChildren >= 2)
        #expect(rendered.labels.contains(where: { $0.contains("最初の項目") }))
        #expect(!rendered.labels.contains(where: { $0.contains("上下の矢印キー") }))
    }

    @Test
    func versionMismatchRetainsAnEditorWhoseOriginalBlockDisappeared() async throws {
        let document = FileTabDocument(path: "stale.md", root: "/")
        document.draft = "# 元の見出し\n\n編集する段落\n"
        #expect(document.setPresentation(.rendered))
        let block = try #require(document.markdownBlocks.last)
        #expect(document.beginBlockEdit(range: block.range))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "失わせない入力")
        document.draft = "# 別の版\n"
        #expect(!document.markdownBlocks.contains(where: { $0.id == block.id }))
        #expect(!document.setPresentation(.source))
        await #expect(throws: FileTabDocument.DocumentError.blockEditVersionMismatch) {
            try await document.save()
        }

        let image = try snapshot(document, width: 480)
        #expect(image.editorCount == 1)
        #expect(image.labels.contains("文書が先に変わったため確定できません"))
        #expect(image.labels.contains("編集を破棄"))
        #expect(image.labels.contains("ソースで開く"))
        #expect(image.editorStrings == ["失わせない入力"])
        #expect(document.activeBlockEdit?.id == id)
        #expect(document.activeBlockEdit?.current == "失わせない入力")
        #expect(document.draft == "# 別の版\n")
        #expect(document.presentation == .rendered)
    }

    private struct Snapshot {
        var png: Data
        var editorCount = 0
        var editorFrames: [CGRect] = []
        var editorStrings: [String] = []
        var blockIDs = Set<String>()
        var blocksWithChildren = 0
        var labels: [String] = []
    }

    private func snapshot(_ document: FileTabDocument, width: Double) throws -> Snapshot {
        // 画面に出さないホストでも SwiftUI の読み上げツリーを生成する。
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let view = MarkdownBlockEditor(document: document, openURL: { _ in .discarded })
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.colorScheme, .dark)
            .frame(width: width, height: 420)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: 420)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        var result = Snapshot(png: try #require(bitmap.representation(using: .png, properties: [:])))
        let artifacts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/markdown-block-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let state = document.activeBlockEdit == nil ? "rendered" : "editing"
        try result.png.write(to: artifacts.appendingPathComponent("\(Int(width))-\(state).png"))
        var seen = Set<ObjectIdentifier>()
        func accessibilityObject(_ name: String, of element: AnyObject) -> Any? {
            // SwiftUI 内部の要素は NSAccessibility に準拠しないことがある。
            // オブジェクトを返す getter と確認できたものだけを呼び、値の型を個別に検査する。
            guard let object = element as? NSObject else { return nil }
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func visit(_ element: Any) {
            let object = element as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            let children = accessibilityObject("accessibilityChildren", of: object) as? [Any] ?? []
            if let id = accessibilityObject("accessibilityIdentifier", of: object) as? String,
               id.hasPrefix("markdown-block-") {
                result.blockIDs.insert(id)
                if !children.isEmpty { result.blocksWithChildren += 1 }
            }
            if let label = accessibilityObject("accessibilityLabel", of: object) as? String { result.labels.append(label) }
            if let value = accessibilityObject("accessibilityValue", of: object) as? String { result.labels.append(value) }
            children.forEach(visit)
            if let textView = element as? CurrentLineTextView {
                result.editorCount += 1
                result.editorStrings.append(textView.string)
                if let scrollView = textView.enclosingScrollView { result.editorFrames.append(scrollView.frame) }
            }
            if let view = element as? NSView { view.subviews.forEach(visit) }
        }
        visit(hosting)
        return result
    }
}
