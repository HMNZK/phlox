import AppKit
import Testing
@testable import DashboardFeature

@Suite("Acceptance: 新規チャットの見出し")
struct NewChatGreetingsAcceptanceTests {
    @Test("見出し候補は10種類で、選択結果は候補のいずれか")
    func selectsOneOfTenGreetings() {
        #expect(NewChatGreetings.all.count == 10)
        #expect(Set(NewChatGreetings.all).count == 10)
        #expect(NewChatGreetings.all.contains(NewChatGreetings.random()))
    }

    @Test("見出しの同梱ドット書体が登録され、全候補の文字を持つ")
    func headingFontIsRegisteredAndCoversGreetings() throws {
        _ = NewChatHeadingFont.font
        let font = try #require(NSFont(name: NewChatHeadingFont.postScriptName, size: 30))
        let text = NewChatGreetings.all.joined() + "ABCabc?'"
        let utf16 = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        #expect(CTFontGetGlyphsForCharacters(font as CTFont, utf16, &glyphs, utf16.count))
    }
}
