import Testing
@testable import SessionFeature

@Suite("CodexSubAgentState 直接状態契約")
struct CodexSubAgentStateDirectTests {
    private func child(
        _ id: String = "child-1",
        parent: String = "parent-1",
        turn: String? = "turn-1",
        status: String = "active"
    ) -> CodexChildThread {
        CodexChildThread(
            id: id,
            parentThreadId: parent,
            ancestorThreadId: parent,
            activeTurnId: turn,
            status: status,
            canAcceptDirectInput: false
        )
    }

    @Test("stale（read 失敗）のあとに届いた完了通知は、通常どおり完了として反映する")
    func completionAfterStaleIsApplied() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.stale(threadId: "child-1", reason: "gone"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))
        #expect(CodexSubAgentPresentation.status(for: state.children.first?.status ?? "") == .completed)
        #expect(state.children.first?.activeTurnId == nil)
        #expect(state.stopState(for: "child-1") == .unavailable)
    }

    @Test("異なるturnの完了通知は状態を変えない")
    func mismatchedTurnDoesNotComplete() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "other-turn", status: "interrupted"))
        #expect(state.children.first?.status == "active")
        #expect(state.children.first?.activeTurnId == "turn-1")
    }

    @Test("異なるparentのchildは一覧から除外する")
    func foreignParentIsExcluded() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child(), child("foreign", parent: "parent-2")]))
        #expect(state.children.map(\.id) == ["child-1"])
    }

    @Test("完了後は共有stripから外し、会話マーカー用のchild状態は保持する")
    func completedChildLeavesStripButRemainsAvailableForMarker() throws {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))

        let ref = CodexSubAgentPresentation.ref(for: try #require(state.children.first))
        #expect(ref.status == .completed)
        #expect(!CodexSubAgentPresentation.isVisibleInStrip(ref, isDismissed: false))
        #expect(CodexSubAgentPresentation.threadID(from: ref.id) == "child-1")
        #expect(state.children.map(\.id) == ["child-1"])
    }

    @Test("停止要求はpending中に一度だけ生成する")
    func stopRequestIsSingleFlight() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1")?.turnId == "turn-1")
        #expect(state.stopRequest(for: "child-1") == nil)
        #expect(state.stopAttemptCount(for: "child-1") == 1)
    }

    @Test("一致するchildとturnのinterrupted完了後だけstoppedにする")
    func matchingInterruptedCompletionStopsChild() throws {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        guard let request = state.stopRequest(for: "child-1") else {
            Issue.record("stop request missing")
            return
        }
        #expect(state.stopState(for: "child-1") == .stopping)
        let completed = state.acceptInterruptCompletion(request: request, threadId: "child-1", turnId: "turn-1", status: "completed")
        #expect(!completed)
        #expect(state.stopState(for: "child-1") == .stopping)
        let interrupted = state.acceptInterruptCompletion(request: request, threadId: "child-1", turnId: "turn-1", status: "interrupted")
        #expect(interrupted)
        #expect(state.stopState(for: "child-1") == .stopped)
    }

    @Test("親interruptはchild停止へfallbackしない")
    func parentInterruptCannotStopChild() throws {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        guard let request = state.stopRequest(for: "child-1") else {
            Issue.record("stop request missing")
            return
        }
        let interrupted = state.acceptInterruptCompletion(request: request, threadId: "parent-1", turnId: "parent-turn", status: "interrupted")
        #expect(!interrupted)
        #expect(state.stopState(for: "child-1") == .stopping)
    }
}
