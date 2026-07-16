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
private func renderImage<V: View>(from view: V) throws -> NSImage {
    let renderer = ImageRenderer(
        content: view
            .padding(16)
            .frame(width: 480, height: 360, alignment: .topLeading)
            .background(DSColor.chatBackground)
    )
    renderer.scale = 1
    return try #require(renderer.nsImage)
}

private func tiffData(from image: NSImage) throws -> Data {
    try #require(image.tiffRepresentation)
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
