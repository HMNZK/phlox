import Testing
import DesignSystemIOS

@Suite("DSChatBubble 添付バッジ")
struct DSChatBubbleAttachmentTests {
    @Test("1枚は枚数なしラベル")
    func singleImageBadgeText() {
        #expect(DSChatBubble.attachmentBadgeText(count: 1) == "画像")
    }

    @Test("2枚以上は枚数付きラベル")
    func multipleImageBadgeText() {
        #expect(DSChatBubble.attachmentBadgeText(count: 2) == "画像 ×2")
        #expect(DSChatBubble.attachmentBadgeText(count: 4) == "画像 ×4")
    }
}
