import AppKit
import Testing
@testable import SessionFeature

@Test("リンクの文字だけ指差しカーソルを持つ")
func chatLinkCursorIsLimitedToLinkText() {
    let text = ChatProseText.compute("a [link](https://example.com) z")
    #expect(ChatLinkHitTester.cursor(in: text, at: .init(x: 16, y: 8), width: 300, scale: 1) === NSCursor.pointingHand)
    #expect(ChatLinkHitTester.cursor(in: text, at: .init(x: 3, y: 8), width: 300, scale: 1) === NSCursor.iBeam)
    #expect(ChatLinkHitTester.cursor(in: text, at: .init(x: 100, y: 8), width: 300, scale: 1) === NSCursor.arrow)
}
