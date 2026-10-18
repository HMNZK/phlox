import Foundation
import PhloxCore
import Testing
@testable import Features

@Suite("長押しメニューの時刻")
struct ChatMessageContextMenuTitleTests {
    @Test("U-24: 端末の時間帯で時刻を表示し、時刻が無い場合は見出しを省く")
    func formatsMessageTimeInSuppliedTimeZone() throws {
        let timestamp = try #require(ISO8601DateFormatter().date(from: "2026-10-17T05:32:00Z"))
        let tokyo = try #require(TimeZone(secondsFromGMT: 9 * 60 * 60))

        #expect(ChatMessageCopyText.contextMenuTitle(createdAt: timestamp, timeZone: tokyo) == "10月17日 14:32")
        #expect(ChatMessageCopyText.contextMenuTitle(createdAt: nil, timeZone: tokyo) == nil)
    }
}
