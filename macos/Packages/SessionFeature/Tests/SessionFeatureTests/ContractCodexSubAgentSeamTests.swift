import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Contract: Codex sub-agent seam")
struct ContractCodexSubAgentSeamTests {
    @Test("ThreadSummaryはparent/ancestor相当の実IDとdirect input能力を保持する")
    func childIdentityIsLossless() throws {
        let raw: JSONValue = .object([
            "id": .string("child-1"),
            "cliVersion": .string("0.147.0"),
            "createdAt": .number(1),
            "cwd": .string("/workspace"),
            "ephemeral": .bool(false),
            "modelProvider": .string("openai"),
            "preview": .string("child"),
            "sessionId": .string("session-child"),
            "source": .object(["subAgent": .object(["parentThreadId": .string("parent-1")])]),
            "turns": .array([]),
            "updatedAt": .number(2),
            "parentThreadId": .string("parent-1"),
            "canAcceptDirectInput": .bool(false),
        ])
        let child = try JSONDecoder().decode(ThreadSummary.self, from: JSONEncoder().encode(raw))
        #expect(child.id == "child-1")
        #expect(child.parentThreadId == "parent-1")
        #expect(child.canAcceptDirectInput == false)
        #expect(child.source == ThreadSessionSource.subAgent(
            JSONValue.object(["parentThreadId": JSONValue.string("parent-1")])
        ))
    }

    @Test("active turnが欠落しているwireを推測で補わない")
    func missingActiveTurnRemainsMissing() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(ThreadSummary(
            id: "child-1", cliVersion: "0.147.0", createdAt: 1, cwd: "/workspace", ephemeral: false,
            modelProvider: "openai", preview: "child", sessionId: "session-child", source: .appServer,
            status: .idle, turns: nil, updatedAt: 2, parentThreadId: "parent-1", canAcceptDirectInput: false
        )))
        let child = try JSONDecoder().decode(ThreadSummary.self, from: JSONEncoder().encode(raw))
        #expect(child.turns == nil)
        #expect(child.canAcceptDirectInput == false)
    }

    @Test("停止完了のwireはchild threadIdとturnIdの一致を機械的に保持する")
    func completionIdentityIsExact() throws {
        let raw: JSONValue = .object([
            "threadId": .string("child-1"),
            "turn": .object([
                "id": .string("turn-1"),
                "status": .string("interrupted"),
                "items": .array([]),
            ]),
        ])
        let notification = try JSONDecoder().decode(
            TurnLifecycleNotification.self,
            from: JSONEncoder().encode(raw)
        )
        #expect(notification.threadId == "child-1")
        #expect(notification.turn.id == "turn-1")
        #expect(notification.turn.status == "interrupted")
    }

}
