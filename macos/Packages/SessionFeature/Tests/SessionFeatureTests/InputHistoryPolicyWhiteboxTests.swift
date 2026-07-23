import Foundation
import Testing
@testable import SessionFeature

@Suite
struct InputHistoryPolicyWhiteboxTests {
    @Test
    func entriesPreserveSingleLongUserMessage() {
        let longText = String(repeating: "long input ", count: 1_000)
        let transcript: [ChatItem] = [
            .userMessage(id: "only-user", text: longText, timestamp: .distantFuture),
        ]

        let entries = InputHistoryPolicy.entries(from: transcript)

        #expect(entries == [InputHistoryEntry(id: "only-user", text: longText)])
    }

    @Test
    func scrubberTicksReturnsEveryEntryWhenCapExactlyMatchesCount() {
        let entries = [
            InputHistoryEntry(id: "u1", text: "first"),
            InputHistoryEntry(id: "u2", text: "second"),
            InputHistoryEntry(id: "u3", text: "third"),
        ]

        #expect(InputHistoryPolicy.scrubberTicks(from: entries, cap: 3) == entries)
    }

    @Test
    func scrubberTicksReturnsEmptyForNegativeCap() {
        let entries = [InputHistoryEntry(id: "u1", text: "first")]

        #expect(InputHistoryPolicy.scrubberTicks(from: entries, cap: -1).isEmpty)
    }
}
