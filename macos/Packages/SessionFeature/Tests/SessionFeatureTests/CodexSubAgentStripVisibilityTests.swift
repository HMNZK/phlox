import Testing
import CodexAppServerKit
@testable import SessionFeature

/// Codex 子エージェントが strip に残る/消える条件の回帰テスト。
/// Codex は終わった子スレッドをアンロードするため、完了後の refresh（`.validated`）で
/// 状態が notLoaded に変わる。これを「失敗」と読むと完了済みの子が strip に居座る。
@Suite("Codex サブエージェントの strip 表示条件")
@MainActor
struct CodexSubAgentStripVisibilityTests {
    private func child(status: String = "active", turn: String? = "turn-1") -> CodexChildThread {
        CodexChildThread(
            id: "child-1",
            parentThreadId: "parent-1",
            ancestorThreadId: "parent-1",
            activeTurnId: turn,
            status: status,
            canAcceptDirectInput: false
        )
    }

    /// refresh（thread/read）が返す形。アンロード済みの子は status が notLoaded になる。
    private func refreshed(_ status: ThreadStatus?) -> CodexChildThread {
        ChatSessionViewModel.codexChild(ThreadSummary(
            id: "child-1",
            cliVersion: "0",
            createdAt: 0,
            cwd: "/tmp",
            ephemeral: false,
            modelProvider: "test",
            preview: "",
            sessionId: "child-1",
            source: .appServer,
            status: status,
            turns: nil,
            updatedAt: 0,
            parentThreadId: "parent-1"
        ))
    }

    private func isVisible(_ state: CodexSubAgentState, dismissed: Bool = false) -> Bool {
        state.children.contains { child in
            CodexSubAgentPresentation.isVisibleInStrip(
                CodexSubAgentPresentation.ref(for: child),
                isDismissed: dismissed
            )
        }
    }

