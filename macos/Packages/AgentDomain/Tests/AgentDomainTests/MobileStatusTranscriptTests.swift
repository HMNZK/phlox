import Foundation
import Testing
import AgentDomain

struct MobileStatusTranscriptTests {
    @Test func orderedReferencesAndCardMetadataSurviveWireRoundTrip() throws {
        let action = MobileStatusTranscript.Action(id: "read", title: "api.swift を読み込み", state: .completed,
            startedAt: Date(timeIntervalSince1970: 100), duration: 2, messageIDs: ["read", "read-next"], symbolName: "doc")
        let row = MobileStatusTranscript.Row(id: "task-build", kind: .task, title: "実装", state: .completed,
            autoExpanded: false, startedAt: nil, endedAt: nil, entries: [.message(id: "thought"), .action(action)])
        let card = MobileStatusTranscript.Card(id: "status-card-user", state: .completed, title: "完了",
            startedAt: Date(timeIntervalSince1970: 99), endedAt: Date(timeIntervalSince1970: 105),
            activityState: .searching, silence: nil, rows: [row])
        let value = MobileStatusTranscript(blocks: [.messages(ids: ["user"]), .card(card), .messages(ids: ["answer"])])
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(MobileStatusTranscript.self, from: data) == value)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("read-next"))
        #expect(!json.contains("output"))
        #expect(!json.contains("diff"))
    }
}
