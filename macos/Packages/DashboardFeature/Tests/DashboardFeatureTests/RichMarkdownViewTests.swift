import AppKit
import SwiftUI
import DesignSystem
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test @MainActor
func representativeMarkdownRendersDifferentlyFromEmptyMarkdown() throws {
    let contentImage = try renderImage(from: RichMarkdownView(representativeMarkdown))
    let emptyImage = try renderImage(from: RichMarkdownView(""))

    #expect(try tiffData(from: contentImage) != tiffData(from: emptyImage))
}

@Test @MainActor
func cumulativeStreamingMarkdownRendersGrowingDocuments() throws {
    let initialCumulativeMarkdown = streamingMarkdownChunks.prefix(2).joined()
    let finalCumulativeMarkdown = streamingMarkdownChunks.joined()

    let initialImage = try renderImage(from: RichMarkdownView(streaming: initialCumulativeMarkdown))
    let finalImage = try renderImage(from: RichMarkdownView(streaming: finalCumulativeMarkdown))
    let emptyImage = try renderImage(from: RichMarkdownView(streaming: ""))

    #expect(try tiffData(from: initialImage) != tiffData(from: emptyImage))
    #expect(try tiffData(from: finalImage) != tiffData(from: emptyImage))
    #expect(try tiffData(from: finalImage) != tiffData(from: initialImage))
}

@MainActor
private func renderImage<V: View>(from view: V, height: CGFloat = 360) throws -> NSImage {
    let renderer = ImageRenderer(
        content: view
            .padding(16)
            .frame(width: 480, height: height, alignment: .topLeading)
            .background(DSColor.chatBackground)
            .environment(\.displayScale, 1)
    )
    renderer.scale = 1
    // 背景は不透明、表示倍率は 1、描画先は 8bit sRGB に固定する。
    renderer.isOpaque = true
    var rendered: CGImage?
    renderer.render { size, draw in
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        draw(context)
        rendered = context.makeImage()
    }
    return NSImage(cgImage: try #require(rendered), size: NSSize(width: 480, height: height))
}

private func tiffData(from image: NSImage) throws -> Data {
    try #require(image.tiffRepresentation)
}

@Test @MainActor
func fileMarkdownUsesItsOwnPresentationAndLeavesChatRenderingUnchanged() throws {
    let before = try tiffData(from: renderImage(from: RichMarkdownView(representativeMarkdown)))
    let file = try tiffData(from: renderImage(from: RichMarkdownView(source: representativeMarkdown, openURL: { _ in .handled })))
    let after = try tiffData(from: renderImage(from: RichMarkdownView(representativeMarkdown)))
    #expect(before == after)
    #expect(file != before)
}

@Test
func fileMarkdownUnderlinesOnlyTheHoveredLinkWithoutChatAutomaticEmphasis() {
    let url = URL(string: "https://example.com")!
    let plain = fileMarkdownAttributed("success 123 [参照](https://example.com)", hoveredLink: nil)
    let hovered = fileMarkdownAttributed("success 123 [参照](https://example.com)", hoveredLink: url)
    #expect(!plain.runs.contains { $0.underlineStyle != nil })
    #expect(hovered.runs.contains { $0.link == url && $0.underlineStyle == .single })
    #expect(!hovered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
}

@Test(arguments: [400.0, 760.0]) @MainActor
func fileMarkdownTableFitsTheAvailableWidthAndKeepsContentProportions(width: Double) async throws {
    let markdown = """
    | Key | Description |
    | --- | --- |
    | A | A longer description of the feature |
    | B | Another description |
    """
    let host = NSHostingView(rootView: RichMarkdownView(source: markdown, openURL: { _ in .handled }))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 240)
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 240),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let key = try #require(fields(host).first { $0.stringValue == "Key" })
    let description = try #require(fields(host).first { $0.stringValue == "Description" })
    let first = host.convert(key.bounds, from: key)
    let second = host.convert(description.bounds, from: description)
    let firstColumn = second.minX - first.minX
    #expect(firstColumn > 30)
    #expect(firstColumn < width / 3)
    #expect(second.maxX <= width)
    #expect(first.minX >= 0)
    #expect(!window.isVisible)
}

private let representativeMarkdown = """
# 見出し

- 1つ目
- 2つ目
- 3つ目

1. 番号付き
2. リンク: [Phlox](https://example.com)

本文には `inlineCode()` を含める。

```swift
struct Example {
    let value: String
}
```
"""

private let streamingMarkdownChunks = [
    "# 見出し\n\n",
    "- 1つ目\n",
    "- 2つ目\n",
    "- 3つ目\n\n",
    "本文には `inlineCode()` を含める。\n\n",
    """
    ```swift
    struct Example {
        let value: String
    }
    ```
    """,
]
