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
func fileMarkdownUnderlinesLinksBeforeHoverWithoutChatAutomaticEmphasis() {
    let url = URL(string: "https://example.com")!
    let markdown = "success 123 [参照](https://example.com) [`File.swift`](File.swift) `code`"
    for hoveredLink in [nil, url] {
        let text = fileMarkdownAttributed(markdown, hoveredLink: hoveredLink)
        #expect(text.runs.contains { $0.link == url && $0.underlineStyle == .single })
        #expect(text.runs.contains { $0.link == URL(string: "File.swift") && $0.underlineStyle == .single })
        #expect(!text.runs.contains { $0.link == nil && $0.underlineStyle != nil })
        #expect(!text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }
}

extension ThemeRenderingTests {
    @Test @MainActor
    func markdownLinkPresentationSnapshots() throws {
        guard let path = ProcessInfo.processInfo.environment["PHLOX_LINK_SNAPSHOTS"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let markdown = """
        ## 見出しの [Webリンク](https://example.com)

        本文の [参照ページ](https://example.com) と [`File.swift`](/project/File.swift:12)

        通常の本文と `plainCode` は下線なし。

        | 種別 | 開ける項目 | 通常の文字 |
        | --- | --- | --- |
        | Web | [参照ページ](https://example.com) | 参照ページ |
        | File | [`File.swift`](/project/File.swift:12) | `plainCode` |
        """
        for light in [false, true] {
            var themed = arguments
            themed[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
            defaults.setVolatileDomain(themed, forName: UserDefaults.argumentDomain)
            for file in [false, true] {
                let image = try renderImage(from: Group {
                    if file { RichMarkdownView(source: markdown, openURL: { _ in .discarded }) }
                    else { RichMarkdownView(markdown) }
                }.environment(\.colorScheme, light ? .light : .dark))
                let bitmap = try #require(NSBitmapImageRep(data: tiffData(from: image)))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("\(file ? "file" : "chat")-\(light ? "light" : "dark").png"))
            }
        }
    }
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
