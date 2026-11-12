import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

struct MobileStatusTranscriptProjectionTests {
    private let time = Date(timeIntervalSince1970: 1_700_000_000)
    private let idle = AgentStatusLiveState(isProcessing: false, activityState: .thinking, hangAssessment: nil, isAwaitingReply: false)

    @Test func taskAndOutsideWorkKeepBuilderOrderingAndFinalAnswerOutsideCard() throws {
        let items: [ChatItem] = [
            .userMessage(id: "u", text: "依頼", timestamp: time, attachments: [], turnEnd: .init(outcome: .completed, at: time.addingTimeInterval(10))),
            .commandExecution(id: "outside", command: "pwd", output: "/work", timestamp: time, completedAt: time.addingTimeInterval(1)),
            .taskList(id: "tasks", tasks: [.init(id: "a", title: "実装", status: .inProgress)], timestamp: time.addingTimeInterval(2)),
            .commandExecution(id: "task-work", command: "swift test", output: "green", timestamp: time.addingTimeInterval(3), completedAt: time.addingTimeInterval(6)),
            .taskList(id: "done", tasks: [.init(id: "a", title: "実装", status: .completed)], timestamp: time.addingTimeInterval(7)),
            .agentMessage(id: "answer", text: "完了しました", timestamp: time.addingTimeInterval(8))
        ]
        let value = try #require(MobileStatusTranscriptProjection.build(items: items, agent: .claudeCode, liveState: idle, locale: Locale(identifier: "ja")))
        #expect(value.blocks.count == 3)
        #expect(value.blocks.first == .messages(ids: ["u"]))
        #expect(value.blocks.last == .messages(ids: ["answer"]))
        guard case .card(let card) = value.blocks[1] else { Issue.record("カードが必要"); return }
        #expect(card.id == "status-card-u")
        #expect(card.state == .completed)
        #expect(card.title == "完了")
        #expect(card.startedAt == time)
        #expect(card.endedAt == time.addingTimeInterval(10))
        #expect(card.rows.map(\.kind) == [.outside, .task])
        #expect(card.rows.map(\.autoExpanded) == [false, false])
        let task = try #require(card.rows.last)
        #expect(task.id == "task-a")
        #expect(task.title == "実装")
        #expect(task.state == .completed)
        guard case .action(let work) = try #require(task.entries.first) else { Issue.record("作業が必要"); return }
        #expect(work.messageIDs == ["task-work"])
        #expect(work.duration == 3)
        #expect(work.title == "swift test")
        #expect(work.symbolName == "terminal")
        #expect(try JSONDecoder().decode(MobileStatusTranscript.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func legacyAgentOmitsProjectionAndActiveOutsideRowUsesMacDisclosure() throws {
        let items: [ChatItem] = [
            .userMessage(id: "u", text: "依頼", timestamp: time, attachments: []),
            .commandExecution(id: "run", command: "pwd", output: "", timestamp: time)
        ]
        let live = AgentStatusLiveState(isProcessing: true, activityState: .running, hangAssessment: nil, isAwaitingReply: false)
        #expect(MobileStatusTranscriptProjection.build(items: items, agent: .cursor, liveState: live, locale: .current) == nil)
        let value = try #require(MobileStatusTranscriptProjection.build(items: items, agent: .codex, liveState: live, locale: Locale(identifier: "ja")))
        guard case .card(let card) = try #require(value.blocks.last) else { Issue.record("カードが必要"); return }
        #expect(card.state == .running)
        #expect(card.rows.first?.autoExpanded == true)
        #expect(card.rows.first?.state == .running)
        #expect(card.title == "pwd を実行中")
    }
}
