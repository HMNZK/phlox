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

    @Test("表示では単一改行を詰め、明示的な改行を保つ")
    func commonMarkBreaksOnlyAffectPresentation() {
        let soft = fileMarkdownAttributed("first\nsecond", hoveredLink: nil)
        let hard = fileMarkdownAttributed("first  \nsecond", hoveredLink: nil)
        #expect(String(soft.characters) == "first second")
        #expect(String(hard.characters) == "first\nsecond")
    }

    @Test("CJK の単一改行は空白を入れず、英語・明示改行を保つ")
    func cjkSoftBreaksKeepOriginalWordSpacing() {
        for source in ["走らせ、\n承認待ち", "漢字\nかな", "カタカナ\n漢字", "𠀀\n漢"] {
            #expect(String(fileMarkdownAttributed(source, hoveredLink: nil).characters) == source.replacingOccurrences(of: "\n", with: ""))
        }
        for source in ["first\nsecond", "日本語\nEnglish", "English\n日本語", "한글\n한글"] {
            #expect(String(fileMarkdownAttributed(source, hoveredLink: nil).characters) == source.replacingOccurrences(of: "\n", with: " "))
        }
        #expect(String(fileMarkdownAttributed("和文  \n改行", hoveredLink: nil).characters) == "和文\n改行")
        #expect(String(fileMarkdownAttributed("和文\\\n改行", hoveredLink: nil).characters) == "和文\n改行")
        #expect(String(fileMarkdownAttributed("和文  \n次を、\n承認待ち", hoveredLink: nil).characters) == "和文\n次を、承認待ち")
        #expect(String(fileMarkdownAttributed("走らせ、 承認\n待ち", hoveredLink: nil).characters) == "走らせ、 承認待ち")
        #expect(fileMarkdownSoftBreakSeparator(before: "、", after: "承") == "")
        #expect(fileMarkdownSoftBreakSeparator(before: "a", after: "b") == " ")
        #expect(String(fileMarkdownAttributed("한국어\n문장입니다", hoveredLink: nil).characters) == "한국어 문장입니다")
        #expect(fileMarkdownSoftBreakSeparator(before: "漢", after: "한") == " ")
        #expect(fileMarkdownSoftBreakSeparator(before: "ﾡ", after: "ﾢ") == " ")
        #expect(fileMarkdownSoftBreakSeparator(before: "漢", after: "ｶ") == "")
    }

    @Test("CJK 改行を詰めても強調とリンクを保持する")
    func cjkSoftBreaksUseDisplayedCharactersAcrossInlineMarkup() throws {
        let strong = fileMarkdownAttributed("**走らせ、**\n承認待ち", hoveredLink: nil)
        #expect(String(strong.characters) == "走らせ、承認待ち")
        let emphasized = try #require(strong.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(String(strong[emphasized.range].characters) == "走らせ、")
        for (source, expected) in [("**走らせ、\n承認待ち**", "走らせ、承認待ち"),
                                   ("**漢字\n日 入力**", "漢字日 入力")] {
            let multiline = fileMarkdownAttributed(source, hoveredLink: nil)
            #expect(String(multiline.characters) == expected)
            #expect(multiline.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        }

        let link = fileMarkdownAttributed("走らせ、\n[承認](review.md)待ち", hoveredLink: nil)
        #expect(String(link.characters) == "走らせ、承認待ち")
        let linked = try #require(link.runs.first { $0.link == URL(string: "review.md") })
        #expect(String(link[linked.range].characters) == "承認")
    }

    @Test("ホバーの判定は参照リンクの解決済み URL を返す")
    func resolvedHoverDestination() {
        let text = ChatProseText.compute("a [link](guide.md) z")
        #expect(ChatLinkHitTester.link(in: text, at: .init(x: 16, y: 8), width: 300, scale: 1) == URL(string: "guide.md"))
        #expect(ChatLinkHitTester.link(in: text, at: .init(x: 3, y: 8), width: 300, scale: 1) == nil)
        #expect(ChatLinkHitTester.link(in: text, at: .init(x: 100, y: 8), width: 300, scale: 1) == nil)
    }
}
