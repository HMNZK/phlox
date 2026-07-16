import Testing
import Foundation
import PhloxCore
@testable import PhloxNetworking

@Suite("ChatMessageDTO toDomain 白箱")
struct ChatMessagesDecodingTests {

    @Test("subAgent は text 付きで Domain に変換される")
    func subAgentWithText() {
        let dto = ChatMessageDTO(
            id: "m1",
            type: "subAgent",
            text: "explore running",
            command: nil,
            output: nil,
            changes: nil,
            message: nil
        )
        #expect(dto.toDomain() == .subAgent(id: "m1", text: "explore running"))
    }

    @Test("subAgent の text 欠落は空文字")
    func subAgentMissingText() {
        let dto = ChatMessageDTO(
            id: "m1",
            type: "subAgent",
            text: nil,
            command: nil,
            output: nil,
            changes: nil,
            message: nil
        )
        #expect(dto.toDomain() == .subAgent(id: "m1", text: ""))
    }
}
