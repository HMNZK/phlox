import Foundation
import PhloxCore
import Testing
@testable import PhloxNetworking

struct StatusTranscriptDTOTests {
    @Test func decodesCardMetadataAndOrderedMessageReferences() throws {
        let payload = #"""
        {"messages":[{"id":"answer","type":"agent","text":"回答"}],"cursor":"c2","snapshot":true,
         "statusTranscript":{"blocks":[{"messages":{"ids":["user"]}},{"card":{"_0":{
           "id":"card-user","state":"completed","title":"完了","startedAt":100,"endedAt":105,
           "activityState":"searching","rows":[{"id":"task","kind":"task","title":"調査",
           "state":"completed","autoExpanded":false,"entries":[{"action":{"_0":{
           "id":"read","title":"ファイルを読む","state":"completed","duration":2,
           "messageIDs":["read"],"symbolName":"doc"}}}]}]}}},{"messages":{"ids":["answer"]}}]}}
        """#
        let value = try JSONDecoder().decode(MessagesDeltaDTO.self, from: Data(payload.utf8)).toDomain(since: "c1")
        let action = MobileStatusTranscript.Action(id: "read", title: "ファイルを読む", state: .completed,
            startedAt: nil, duration: 2, messageIDs: ["read"], symbolName: "doc")
        let row = MobileStatusTranscript.Row(id: "task", kind: .task, title: "調査", state: .completed,
            autoExpanded: false, startedAt: nil, endedAt: nil, entries: [.action(action)])
        let card = MobileStatusTranscript.Card(id: "card-user", state: .completed, title: "完了",
            startedAt: Date(timeIntervalSinceReferenceDate: 100), endedAt: Date(timeIntervalSinceReferenceDate: 105),
            activityState: .searching, silence: nil, rows: [row])
        #expect(value.statusTranscript == MobileStatusTranscript(blocks: [
            .messages(ids: ["user"]), .card(card), .messages(ids: ["answer"]),
        ]))
        #expect(value.messages == [.agent(id: "answer", text: "回答")])
        #expect(value.isSnapshot)
    }

    @Test func oldMacWithoutProjectionStillDecodes() throws {
        let payload = #"{"messages":[],"cursor":"old"}"#
        let delta = try JSONDecoder().decode(MessagesDeltaDTO.self, from: Data(payload.utf8)).toDomain(since: nil)
        #expect(delta.statusTranscript == nil)
        #expect(delta.isSnapshot)
    }
}
