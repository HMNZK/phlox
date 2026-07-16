import Testing
import AgentDomain
@testable import DesignSystem

@Suite @MainActor struct StatusBadgeLabelTests {
    @Test func startingLabel() {
        #expect(StatusBadge.label(for: .starting) == "起動中")
    }

    @Test func idleLabel() {
        #expect(StatusBadge.label(for: .idle) == "待機中")
    }

    @Test func runningLabel() {
        #expect(StatusBadge.label(for: .running) == "実行中")
    }

    @Test func awaitingApprovalLabel() {
        #expect(StatusBadge.label(for: .awaitingApproval(prompt: "anything")) == "承認待ち")
    }

    @Test(arguments: [0, 1, 137])
    func completedLabelIncludesExitCode(code: Int32) {
        #expect(StatusBadge.label(for: .completed(exitCode: code)) == "完了 (\(code))")
    }

    @Test func errorLabel() {
        #expect(StatusBadge.label(for: .error(message: "boom")) == "エラー")
    }
}

@Suite @MainActor struct StatusBadgeColorTests {
    @Test func startingIsGray() {
        #expect(StatusBadge.color(for: .starting) == DSColor.statusStarting)
    }

    @Test func idleIsGray() {
        #expect(StatusBadge.color(for: .idle) == DSColor.statusIdle)
    }

    @Test func runningUsesStatusRunningColor() {
        #expect(StatusBadge.color(for: .running) == DSColor.statusRunning)
    }

    @Test func awaitingApprovalIsOrange() {
        #expect(StatusBadge.color(for: .awaitingApproval(prompt: "")) == DSColor.statusAwaitingApproval)
    }

    @Test func completedIsGreen() {
        #expect(StatusBadge.color(for: .completed(exitCode: 0)) == DSColor.statusCompleted)
    }

    @Test func errorIsRed() {
        #expect(StatusBadge.color(for: .error(message: "")) == DSColor.statusError)
    }
}

@Suite @MainActor struct StatusBadgeIconTests {
    @Test func idleIconIsPauseCircle() {
        #expect(StatusBadge.iconName(for: .idle) == "pause.circle")
    }
}

@Suite @MainActor struct StatusBadgeEnglishLabelTests {
    @Test func startingEnglishLabel() {
        #expect(StatusBadge.englishLabel(for: .starting) == "starting")
    }

    @Test func idleEnglishLabel() {
        #expect(StatusBadge.englishLabel(for: .idle) == "idle")
    }

    @Test func runningEnglishLabel() {
        #expect(StatusBadge.englishLabel(for: .running) == "running")
    }

    @Test func awaitingApprovalEnglishLabel() {
        #expect(StatusBadge.englishLabel(for: .awaitingApproval(prompt: "x")) == "awaiting")
    }

    @Test func completedExitCodeZeroEnglishLabel() {
        #expect(StatusBadge.englishLabel(for: .completed(exitCode: 0)) == "done")
    }

    @Test(arguments: [1, 137])
    func completedNonZeroExitCodeEnglishLabel(code: Int32) {
        #expect(StatusBadge.englishLabel(for: .completed(exitCode: code)) == "exited")
    }

    @Test func errorEnglishLabel() {
        #expect(StatusBadge.englishLabel(for: .error(message: "boom")) == "error")
    }
}

@Suite @MainActor struct StatusBadgeHelpTextTests {
    @Test func errorHelpShowsMessage() {
        #expect(StatusBadge.helpText(for: .error(message: "out of memory")) == "out of memory")
    }

    @Test(arguments: [
        SessionStatus.starting,
        .idle,
        .running,
        .awaitingApproval(prompt: "x"),
        .completed(exitCode: 0),
    ])
    func nonErrorHelpIsEmpty(status: SessionStatus) {
        #expect(StatusBadge.helpText(for: status) == "")
    }
}
