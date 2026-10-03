import SwiftUI
import Testing
@testable import SessionFeature

@MainActor
struct FileMarkdownPresentationTests {
    @Test("ファイル用の描画には原文補完と改行の正規化を加えない")
    func sourceIsPassedUnchanged() throws {
        let source = "**未閉鎖\r\n\r\ne\u{301}\r\n"
        let fileView = RichMarkdownView(source: source, openURL: { _ in .discarded })
        let stored = try #require(Mirror(reflecting: fileView).children.first(where: { $0.label == "markdown" })?.value as? String)
        #expect(stored.utf8.elementsEqual(source.utf8))
        let chatView = RichMarkdownView(source)
        let chatStored = try #require(Mirror(reflecting: chatView).children.first(where: { $0.label == "markdown" })?.value as? String)
        #expect(chatStored == TranscriptMarkdownPresentation.prepare(source))
        #expect(!chatStored.utf8.elementsEqual(source.utf8))
    }

    @Test("ホバーの判定は参照リンクの解決済み URL を返す")
    func resolvedHoverDestination() {
        let text = ChatProseText.compute("a [link](guide.md) z")
        #expect(ChatLinkHitTester.link(in: text, at: .init(x: 16, y: 8), width: 300, scale: 1) == URL(string: "guide.md"))
        #expect(ChatLinkHitTester.link(in: text, at: .init(x: 3, y: 8), width: 300, scale: 1) == nil)
        #expect(ChatLinkHitTester.link(in: text, at: .init(x: 100, y: 8), width: 300, scale: 1) == nil)
    }
}
