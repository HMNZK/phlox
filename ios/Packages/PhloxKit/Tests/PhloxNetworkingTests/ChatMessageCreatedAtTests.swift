import Foundation
import PhloxCore
import Testing
@testable import PhloxNetworking

@Suite("発言・返答の作成時刻")
struct ChatMessageCreatedAtTests {
    private let payload = #"""
    {"sessionId":"s1","messages":[
      {"id":"u1","type":"user","text":"質問","createdAt":"2026-10-17T05:32:00Z"},
      {"id":"a1","type":"agent","text":"回答","createdAt":"2026-10-17T05:33:00Z"},
      {"id":"r1","type":"reasoning","text":"考え中","createdAt":"2026-10-17T05:34:00Z"}
    ],"cursor":"c-2"}
    """#

    @Test("user・agent の時刻を読み、他の type では使わない")
    func decodesOnlyUserAndAgentTimestamps() throws {
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(payload.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        let formatter = ISO8601DateFormatter()

        #expect(messages[0].createdAt == formatter.date(from: "2026-10-17T05:32:00Z"))
        #expect(messages[1].createdAt == formatter.date(from: "2026-10-17T05:33:00Z"))
        #expect(messages[2].createdAt == nil)
    }

    @Test("since の差分でも時刻を保持し、旧 Mac の欠落は nil のまま")
    func deltaRetainsOptionalTimestamp() throws {
        let dto = try JSONDecoder().decode(MessagesDeltaDTO.self, from: Data(payload.utf8))
        let delta = dto.toDomain(since: "c-1")
        let formatter = ISO8601DateFormatter()

        #expect(!delta.isSnapshot)
        #expect(delta.messages.first?.createdAt == formatter.date(from: "2026-10-17T05:32:00Z"))

        let oldMac = ChatMessageDTO(id: "u2", type: "user", text: "古い Mac")
        #expect(oldMac.toDomain()?.createdAt == nil)
    }
}
