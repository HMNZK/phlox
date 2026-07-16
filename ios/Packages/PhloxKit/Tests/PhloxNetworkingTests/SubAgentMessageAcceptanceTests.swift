import Testing
import Foundation
import PhloxCore
@testable import PhloxNetworking

// task-2 受け入れテスト（PM 著・凍結）。契約: tasks/task-2.md
// wire "subAgent" のデコードと前方互換（未知 type 除外・既存6種不変）を検証する。

@Suite("subAgent メッセージのデコード 受け入れ")
struct SubAgentMessageAcceptanceTests {

    private func decodeMessages(_ json: String) throws -> [ChatMessage] {
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(json.utf8))
        return dto.messages.compactMap { $0.toDomain() }
    }

    @Test("type=subAgent が .subAgent(id:text:) にデコードされる")
    func decodesSubAgent() throws {
        let json = #"""
        {"sessionId":"s1","messages":[
          {"id":"m1","type":"subAgent","text":"Sub-agent explore-map running: コードベース調査"}
        ]}
        """#
        let messages = try decodeMessages(json)
        #expect(messages == [.subAgent(id: "m1", text: "Sub-agent explore-map running: コードベース調査")])
    }

    @Test("subAgent の text 欠落は空文字にフォールバックする（クラッシュ・除外しない）")
    func subAgentWithoutTextFallsBackToEmpty() throws {
        let json = #"{"sessionId":"s1","messages":[{"id":"m1","type":"subAgent"}]}"#
        let messages = try decodeMessages(json)
        #expect(messages == [.subAgent(id: "m1", text: "")])
    }

    @Test("未知 type は引き続き除外される（前方互換）")
    func unknownTypesAreDropped() throws {
        let json = #"""
        {"sessionId":"s1","messages":[
          {"id":"m1","type":"turnCost","text":"$0.12"},
          {"id":"m2","type":"future_kind","text":"x"},
          {"id":"m3","type":"agent","text":"hello"}
        ]}
        """#
        let messages = try decodeMessages(json)
        #expect(messages == [.agent(id: "m3", text: "hello")])
    }

    @Test("既存6種のデコードは不変")
    func existingSixTypesUnchanged() throws {
        let json = #"""
        {"sessionId":"s1","messages":[
          {"id":"m1","type":"user","text":"こんにちは"},
          {"id":"m2","type":"agent","text":"了解"},
          {"id":"m3","type":"reasoning","text":"意図を分析"},
          {"id":"m4","type":"command","command":"ls","output":"a.txt"},
          {"id":"m5","type":"fileChange","changes":[{"path":"a.swift","diff":"+1"}]},
          {"id":"m6","type":"error","message":"失敗"}
        ]}
        """#
        let messages = try decodeMessages(json)
        #expect(messages == [
            .user(id: "m1", text: "こんにちは"),
            .agent(id: "m2", text: "了解"),
            .reasoning(id: "m3", text: "意図を分析"),
            .command(id: "m4", command: "ls", output: "a.txt"),
            .fileChange(id: "m5", changes: [ChatFileChange(path: "a.swift", diff: "+1", kind: nil)]),
            .error(id: "m6", message: "失敗"),
        ])
    }
}