    @Test("自然完了後にアンロードされて notLoaded で refresh されても strip に戻らない")
    func naturallyCompletedChildStaysHiddenAfterNotLoadedRefresh() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(isVisible(state))

        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))
        #expect(!isVisible(state))

        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
    }

    @Test("完了通知の status が空文字でも完了扱いで strip から外れる")
    func emptyCompletionStatusIsCompleted() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: ""))
        #expect(!isVisible(state))
    }

    @Test("失敗は strip に残す")
    func failuresStayVisible() {
        for status in ["error", "systemError", "failed"] {
            #expect(CodexSubAgentPresentation.status(for: status) == .failed, "\(status)")
        }
        #expect(CodexSubAgentPresentation.status(for: "notLoaded") == .completed)
        #expect(CodexSubAgentPresentation.status(for: "") == .completed)
    }

    @Test("ユーザーが止めた子は停止確定で strip から消え、その後の refresh でも戻らない")
    func userStoppedChildLeavesStripAndIsNotRevivedByRefresh() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        #expect(state.stopState(for: "child-1") == .stopped)
        #expect(!isVisible(state))

        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
        state.apply(.available(children: [refreshed(.notLoaded)]))
        #expect(!isVisible(state))

        #expect(!isVisible(state, dismissed: true))
    }

    @Test("止めていない完了は notLoaded を跨いでも表示されない")
    func notStoppedCompletionIsNotUserStopped() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        #expect(!state.isSticky("child-1"))
        #expect(!isVisible(state))
    }

    @Test("失敗した子は、アンロード後の notLoaded / unknown の refresh で上書きされず残る")
    func failedChildSurvivesNotLoadedRefresh() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(isVisible(state))

        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(isVisible(state))
        state.apply(.validated(child: refreshed(nil)))
        #expect(isVisible(state))
        state.apply(.available(children: [refreshed(.notLoaded)]))
        #expect(isVisible(state))
        #expect(!isVisible(state, dismissed: true))
    }

    @Test("失敗した子が再実行されて active に戻れば、その状態を採用する")
    func failedChildIsReplacedByRunningRefresh() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        state.apply(.validated(child: child(status: "active", turn: "turn-2")))
        #expect(state.children.first?.status == "active")
    }

    @Test("失敗した子を refresh が active（別 turn）と返したら、失敗記録は片付いて実行中表示に戻り、次の idle refresh で札が消える")
    func runningRefreshClearsFailureRecordThenIdleRefreshHidesChild() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child(turn: "turn-1")]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(state.isSticky("child-1"))

        // 本番は一覧の refresh（.available のあと .validated）で子の状態が決まる。
        state.apply(.available(children: [child(status: "active", turn: "turn-2")]))
        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .running)
        #expect(!state.isSticky("child-1"))
        #expect(isVisible(state))

        state.apply(.available(children: [refreshed(.idle)]))
        #expect(!isVisible(state))
        #expect(!state.isSticky("child-1"))
    }

    @Test("実行中の子の thread/read が失敗（stale）しても、失敗にも完了にもせず実行中のまま保つ")
    func runningChildStaysRunningWhenReadFails() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.stale(threadId: "child-1", reason: "read failed"))

        let ref = CodexSubAgentPresentation.ref(for: state.children[0])
        #expect(ref.status == .running)
        #expect(isVisible(state))
        // 停止操作だけは失効する。✕ で閉じる対象（実行中ではない札）にもならない。
        #expect(state.stopState(for: "child-1") == .stale)
        #expect(SubAgentChipPresentation.control(isHovering: true, status: ref.status, stopState: .stale) == .none)

        // 次の refresh で実行中と確認できれば、そのまま復帰する。
        state.apply(.validated(child: child()))
        #expect(state.stopState(for: "child-1") == .available)
        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .running)
    }

    @Test("終わったと分かっている子（完了して消えた札・止めた札）は、遅れて届いた refresh の失敗 status で失敗札に戻らない")
    func lateRefreshFailureDoesNotRewriteEndedChild() {
        func failing() -> CodexChildThread { child(status: "error", turn: nil) }

        // 完了して札が消えたあと。
        var completed = CodexSubAgentState(parentThreadId: "parent-1")
        completed.apply(.available(children: [child()]))
        completed.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))
        completed.apply(.validated(child: failing()))
        completed.apply(.available(children: [failing()]))
        #expect(!isVisible(completed))
        #expect(!completed.isSticky("child-1"))

        // ユーザーが止めたあと。停止記録は失敗で上書きされない。
        var stopped = CodexSubAgentState(parentThreadId: "parent-1")
        stopped.apply(.available(children: [child()]))
        #expect(stopped.stopRequest(for: "child-1") != nil)
        stopped.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        stopped.apply(.validated(child: failing()))
        #expect(stopped.stopState(for: "child-1") == .stopped)
        #expect(stopped.children[0].status == "interrupted")

        // 実行中の子に対する失敗の報告は、従来どおり失敗として記録する。
        var running = CodexSubAgentState(parentThreadId: "parent-1")
        running.apply(.available(children: [child()]))
        running.apply(.validated(child: failing()))
        #expect(CodexSubAgentPresentation.ref(for: running.children[0]).status == .failed)
        #expect(isVisible(running))
    }

    @Test("read 失敗のあとに届いた完了通知（completed / interrupted）は通常どおり反映され、札が消える")
    func completionAfterReadFailureIsApplied() {
        for outcome in ["completed", "interrupted"] {
            var state = CodexSubAgentState(parentThreadId: "parent-1")
            state.apply(.available(children: [child()]))
            state.apply(.stale(threadId: "child-1", reason: "read failed"))
            state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: outcome))
            #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == (outcome == "interrupted" ? .stopped : .completed), "\(outcome)")
            #expect(state.children[0].activeTurnId == nil, "\(outcome)")
            #expect(!isVisible(state), "\(outcome)")
        }
    }

    @Test("read 失敗のあとに届いた失敗通知は失敗として反映され、札に残る")
    func failureAfterReadFailureIsApplied() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .failed)
        #expect(isVisible(state))
    }

    @Test("read 失敗のあとに Codex が実際に報告した完了・失敗だけが状態を変える")
    func onlyReportedOutcomeChangesStatusAfterReadFailure() {
        var completed = CodexSubAgentState(parentThreadId: "parent-1")
        completed.apply(.available(children: [child()]))
        completed.apply(.stale(threadId: "child-1", reason: "read failed"))
        completed.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(completed))

        var failed = CodexSubAgentState(parentThreadId: "parent-1")
        failed.apply(.available(children: [child()]))
        failed.apply(.stale(threadId: "child-1", reason: "read failed"))
        failed.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(CodexSubAgentPresentation.ref(for: failed.children[0]).status == .failed)
        #expect(isVisible(failed))
    }

    @Test("止めた子は stale と notLoaded の refresh を挟んでも、停止確定後は札に戻らない")
    func userStoppedChildSurvivesStaleThenNotLoaded() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        #expect(state.isSticky("child-1"))

        // 詳細の読み込み失敗で stale になり、stopState が上書きされる。
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(state.stopState(for: "child-1") == .stopped)
        #expect(state.isSticky("child-1"))
        #expect(!isVisible(state))
        #expect(!isVisible(state, dismissed: true))
    }

    @Test("止めた子が再び実行中になったら、止めた印は外れる")
    func userStoppedMarkClearsWhenRunningAgain() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        state.apply(.validated(child: child(status: "active", turn: "turn-2")))
        #expect(!state.isSticky("child-1"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-2", status: "completed"))
        #expect(!isVisible(state))
    }

    @Test("unavailable で止めた印もリセットされる")
    func unavailableResetsUserStoppedMark() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        state.apply(.unavailable(reason: "gone"))
        state.apply(.available(children: [child(status: "notLoaded", turn: nil)]))
        #expect(!state.isSticky("child-1"))
    }

    @Test("失敗 → 詳細の読み込み失敗（stale）→ notLoaded の refresh でも失敗は残る")
    func failedChildSurvivesStaleThenNotLoaded() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(state.children.first?.status == "failed")
        #expect(isVisible(state))
        #expect(!isVisible(state, dismissed: true))
    }

    @Test("停止成功後に、同じ（止めた）turn の active を返す古い in-flight refresh が来ても札に戻らない")
    func staleInFlightRefreshOfStoppedTurnDoesNotClearMark() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))

        state.apply(.validated(child: child(status: "active", turn: "turn-1")))
        #expect(state.isSticky("child-1"))
        #expect(state.children.first?.activeTurnId == nil)
        #expect(state.stopState(for: "child-1") != .available)

        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
        #expect(!isVisible(state, dismissed: true))
    }

    @Test("refresh で見つけた失敗も記録し、以後の notLoaded で消えない")
    func failureFoundByRefreshIsRecorded() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.validated(child: refreshed(.systemError)))
        state.apply(.validated(child: refreshed(.idle)))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(isVisible(state))
    }

    @Test("止めた後に別の turn で実行中に戻ったら印は外れ、その turn の自然完了で strip から消える")
    func newTurnAfterStopClearsStickyAndNaturalCompletionHides() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        #expect(!isVisible(state))

        state.apply(.validated(child: child(status: "active", turn: "turn-2")))
        #expect(!state.isSticky("child-1"))
        #expect(state.children.first?.activeTurnId == "turn-2")

        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-2", status: "completed"))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
    }

    @Test("一覧から消えた子の印は外れる")
    func stickyIsDroppedWhenChildDisappears() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        state.apply(.available(children: []))
        state.apply(.available(children: [refreshed(.notLoaded)]))
        #expect(!isVisible(state))
    }

    @Test("停止要求 → stale → interrupted 完了 → notLoaded の refresh でも、止めた子は札に戻らない")
    func stopRequestedThenStaleThenInterruptedCompletionIsSticky() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        #expect(state.isSticky("child-1"))
        // 実報告（interrupted）は通常どおり反映する。止めた子は停止済み。
        #expect(state.stopState(for: "child-1") == .stopped)

        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
        #expect(!isVisible(state, dismissed: true))
    }

    @Test("stale の直後に failed 完了が来ても失敗は記録され、notLoaded の refresh で消えない")
    func staleThenFailedCompletionIsSticky() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(state.isSticky("child-1"))
        #expect(state.stopState(for: "child-1") == .unavailable)

        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(isVisible(state))
    }

    @Test("stale の子への、停止要求も失敗でもない完了通知は、止めた・失敗の記録を残さない")
    func staleChildDoesNotRecordPlainCompletionsAsSticky() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))
        #expect(!state.isSticky("child-1"))
    }

    @Test("停止要求 → turnId の無い refresh → stale → 完了通知が無視される → notLoaded でも止めた子は札に戻らない")
    func stopRequestSurvivesRefreshWithoutTurnThenStale() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        #expect(state.isSticky("child-1"))

        state.apply(.available(children: [child(status: "active", turn: nil)]))
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
        #expect(!isVisible(state, dismissed: true))
    }

    @Test("停止要求 → stale → 同じ turn の読み込みが成功しても、interrupted を自然完了と扱わず止めた子として札に戻らない")
    func stopRequestThenStaleThenSameTurnReadKeepsStopped() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.stale(threadId: "child-1", reason: "read failed"))
        state.apply(.validated(child: child(status: "interrupted", turn: nil)))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(state.isSticky("child-1"))
        #expect(!isVisible(state))
        #expect(state.children.first?.activeTurnId == nil)
    }

    @Test("停止中は refresh が来ても実行中のまま停止中を保つ")
    func stoppingStaysStoppingAcrossSameTurnRefresh() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.validated(child: child(status: "active", turn: "turn-1")))
        #expect(state.stopState(for: "child-1") == .stopping)
        #expect(state.children.first?.activeTurnId == "turn-1")
        #expect(CodexSubAgentPresentation.status(for: state.children.first?.status ?? "") == .running)
    }

    @Test("停止要求が失敗したら止めた印は外れ、その後の自然完了で strip から消える")
    func rejectedStopClearsStickyAndNaturalCompletionHides() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.rejectStop(for: "child-1")
        #expect(!state.isSticky("child-1"))

        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(!isVisible(state))
    }

    @Test("停止中に turn が終わったと分かる refresh（idle / notLoaded）で、停止中のまま固まらず止めた子になる")
    func stoppingResolvesWhenRefreshShowsTurnEnded() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.validated(child: refreshed(.notLoaded)))
        #expect(state.stopState(for: "child-1") == .stopped)
        #expect(!isVisible(state))
        #expect(state.stopRequest(for: "child-1") == nil)
    }

    @Test("停止要求中に自然完了が報告されたら、止めた扱いにせず完了として扱う（失敗なら失敗）")
    func naturalOutcomeDuringPendingStopIsNotReportedAsStopped() {
        var completed = CodexSubAgentState(parentThreadId: "parent-1")
        completed.apply(.available(children: [child()]))
        #expect(completed.stopRequest(for: "child-1") != nil)
        completed.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "completed"))
        #expect(CodexSubAgentPresentation.ref(for: completed.children[0]).status == .completed)
        #expect(completed.stopState(for: "child-1") != .stopped)
        #expect(!completed.isSticky("child-1"))
        #expect(!isVisible(completed))

        var failed = CodexSubAgentState(parentThreadId: "parent-1")
        failed.apply(.available(children: [child()]))
        #expect(failed.stopRequest(for: "child-1") != nil)
        failed.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(CodexSubAgentPresentation.ref(for: failed.children[0]).status == .failed)
        #expect(isVisible(failed))
    }

    @Test("停止要求中に refresh が completed を報告しても、止めた扱いにしない")
    func completedRefreshDuringPendingStopIsNotStopped() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.validated(child: child(status: "completed", turn: nil)))
        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .completed)
        #expect(state.stopState(for: "child-1") != .stopped)
    }

    @Test("停止要求中の read 失敗（stale）は何も変えない。停止待ちも実行中表示も保ち、interrupted の実報告で初めて停止になる")
    func staleDuringPendingStopChangesNothingUntilInterruptedIsReported() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)

        state.apply(.stale(threadId: "child-1", reason: "read failed"))

        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .running)
        #expect(state.children[0].activeTurnId == "turn-1")
        #expect(state.stopState(for: "child-1") == .stopping)
        #expect(isVisible(state))

        // 確認が来ないままタイムアウトしても、実行中のまま押し直せる。
        var timedOut = state
        timedOut.rejectStop(for: "child-1")
        #expect(timedOut.stopState(for: "child-1") == .available)
        #expect(timedOut.stopRequest(for: "child-1") != nil)

        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        #expect(state.stopState(for: "child-1") == .stopped)
        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .stopped)
        #expect(!isVisible(state))
    }

    @Test("停止要求中に一覧が失敗（systemError など）を報告したら、停止待ちを解除して失敗として表示し、✕ で消せる")
    func failureRefreshDuringPendingStopIsApplied() {
        for viaAvailable in [false, true] {
            var state = CodexSubAgentState(parentThreadId: "parent-1")
            state.apply(.available(children: [child()]))
            #expect(state.stopRequest(for: "child-1") != nil)

            let failing = refreshed(.systemError)
            state.apply(viaAvailable ? .available(children: [failing]) : .validated(child: failing))

            let ref = CodexSubAgentPresentation.ref(for: state.children[0])
            #expect(ref.status == .failed, "available=\(viaAvailable)")
            #expect(isVisible(state), "available=\(viaAvailable)")
            #expect(!isVisible(state, dismissed: true), "available=\(viaAvailable)")
            #expect(state.stopState(for: "child-1") != .stopping, "available=\(viaAvailable)")
            #expect(SubAgentChipPresentation.control(isHovering: true, status: ref.status, stopState: state.stopState(for: "child-1")) == .dismiss)
        }
    }

    @Test("規則 B: 止めて確定した子は、遅れた失敗 refresh で失敗に書き換えない")
    func confirmedStopIsNotRewrittenByLateFailureRefresh() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        #expect(state.stopRequest(for: "child-1") != nil)
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "interrupted"))
        state.apply(.validated(child: refreshed(.systemError)))
        #expect(CodexSubAgentPresentation.ref(for: state.children[0]).status == .stopped)
        #expect(!isVisible(state))
    }
}
