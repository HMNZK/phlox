import Testing
import AgentDomain
@testable import DesignSystem

@Suite @MainActor struct StatusBadgeLabelTests {
    @Test func startingLabel() {
        #expect(StatusBadge.label(for: .starting) == "起動中")
    }

    @Test func idleLabel() {
        #expect(StatusBadge.label(for: .idle) == "待機") // 再設計（12 Design System）で語彙変更
    }

    @Test func runningLabel() {
        #expect(StatusBadge.label(for: .running) == "実行中")
    }

    @Test func awaitingApprovalLabel() {
        #expect(StatusBadge.label(for: .awaitingApproval(prompt: "anything")) == "承認待ち")
    }

    @Test(arguments: [0, 1, 137])
    func completedLabelIsStopAndExitCodeMovesToHint(code: Int32) {
        // 再設計: 一覧の語彙は「完了」（「停止」は使わない）。終了コードは nextActionHint / helpText で確認できる。
        #expect(StatusBadge.label(for: .completed(exitCode: code)) == "完了")
        #expect(StatusBadge.nextActionHint(for: .completed(exitCode: code))?.contains("終了コード \(code)") == true)
    }

    @Test func errorLabel() {
        #expect(StatusBadge.label(for: .error(message: "boom")) == "エラー")
    }
}

/// 再設計: 色が付くのは対応待ちの 4 状態だけ。実行中は補助文字、ほかは弱い文字（無彩色）。
@Suite @MainActor struct StatusBadgeColorTests {
    @Test func nonAttentionStatesAreAchromatic() {
        #expect(StatusBadge.color(for: .starting) == DSColor.textTertiary)
        #expect(StatusBadge.color(for: .idle) == DSColor.textTertiary)
        #expect(StatusBadge.color(for: .completed(exitCode: 0)) == DSColor.textTertiary)
        #expect(StatusBadge.color(for: .running) == DSColor.textSecondary)
    }

    @Test func attentionStatesUseTheirInk() {
        #expect(StatusBadge.color(for: .awaitingApproval(prompt: "")) == DSColor.attentionInk(.approval))
        #expect(StatusBadge.color(for: .awaitingUserQuestion) == DSColor.attentionInk(.question))
        #expect(StatusBadge.color(for: .error(message: "")) == DSColor.attentionInk(.error))
        #expect(SessionDisplayState.stalled.color == DSColor.attentionInk(.stalled))
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
        // task-30（UX-02）: ヘルプは語彙＋次の操作＋本文。本文は必ず含まれる。
        #expect(StatusBadge.helpText(for: .error(message: "out of memory")).hasSuffix("\nout of memory"))
    }

    @Test(arguments: [
        SessionStatus.starting,
        .idle,
        .running,
        .awaitingApproval(prompt: "x"),
        .completed(exitCode: 0),
    ])
    func nonErrorHelpStartsWithLabel(status: SessionStatus) {
        // task-30（UX-02）: 色だけに頼らないため、非エラーでもヘルプに語彙が入る。
        #expect(StatusBadge.helpText(for: status).hasPrefix(StatusBadge.label(for: status)))
    }
}
