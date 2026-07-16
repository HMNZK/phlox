import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test func isQuestionVisible_detectsPlanApprovalPrompt() {
  // 実機スクショ由来: Codex のプラン承認プロンプト（"submit answer" を含まない実プロンプト）。
  let text = """
    Implement this plan?
    1. Yes, implement this plan          Switch to Default and start coding.
    2. Yes, clear context and implement  Fresh thread. Context: 11% used.
    3. No, stay in Plan mode             Continue planning with the model.
    Press enter to confirm or esc to go back
    """
  #expect(CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_detectsConfirmFooterWrappedAcrossLines() {
  // 端末幅で折り返されても空白正規化で検出される。
  let text = "Press enter to\nconfirm or esc to go back"
  #expect(CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_detectsScreenshotLikeText() {
  let text = """
    Question 1/1 (1 unanswered)
    enter to submit answer
    esc to interrupt
    tab to add notes
    """
  #expect(CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_detectsMarkersSplitAcrossLines() {
  let text = """
    Question 1/1 (1 unanswered)
    enter to submit
    answer
  """
  #expect(CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_isCaseInsensitive() {
  let text = """
    ENTER TO SUBMIT ANSWER
    Unanswered
    """
  #expect(CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_rejectsUnansweredAlone() {
  let text = "There is 1 unanswered comment in this diff."
  #expect(!CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_rejectsSubmitAnswerWithoutReinforcingSignal() {
  let text = "enter to submit answer"
  #expect(!CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_rejectsEscToInterruptAlone() {
  let text = "esc to interrupt"
  #expect(!CodexQuestionDetector.isQuestionVisible(in: text))
}

@Test func isQuestionVisible_rejectsEmptyAndNormalOutput() {
  #expect(!CodexQuestionDetector.isQuestionVisible(in: ""))
  #expect(!CodexQuestionDetector.isQuestionVisible(in: "Running codex...\nDone."))
}
