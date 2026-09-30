import Testing
import CodexAppServerKit
@testable import SessionFeature

/// refresh（`.validated` / `.available`）と `.stale` は情報を落とす（lossy）。
/// 許されるのは「turnId 付きで実行中」か「実行中ではない」と言うことだけで、終わり方（failed / interrupted）を
/// 書いたり、既知の turnId を nil で消したり、自然完了で隠れた子を復活させたりしてはならない。
/// 権威あるイベント列の任意の位置に lossy な refresh を挟んでも、最終状態は挟まないときと一致する。
@Suite("Codex サブエージェント: lossy refresh の不変条件")
@MainActor
struct CodexSubAgentLossyRefreshPropertyTests {
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

    private func refreshed(_ status: ThreadStatus?) -> CodexChildThread {
        ChatSessionViewModel.codexChild(ThreadSummary(
            id: "child-1", cliVersion: "0", createdAt: 0, cwd: "/tmp", ephemeral: false,
            modelProvider: "test", preview: "", sessionId: "child-1", source: .appServer,
            status: status, turns: nil, updatedAt: 0, parentThreadId: "parent-1"
        ))
    }

    private enum Step {
        case available(CodexChildThread)
        case stopRequest
        case completed(turn: String, status: String)
        case refresh(CodexChildThread)
    }

    private enum Lossy: CaseIterable {
        case activeNilTurn, activeTurn1, activeTurn2, omittedStatus, notLoaded, idle, stale
    }

    private struct Sequence {
        let name: String
        let steps: [Step]
        /// この位置（= そこまでに適用した step 数）から、その turn の「実行中」という主張が起こり得る。
        let turn2StartsAt: Int?
        /// この位置以降でだけ「実行中ではない」主張を挟める（それ以前は停止要求などが成立しなくなる）。
        let notRunningFrom: Int
        let staleFrom: Int
    }

    private struct Snapshot: Equatable, CustomStringConvertible {
        var visible: Bool
        var statusClass: SubAgentStatus
        var stopState: CodexSubAgentStopState
        var description: String { "visible=\(visible) class=\(statusClass) stop=\(stopState)" }
    }

    private var sequences: [Sequence] {
        [
            Sequence(
                name: "自然完了",
                steps: [.available(child()), .completed(turn: "turn-1", status: "completed"), .refresh(refreshed(.notLoaded))],
                turn2StartsAt: nil, notRunningFrom: 1, staleFrom: 1
            ),
            Sequence(
                name: "失敗",
                steps: [.available(child()), .completed(turn: "turn-1", status: "failed"), .refresh(refreshed(.notLoaded))],
                turn2StartsAt: nil, notRunningFrom: 1, staleFrom: 1
            ),
            Sequence(
                name: "ユーザー停止",
                steps: [.available(child()), .stopRequest, .completed(turn: "turn-1", status: "interrupted"), .refresh(refreshed(.notLoaded))],
                turn2StartsAt: nil, notRunningFrom: 2, staleFrom: 2
            ),
            Sequence(
                name: "停止のあと新しい turn",
                steps: [
                    .available(child()), .stopRequest, .completed(turn: "turn-1", status: "interrupted"),
                    .refresh(child(status: "active", turn: "turn-2")),
                    .completed(turn: "turn-2", status: "completed"), .refresh(refreshed(.notLoaded)),
                ],
                turn2StartsAt: 4, notRunningFrom: 2, staleFrom: 2
            ),
            Sequence(
                name: "実行中のまま",
                steps: [.available(child()), .refresh(child(status: "active", turn: "turn-1"))],
                turn2StartsAt: nil, notRunningFrom: Int.max, staleFrom: 1
            ),
        ]
    }

    private func apply(_ step: Step, to state: inout CodexSubAgentState) {
        switch step {
        case .available(let c): state.apply(.available(children: [c]))
        case .stopRequest: _ = state.stopRequest(for: "child-1")
        case .completed(let turn, let status): state.apply(.turnCompleted(threadId: "child-1", turnId: turn, status: status))
        case .refresh(let c): state.apply(.validated(child: c))
        }
    }

    private func snapshot(_ state: CodexSubAgentState) -> Snapshot {
        let c = state.children[0]
        let ref = CodexSubAgentPresentation.ref(for: c)
        return Snapshot(
            visible: CodexSubAgentPresentation.isVisibleInStrip(ref, isDismissed: false),
            statusClass: ref.status,
            stopState: state.stopState(for: c.id)
        )
    }

    private func run(_ sequence: Sequence, inserting lossy: Lossy? = nil, at position: Int = 0, viaAvailable: Bool = false) -> Snapshot {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        for (index, step) in sequence.steps.enumerated() {
            if let lossy, position == index { insert(lossy, into: &state, viaAvailable: viaAvailable) }
            apply(step, to: &state)
        }
        if let lossy, position == sequence.steps.count { insert(lossy, into: &state, viaAvailable: viaAvailable) }
        return snapshot(state)
    }

