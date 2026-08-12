import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex plan タスクリスト")
struct AcceptanceCodexPlanTaskListTests {
    @Test("plan notification の thread/turn と3 statusを実DTOで保持する")
    func planNotificationRoundTripsIdentityAndStatuses() throws {
        let value = TurnPlanUpdatedNotification(
            threadId: "thread-plan",
            turnId: "turn-plan",
            plan: [
                TurnPlanStep(step: "保留", status: .pending),
                TurnPlanStep(step: "進行中", status: .inProgress),
                TurnPlanStep(step: "完了", status: .completed),
            ],
            explanation: nil
        )
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TurnPlanUpdatedNotification.self, from: data)

        #expect(decoded.threadId == "thread-plan")
        #expect(decoded.turnId == "turn-plan")
        #expect(decoded.plan.map(\.step) == ["保留", "進行中", "完了"])
        #expect(decoded.plan.map(\.status) == [.pending, .inProgress, .completed])
    }

    @Test("未知 status は実DTOの unknown として保持し、既知状態へ変換しない")
    func unknownPlanStatusRemainsUnknown() throws {
        let raw: JSONValue = .object([
            "threadId": .string("thread-plan"),
            "turnId": .string("turn-plan"),
            "plan": .array([.object(["step": .string("future"), "status": .string("futureStatus")])]),
        ])
        let value = try JSONDecoder().decode(
            TurnPlanUpdatedNotification.self,
            from: JSONEncoder().encode(raw)
        )
        guard case .unknown("futureStatus") = value.plan.first?.status else {
            Issue.record("未知 status が unknown として保持されていない")
            return
        }
        #expect(value.plan.count == 1)
    }

    @Test("plan event は既存 AgentTaskItem の normalized event へ3 statusを写像する")
    func planEventNormalizesToExistingTaskItems() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "turn/plan/updated",
            params: .object([
                "threadId": .string("thread-plan"),
                "turnId": .string("turn-plan"),
                "plan": .array([
                    .object(["step": .string("保留"), "status": .string("pending")]),
                    .object(["step": .string("進行中"), "status": .string("inProgress")]),
                    .object(["step": .string("完了"), "status": .string("completed")]),
                ]),
            ])
        )

        guard let event else {
            Issue.record("typed plan event が取得できない")
            return
        }
        guard case .planUpdated = event else {
            Issue.record("typed plan event が取得できない")
            return
        }
        guard case .taskListUpdated(let tasks)? = CodexStructuredAgentClient.normalizedEvent(from: event) else {
            Issue.record("plan event が task-list normalized event に変換されていない")
            return
        }
        #expect(tasks.map(\.title) == ["保留", "進行中", "完了"])
        #expect(tasks.map(\.status) == [.pending, .inProgress, .completed])
    }
}
