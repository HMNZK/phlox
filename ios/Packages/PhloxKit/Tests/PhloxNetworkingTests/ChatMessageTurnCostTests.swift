import Foundation
import PhloxCore
import Testing
@testable import PhloxNetworking

@Suite("ターンコストの読み込み")
struct ChatMessageTurnCostTests {
    @Test("Mac の turnCost 本文から金額を読む")
    func decodesMacWireText() throws {
        let payload = #"{"id":"cost-1","type":"turnCost","text":"$0.42"}"#
        let dto = try JSONDecoder().decode(ChatMessageDTO.self, from: Data(payload.utf8))

        #expect(dto.toDomain() == .turnCost(id: "cost-1", costUSD: 0.42))
    }

    @Test("不正または欠落した金額は会話項目にしない")
    func ignoresInvalidCost() {
        #expect(ChatMessageDTO(id: "cost-1", type: "turnCost", text: nil).toDomain() == nil)
        #expect(ChatMessageDTO(id: "cost-2", type: "turnCost", text: "$unknown").toDomain() == nil)
    }
}
