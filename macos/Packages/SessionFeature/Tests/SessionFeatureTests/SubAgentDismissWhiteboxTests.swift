import Foundation
import Testing
@testable import SessionFeature

@Suite("SubAgent dismiss whitebox")
@MainActor
struct SubAgentDismissWhiteboxTests {
    @Test
    func completionRemovesSubAgentFromStripButKeepsFinalTranscript() {
        let model = ChatSubAgentModel()
        model.upsertSubAgent(
            toolUseId: "toolu_complete",
            subagentType: "Explore",
            description: "complete",
            status: .running,
            summary: nil,
            outputFile: nil
        )

        model.completeSubAgent(toolUseId: "toolu_complete", status: "completed", summary: "done", outputFile: nil)

        #expect(model.subAgents.first?.status == .completed)
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_complete" })
        #expect(model.transcript(for: "toolu_complete").contains {
            if case .agentMessage(_, let text, _) = $0 { text == "done" } else { false }
        })
    }

    @Test
    func lateStartRenamesWithoutRewindingCompletedStatus() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_late", subagentType: "general-purpose", description: "先着の名前")
        model.completeSubAgent(toolUseId: "toolu_late", status: "completed", summary: "done", outputFile: nil)

        // 親の Task 入力が完了通知より後に届いて、名前だけ更新される。
        model.markStarted(toolUseId: "toolu_late", subagentType: "general-purpose", description: "親が付けた名前")

        let ref = model.subAgents.first { $0.id == "toolu_late" }
        #expect(ref?.description == "親が付けた名前")
        #expect(ref?.status == .completed)
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_late" })
    }

    @Test
    func lateStartKeepsFailedStatus() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_fail", subagentType: "x", description: "a")
        model.completeSubAgent(toolUseId: "toolu_fail", status: "failed", summary: "", outputFile: nil)
        model.markStarted(toolUseId: "toolu_fail", subagentType: "x", description: "b")
        #expect(model.subAgents.first?.status == .failed)
        #expect(model.subAgents.first?.description == "b")
    }

    @Test
    func dismissKeepsSubAgentButRemovesItFromStrip() {
        let model = ChatSubAgentModel()
        model.upsertSubAgent(
            toolUseId: "toolu_drop",
            subagentType: "Explore",
            description: "drop",
            status: .failed,
            summary: nil,
            outputFile: nil
        )

        model.dismissSubAgent("toolu_drop")

        #expect(model.subAgents.contains { $0.id == "toolu_drop" })
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_drop" })
    }

    @Test
    func dismissingOneSubAgentLeavesTheOtherInStrip() {
        let model = ChatSubAgentModel()
        for id in ["toolu_kept", "toolu_other"] {
            model.upsertSubAgent(
                toolUseId: id,
                subagentType: "Explore",
                description: id,
                status: .running,
                summary: nil,
                outputFile: nil
            )
        }

        model.dismissSubAgent("toolu_other")

        #expect(model.stripSubAgents.contains { $0.id == "toolu_kept" })
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_other" })
    }

    @Test
    func dismissedSubAgentStaysOutAfterUpsert() {
        let model = ChatSubAgentModel()
        model.upsertSubAgent(
            toolUseId: "toolu_sticky",
            subagentType: "Explore",
            description: "before",
            status: .running,
            summary: nil,
            outputFile: nil
        )
        model.dismissSubAgent("toolu_sticky")

        model.upsertSubAgent(
            toolUseId: "toolu_sticky",
            subagentType: "",
            description: "",
            status: .failed,
            summary: "updated",
            outputFile: nil
        )

        #expect(model.subAgents.contains { $0.id == "toolu_sticky" && $0.status == .failed })
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_sticky" })
    }

    @Test
    func chipControlsAreVisibleOnlyWhileHovering() {
        for status in [SubAgentStatus.running, .completed, .failed, .stopped] {
            for stopState in [nil, CodexSubAgentStopState.available, .stopping, .stopped, .unavailable, .stale] {
                #expect(SubAgentChipPresentation.control(isHovering: false, status: status, stopState: stopState) == .none)
            }
        }
    }

    @Test
    func runningStoppableChipShowsStopInsteadOfDismiss() {
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .running, stopState: .available) == .stop)
    }

    @Test
    func stoppingChipShowsNoControl() {
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .running, stopState: .stopping) == .none)
    }

    @Test
    func runningChipNeverShowsDismiss() {
        // 停止 API の無い実行中の子（Claude）・turn 不明・stale でも、✕ は出さない（閉じても子は走り続ける）。
        for stopState in [nil, CodexSubAgentStopState.unavailable, .stale, .stopped, .stopping] {
            #expect(SubAgentChipPresentation.control(isHovering: true, status: .running, stopState: stopState) == .none)
        }
        for stopState in [nil, CodexSubAgentStopState.available, .stopping, .stopped, .unavailable, .stale] {
            #expect(SubAgentChipPresentation.control(isHovering: true, status: .running, stopState: stopState) != .dismiss)
        }
    }

    @Test
    func notRunningChipShowsDismiss() {
        // ユーザーが止めた子・失敗・完了
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .stopped, stopState: .stopped) == .dismiss)
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .failed, stopState: .unavailable) == .dismiss)
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .failed, stopState: nil) == .dismiss)
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .completed, stopState: .available) == .dismiss)
    }

    @Test
    func statusIconIsLoadingWhileRunningAndFailureMarkOnFailureOnly() {
        #expect(SubAgentChipPresentation.statusIcon(for: .running) == .loading)
        #expect(SubAgentChipPresentation.statusIcon(for: .failed) == .failure)
        #expect(SubAgentChipPresentation.statusIcon(for: .completed) == nil)
        #expect(SubAgentChipPresentation.statusIcon(for: .stopped) == nil)
    }

    @Test
    func codexInterruptedMapsToStopped() {
        #expect(CodexSubAgentPresentation.status(for: "interrupted") == .stopped)
    }

    @Test
    func claudeStoppedNotificationMakesTheChildStoppedAndRemovesTheChip() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_s", subagentType: "x", description: "a")
        model.completeSubAgent(toolUseId: "toolu_s", status: "stopped", summary: "", outputFile: nil)
        #expect(model.subAgents.first?.status == .stopped)
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_s" })
    }

    @Test
    func failedChipStaysInStripAndShowsDismiss() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_f", subagentType: "x", description: "a")
        model.completeSubAgent(toolUseId: "toolu_f", status: "failed", summary: "", outputFile: nil)
        #expect(model.stripSubAgents.contains { $0.id == "toolu_f" })
        #expect(SubAgentChipPresentation.control(isHovering: true, status: .failed, stopState: model.stopState(for: "toolu_f")) == .dismiss)
    }

    // MARK: Claude の個別停止（ChatSubAgentModel）

    @Test
    func stopNeedsAKnownTaskAndIsSingleFlight() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_1", subagentType: "x", description: "a")
        #expect(model.stopState(for: "toolu_1") == nil)
        #expect(model.beginStop("toolu_1") == nil)

        model.markStoppable("toolu_1")
        #expect(model.stopState(for: "toolu_1") == .available)
        #expect(model.beginStop("toolu_1") == 1)
        #expect(model.stopState(for: "toolu_1") == .stopping)
        #expect(model.beginStop("toolu_1") == nil)
    }

    @Test
    func failedStopReturnsToAvailableAndCanBeRetried() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_1", subagentType: "x", description: "a")
        model.markStoppable("toolu_1")
        #expect(model.beginStop("toolu_1") == 1)
        model.stopFailed("toolu_1", attempt: 1)
        #expect(model.stopState(for: "toolu_1") == .available)
        #expect(model.beginStop("toolu_1") == 2)
    }

    @Test
    func finishedChildHasNoStopState() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_1", subagentType: "x", description: "a")
        model.markStoppable("toolu_1")
        model.completeSubAgent(toolUseId: "toolu_1", status: "stopped", summary: "", outputFile: nil)
        #expect(model.stopState(for: "toolu_1") == nil)
        #expect(model.beginStop("toolu_1") == nil)
    }

    @Test
    func stoppedChildIsTerminalAgainstLaterCompletionOrFailure() {
        for later in ["completed", "failed"] {
            let model = ChatSubAgentModel()
            model.markStarted(toolUseId: "toolu_s", subagentType: "x", description: "a")
            model.completeSubAgent(toolUseId: "toolu_s", status: "stopped", summary: "", outputFile: nil)

            // 親の Agent tool_result 由来の再通知
            model.completeSubAgent(toolUseId: "toolu_s", status: later, summary: "The user doesn't want to proceed", outputFile: nil)

            #expect(model.subAgents.first?.status == .stopped, "\(later)")
            #expect(!model.stripSubAgents.contains { $0.id == "toolu_s" }, "\(later)")
        }
    }

    @Test
    func staleAttemptFailureDoesNotReleaseTheCurrentStop() {
        let model = ChatSubAgentModel()
        model.markStarted(toolUseId: "toolu_1", subagentType: "x", description: "a")
        model.markStoppable("toolu_1")
        #expect(model.beginStop("toolu_1") == 1)
        #expect(model.stopFailed("toolu_1", attempt: 1))      // タイムアウト
        #expect(model.beginStop("toolu_1") == 2)              // 再試行

        #expect(!model.stopFailed("toolu_1", attempt: 1))     // 1 回目への遅れた error
        #expect(model.stopState(for: "toolu_1") == .stopping)
        #expect(model.stopFailed("toolu_1", attempt: 2))
        #expect(model.stopState(for: "toolu_1") == .available)
    }
}
