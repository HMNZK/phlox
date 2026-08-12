import Testing
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Acceptance: Codex plan task state")
@MainActor
struct AcceptanceCodexPlanTaskStateTests {
    @Test("実 plan event の3 status・順序・IDをそのまま状態へ保持する")
    func stateKeepsStatusesOrderAndIDs() {
        let state = CodexPlanTaskState()
        let applied = state.apply(.planUpdated(
            threadId: "thread-1",
            turnId: "turn-1",
            plan: [
                TurnPlanStep(step: "保留", status: .pending),
                TurnPlanStep(step: "進行中", status: .inProgress),
                TurnPlanStep(step: "完了", status: .completed),
            ],
            explanation: "説明"
        ))

        #expect(applied)
        #expect(state.threadId == "thread-1")
        #expect(state.turnId == "turn-1")
        #expect(state.tasks.map(\.title) == ["保留", "進行中", "完了"])
        #expect(state.tasks.map(\.status) == [.pending, .inProgress, .completed])
        #expect(state.tasks.map(\.id) == [
            "codex-plan-0-保留",
            "codex-plan-1-進行中",
            "codex-plan-2-完了",
        ])
        #expect(state.explanation == "説明")
    }
}
