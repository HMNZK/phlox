import AppKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

/// task-5 白箱テスト — メッセージコピーが Markdown 装飾なしの生テキストを Pasteboard へ書くこと。
@Suite("MessageCopy whitebox")
struct MessageCopyWhiteboxTests {

    @Test @MainActor
    func copyPlainText_writesRawTextToPasteboard() {
        let sample = "Hello\n**not bold**"
        ChatMessageCopy.copyPlainTextToPasteboard(sample)
        #expect(NSPasteboard.general.string(forType: .string) == sample)
    }

    @Test @MainActor
    func copyPlainText_replacesExistingPasteboardContents() {
        ChatMessageCopy.copyPlainTextToPasteboard("first")
        ChatMessageCopy.copyPlainTextToPasteboard("second")
        #expect(NSPasteboard.general.string(forType: .string) == "second")
    }
}
