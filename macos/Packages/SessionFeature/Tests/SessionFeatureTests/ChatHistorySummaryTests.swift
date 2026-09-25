import Foundation
import Testing
@testable import SessionFeature

// C-21: 履歴カードの「18 件」「最後: …」。数えるのは発言（ユーザーとエージェント）だけ。
@Suite("Chat history summary")
struct ChatHistorySummaryTests {
    private let time = Date(timeIntervalSince1970: 0)

    @Test
    func countsMessagesAndKeepsTheLastOneOnOneLine() {
        let summary = ChatHistorySummary(items: [
            .userMessage(id: "u", text: "直して", timestamp: time, attachments: []),
            .commandExecution(id: "c", command: "ls", output: "", timestamp: time),
            .agentMessage(id: "a", text: "直しました。\n  テストは 3 件とも成功", timestamp: time),
        ])
        #expect(summary.messageCount == 2)
        #expect(!summary.reachesLimit)
        #expect(summary.lastMessage == "直しました。 テストは 3 件とも成功")
    }

    @Test
    func emptyHistoryHasNoLastMessage() {
        let summary = ChatHistorySummary(items: [])
        #expect(summary.messageCount == 0)
        #expect(summary.lastMessage == nil)
    }

    @Test
    func reachingTheLoadLimitIsMarked() {
        let items = (0..<3).map { ChatItem.agentMessage(id: "\($0)", text: "x", timestamp: time) }
        #expect(ChatHistorySummary(items: items, limit: 3).reachesLimit)
        #expect(!ChatHistorySummary(items: items, limit: 4).reachesLimit)
    }
}
