import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

// CodexSessionAdapter は SessionViewModel から抽出した codex 固有の状態機械。
// 信頼プロンプト自動応答の 1 回限定と、質問検知 → 回答送信 → 復帰の遷移を
// タイミング非依存で検証する。

private let trustPromptText = "Do you trust the contents of this directory?\n1. Yes, continue"
private let questionText = """
Question from Codex
unanswered
enter to submit answer
"""
private let plainText = "plain output without a visible question"

// MARK: - 信頼プロンプト自動応答

@Test @MainActor
func trustPrompt_visibleAndUnanswered_consumesOnce() {
    let adapter = CodexSessionAdapter()

    #expect(adapter.consumeTrustPromptAutoAnswer(visibleText: trustPromptText) == true)
    #expect(adapter.didAutoAnswerTrustPrompt)

    // 応答済みなら、同じ文言が可視のままでも二重応答しない。
    #expect(adapter.consumeTrustPromptAutoAnswer(visibleText: trustPromptText) == false)
}

@Test @MainActor
func trustPrompt_answered_skipsVisibleTextEvaluation() {
    let adapter = CodexSessionAdapter()
    _ = adapter.consumeTrustPromptAutoAnswer(visibleText: trustPromptText)

    // 応答済みガードにより可視テキストの構築自体をスキップする（P2-c）。
    var evaluated = false
    let lazyText: () -> String = {
        evaluated = true
        return trustPromptText
    }
    let result = adapter.consumeTrustPromptAutoAnswer(visibleText: lazyText())
    #expect(result == false)
    #expect(evaluated == false)
}

@Test @MainActor
func trustPrompt_notVisible_doesNotConsume() {
    let adapter = CodexSessionAdapter()

    #expect(adapter.consumeTrustPromptAutoAnswer(visibleText: plainText) == false)
    #expect(adapter.didAutoAnswerTrustPrompt == false)
}

// MARK: - 質問検知の状態機械

@Test @MainActor
func question_visibleWhileRunning_entersAwaitingWithNotification() {
    let adapter = CodexSessionAdapter()

    let action = adapter.reconcileQuestion(visibleText: questionText, status: .running)

    #expect(action == .enterAwaiting(notifyAwaitingInput: true))
    #expect(adapter.isAwaitingQuestion)
}

@Test @MainActor
func question_visibleWhileIdle_entersAwaitingWithoutNotification() {
    let adapter = CodexSessionAdapter()

    let action = adapter.reconcileQuestion(visibleText: questionText, status: .idle)

    #expect(action == .enterAwaiting(notifyAwaitingInput: false))
    #expect(adapter.isAwaitingQuestion)
}

@Test @MainActor
func question_visibleWhileStarting_isIgnored() {
    let adapter = CodexSessionAdapter()

    let action = adapter.reconcileQuestion(visibleText: questionText, status: .starting)

    #expect(action == .none)
    #expect(adapter.isAwaitingQuestion == false)
}

@Test @MainActor
func question_stillVisibleAfterHookRewoundStatus_reasserts() {
    let adapter = CodexSessionAdapter()
    _ = adapter.reconcileQuestion(visibleText: questionText, status: .running)

    // hook イベント(stop 等)が status を idle へ巻き戻しても、質問が可視なら awaiting へ再整合する。
    let action = adapter.reconcileQuestion(visibleText: questionText, status: .idle)

    #expect(action == .reassertAwaiting)
}

@Test @MainActor
func question_stillVisibleWhileAlreadyAwaiting_noAction() {
    let adapter = CodexSessionAdapter()
    _ = adapter.reconcileQuestion(visibleText: questionText, status: .running)

    let action = adapter.reconcileQuestion(
        visibleText: questionText,
        status: .awaitingApproval(prompt: "Codex is asking a question")
    )

    #expect(action == .none)
}

@Test @MainActor
func question_disappearsWithoutSubmit_staysAwaiting() {
    let adapter = CodexSessionAdapter()
    _ = adapter.reconcileQuestion(visibleText: questionText, status: .running)

    // 回答未送信のままマーカーが一時的に消えても（再描画等）回答待ちは維持する。
    let action = adapter.reconcileQuestion(
        visibleText: plainText,
        status: .awaitingApproval(prompt: "Codex is asking a question")
    )

    #expect(action == .none)
    #expect(adapter.isAwaitingQuestion)
}

@Test @MainActor
func question_disappearsAfterSubmit_resumesRunning() {
    let adapter = CodexSessionAdapter()
    _ = adapter.reconcileQuestion(visibleText: questionText, status: .running)
    adapter.noteInputSubmitted()

    let action = adapter.reconcileQuestion(
        visibleText: plainText,
        status: .awaitingApproval(prompt: "Codex is asking a question")
    )

    #expect(action == .resumeRunning)
    #expect(adapter.isAwaitingQuestion == false)
}

@Test @MainActor
func noteInputSubmitted_whileNotAwaiting_doesNotArmResume() {
    let adapter = CodexSessionAdapter()

    // 質問待ちでない通常入力は「回答送信」として扱わない。
    adapter.noteInputSubmitted()
    _ = adapter.reconcileQuestion(visibleText: questionText, status: .running)
    let action = adapter.reconcileQuestion(
        visibleText: plainText,
        status: .awaitingApproval(prompt: "Codex is asking a question")
    )

    #expect(action == .none)
    #expect(adapter.isAwaitingQuestion)
}

// MARK: - 処理中(turn 開始)検知

@Test
func indicatesProcessing_whenWorkingIndicatorVisible_isTrue() {
    // codex は処理中に "Working" と "esc to interrupt" を表示する。
    let visible = "• Working (5s • esc to interrupt)\n› \ngpt-5.5 high · Context 100% left"
    #expect(CodexSessionAdapter.indicatesProcessing(in: visible))
}

@Test
func indicatesProcessing_whenOnlyEscToInterruptVisible_isTrue() {
    #expect(CodexSessionAdapter.indicatesProcessing(in: "Starting MCP servers (1/2) (0s • esc to interrupt)"))
}

@Test
func indicatesProcessing_whenComposerHoldsTextButNotProcessing_isFalse() {
    // submit 失敗時に滞留する典型: 本文が composer に残り、処理中表示が無い。
    let stuck = "› [from Alice] タスク仕様 docs/orchestration/tasks/T001.md を読み作業せよ\ngpt-5.5 high · Context 100% left · weekly 58% left"
    #expect(CodexSessionAdapter.indicatesProcessing(in: stuck) == false)
}

@Test @MainActor
func reset_clearsTrustPromptAndQuestionState() {
    let adapter = CodexSessionAdapter()
    _ = adapter.consumeTrustPromptAutoAnswer(visibleText: trustPromptText)
    _ = adapter.reconcileQuestion(visibleText: questionText, status: .running)

    adapter.reset()

    #expect(adapter.didAutoAnswerTrustPrompt == false)
    #expect(adapter.isAwaitingQuestion == false)
    // restart 後は信頼プロンプトへ再度応答できる。
    #expect(adapter.consumeTrustPromptAutoAnswer(visibleText: trustPromptText) == true)
}
