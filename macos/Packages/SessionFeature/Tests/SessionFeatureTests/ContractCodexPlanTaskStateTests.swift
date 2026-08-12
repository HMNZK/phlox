import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Contract: Codex plan task state")
@MainActor
struct ContractCodexPlanTaskStateTests {
    @Test("別 thread/turn の plan は現在の状態へ混ざらない")
    func staleIdentityDoesNotApply() {
        let state = CodexPlanTaskState()
        let original = [TurnPlanStep(step: "元", status: .pending)]
        #expect(state.apply(threadId: "thread-1", turnId: "turn-1", plan: original))
        let before = state.tasks

        #expect(!state.apply(threadId: "thread-2", turnId: "turn-1", plan: [
            TurnPlanStep(step: "別 thread", status: .completed),
        ]))
        #expect(!state.apply(threadId: "thread-1", turnId: "turn-2", plan: [
            TurnPlanStep(step: "別 turn", status: .completed),
        ]))
        #expect(state.tasks == before)
        #expect(state.threadId == "thread-1")
        #expect(state.turnId == "turn-1")
    }

    @Test("未知 status と空の identity は直前の有効状態を維持する")
    func invalidPlanDoesNotPartiallyApply() {
        let state = CodexPlanTaskState()
        #expect(state.apply(threadId: "thread-1", turnId: "turn-1", plan: [
            TurnPlanStep(step: "有効", status: .completed),
        ], explanation: "保持"))
        let beforeTasks = state.tasks
        let beforeExplanation = state.explanation

        #expect(!state.apply(threadId: "thread-1", turnId: "turn-1", plan: [
            TurnPlanStep(step: "未知", status: .unknown("future")),
        ], explanation: "未知"))
        #expect(!state.apply(threadId: "", turnId: "turn-1", plan: []))
        #expect(!state.apply(threadId: "thread-1", turnId: "", plan: []))
        #expect(state.tasks == beforeTasks)
        #expect(state.explanation == beforeExplanation)
    }

    @Test("plan 以外の event は状態を変更しない")
    func nonPlanEventDoesNotApply() {
        let state = CodexPlanTaskState()
        let event = ThreadEvent.turnInterrupted(threadId: "thread-1", turnId: "turn-1")

        #expect(!state.apply(event))
        #expect(state.threadId.isEmpty)
        #expect(state.turnId.isEmpty)
        #expect(state.tasks.isEmpty)
    }

    @Test("reset 失敗後の空 thread identity は wildcard にならない")
    func failedResetRejectsPlansUntilNewThreadIsBound() {
        let state = CodexPlanTaskState(threadId: "thread-old", turnId: "turn-old")
        #expect(state.apply(threadId: "thread-old", turnId: "turn-old", plan: [
            TurnPlanStep(step: "old", status: .completed),
        ]))

        state.reset(threadId: "")
        #expect(!state.apply(threadId: "thread-late", turnId: "turn-late", plan: [
            TurnPlanStep(step: "stale", status: .completed),
        ]))
        #expect(state.tasks.isEmpty)

        state.reset(threadId: "thread-new")
        #expect(state.apply(threadId: "thread-new", turnId: "turn-new", plan: [
            TurnPlanStep(step: "fresh", status: .inProgress),
        ]))
        #expect(state.tasks.map(\.title) == ["fresh"])
    }
}