    private func insert(_ lossy: Lossy, into state: inout CodexSubAgentState, viaAvailable: Bool) {
        let refresh: CodexChildThread
        switch lossy {
        case .stale:
            state.apply(.stale(threadId: "child-1", reason: "read failed"))
            return
        case .activeNilTurn: refresh = child(status: "active", turn: nil)
        case .activeTurn1: refresh = child(status: "active", turn: "turn-1")
        case .activeTurn2: refresh = child(status: "active", turn: "turn-2")
        case .omittedStatus: refresh = refreshed(nil)
        case .notLoaded: refresh = refreshed(.notLoaded)
        case .idle: refresh = refreshed(.idle)
        }
        state.apply(viaAvailable ? .available(children: [refresh]) : .validated(child: refresh))
    }

    private func isValid(_ lossy: Lossy, at position: Int, in sequence: Sequence) -> Bool {
        switch lossy {
        case .activeNilTurn, .activeTurn1: true
        case .activeTurn2: sequence.turn2StartsAt.map { position >= $0 } ?? false
        // status を省略した refresh は「情報なし」なので、どの位置でも何も変えない。
        case .omittedStatus: true
        case .notLoaded, .idle: position >= sequence.notRunningFrom
        // 最後の位置の stale は、次の refresh が来るまで stale のまま（stopState が .stale になるのが正しい）。
        case .stale: position >= sequence.staleFrom && position < sequence.steps.count
        }
    }

    @Test("基準: 権威あるイベント列だけの最終状態")
    func baselines() {
        let expected: [String: Snapshot] = [
            "自然完了": Snapshot(visible: false, statusClass: .completed, stopState: .unavailable),
            "失敗": Snapshot(visible: true, statusClass: .failed, stopState: .unavailable),
            "ユーザー停止": Snapshot(visible: false, statusClass: .stopped, stopState: .stopped),
            "停止のあと新しい turn": Snapshot(visible: false, statusClass: .completed, stopState: .unavailable),
            "実行中のまま": Snapshot(visible: true, statusClass: .running, stopState: .available),
        ]
        for sequence in sequences {
            #expect(run(sequence) == expected[sequence.name], "\(sequence.name)")
        }
    }

    @Test("どの位置にどの lossy refresh を挟んでも、最終状態は挟まないときと同じ")
    func lossyRefreshNeverChangesTheOutcome() {
        var checked = 0
        for sequence in sequences {
            let baseline = run(sequence)
            for position in 1...sequence.steps.count {
                for lossy in Lossy.allCases where isValid(lossy, at: position, in: sequence) {
                    for viaAvailable in [false, true] where !(lossy == .stale && viaAvailable) {
                        checked += 1
                        let result = run(sequence, inserting: lossy, at: position, viaAvailable: viaAvailable)
                        #expect(
                            result == baseline,
                            "\(sequence.name) / 位置\(position) / \(lossy) / available=\(viaAvailable): \(result) != \(baseline)"
                        )
                    }
                }
            }
        }
        #expect(checked > 100)
    }

    @Test("完了済みの子は、status を省略した refresh（unknown）で失敗として復活しない")
    func omittedStatusDoesNotResurrectCompletedChild() {
        #expect(CodexSubAgentPresentation.status(for: "unknown") == .completed)
        #expect(CodexSubAgentPresentation.status(for: "") == .completed)
        #expect(CodexSubAgentPresentation.status(for: "failed") == .failed)
        #expect(CodexSubAgentPresentation.status(for: "error") == .failed)
        #expect(CodexSubAgentPresentation.status(for: "systemError") == .failed)
    }

    @Test("別の既知 turn を実行中の子への、古い turn の完了通知は無視する")
    func completionOfAnotherKnownTurnIsIgnoredWhileRunning() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child(turn: "turn-2")]))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(state.children.first?.activeTurnId == "turn-2")
        #expect(!state.isSticky("child-1"))
    }

    @Test("完了通知は activeTurnId が消えていても終わり方を記録する")
    func terminalCompletionRecordedEvenWithoutActiveTurn() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.validated(child: refreshed(.notLoaded)))
        state.apply(.turnCompleted(threadId: "child-1", turnId: "turn-1", status: "failed"))
        #expect(state.isSticky("child-1"))
        #expect(snapshot(state) == Snapshot(visible: true, statusClass: .failed, stopState: .unavailable))
    }

    @Test("実行中の子に status を省略した refresh が来ても、同じ turn の active でなお実行中で停止できる")
    func omittedStatusWhileRunningKeepsChildRunningAndStoppable() {
        var state = CodexSubAgentState(parentThreadId: "parent-1")
        state.apply(.available(children: [child()]))
        state.apply(.validated(child: refreshed(nil)))
        state.apply(.validated(child: child(status: "active", turn: "turn-1")))
        #expect(snapshot(state) == Snapshot(visible: true, statusClass: .running, stopState: .available))
        #expect(state.children.first?.activeTurnId == "turn-1")
        #expect(state.stopRequest(for: "child-1") != nil)
    }

    @Test("status を省略した refresh は、失敗・停止済み・完了済みの子の状態も変えない")
    func omittedStatusChangesNothing() {
        for sequence in sequences.prefix(4) {
            var state = CodexSubAgentState(parentThreadId: "parent-1")
            for step in sequence.steps.dropLast() { apply(step, to: &state) }
            let before = snapshot(state)
            state.apply(.validated(child: refreshed(nil)))
            #expect(snapshot(state) == before, "\(sequence.name)")
        }
    }
}
