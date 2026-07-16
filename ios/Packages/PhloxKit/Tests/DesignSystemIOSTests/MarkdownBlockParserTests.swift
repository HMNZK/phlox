import Testing
@testable import DesignSystemIOS

struct MarkdownBlockParserTests {
    @Test("行中のバッククォートはフェンスとして扱わない")
    func inlineBackticksAreParagraphText() {
        let text = "prefix ```swift\nlet value = 1\nsuffix ```"
        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("空コードと前後の空行を失わない")
    func emptyCodeAndSurroundingBlankLines() {
        let text = "intro\n\n```swift\n```\n\noutro"
        #expect(MarkdownBlockParser.blocks(from: text) == [
            .paragraph("intro\n"),
            .code(language: "swift", content: ""),
            .paragraph("\noutro"),
        ])
    }

    @Test("言語識別子は前後空白を除いた最初の語")
    func extractsLanguageIdentifier() {
        #expect(MarkdownBlockParser.blocks(from: "```  swift extra\nlet x = 0\n```") == [
            .code(language: "swift", content: "let x = 0"),
        ])
    }

    @Test("未終端フェンスは空コードも表現する")
    func unterminatedEmptyFence() {
        #expect(MarkdownBlockParser.blocks(from: "```swift") == [
            .code(language: "swift", content: ""),
        ])
    }
}
