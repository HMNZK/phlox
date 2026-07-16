import AppKit
import SwiftUI
import DesignSystem
import MarkdownUI
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test @MainActor
func markdownTableRendersDifferentlyFromEmpty() throws {
    let contentImage = try renderTableImage(theme: chatTableTheme(scale: 1.0))
    let emptyImage = try renderImage(from: RichMarkdownView(""))

    #expect(try tiffData(from: contentImage) != tiffData(from: emptyImage))
}

@Test @MainActor
func markdownTableRendersDifferentlyFromNonTableMarkdown() throws {
    let tableImage = try renderTableImage(theme: chatTableTheme(scale: 1.0))
    let plainImage = try renderImage(from: RichMarkdownView("本文のみ。表は含まない。"))

    #expect(try tiffData(from: tableImage) != tiffData(from: plainImage))
}

@Test @MainActor
func chatTableThemeDiffersFromMarkdownUIDefaultTable() throws {
    let styledImage = try renderTableImage(theme: chatTableTheme(scale: 1.0))
    let defaultImage = try renderTableImage(theme: Theme())

    #expect(try tiffData(from: styledImage) != tiffData(from: defaultImage))
}

@Test @MainActor
func chatTableThemeFollowsFontScale() throws {
    let scale10Image = try renderTableImage(theme: chatTableTheme(scale: 1.0))
    let scale15Image = try renderTableImage(theme: chatTableTheme(scale: 1.5))

    #expect(try tiffData(from: scale10Image) != tiffData(from: scale15Image))
}

@MainActor
private func chatTableTheme(scale: CGFloat) -> Theme {
    RichMarkdownView.theme(for: AppTheme.phlox.id, scale: scale)
}

@MainActor
private func renderTableImage(theme: Theme) throws -> NSImage {
    let renderer = ImageRenderer(
        content: Markdown(tableMarkdown)
            .markdownTheme(theme)
            .padding(16)
            .frame(width: 480, height: 220, alignment: .topLeading)
            .background(DSColor.chatBackground)
    )
    renderer.scale = 1
    return try #require(renderer.nsImage)
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

// NOTE(P1 リサイズ暴走の回帰検証について): 表＋リサイズの非収束レイアウトループ
// （2026-07-07 CPU 暴走。ADR 0045 / delivery/0024-teamview-cpu-fix-worklog.md）は
// headless の NSWindow + NSHostingView（実物 ChatItemView・実物大コンテンツ）でも
// 再現しないことを確認済み（WindowServer 実表示の update cycle に依存）。
// このため自動回帰テストは置かず、回帰確認は実 Debug 起動＋リサイズ＋CPU 収束の
// runtime 手順（worklog 記載）で行う。検出力のないテストは置かない。
private let tableMarkdown = """
| Command | Description |
| --- | --- |
| git status | List all new or modified files |
| git diff | Show file differences that haven't been staged |
| git add | Stage a file for commit |
"""
