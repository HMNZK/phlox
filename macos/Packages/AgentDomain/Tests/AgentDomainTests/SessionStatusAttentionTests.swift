import Testing
import AgentDomain

// 「未確認の停止（＝ユーザーの対応待ち）」を入口でラッチするかの決定表。
// UI（グリッド赤枠・サイドバー強調・Dock バッジ）が参照する単一の真実源のため固定する。
// idle（ターン完了）は入口では本物の完了か中断キャンセルか区別できないため、この判定には
// 含めず完了通知経路でラッチする。ゆえにここでは idle は false であることを固定する。

@Test func attentionOnEntry_isTrueForAwaitingCompletedError() {
    #expect(SessionStatus.awaitingApproval(prompt: "approve?").latchesUnseenAttentionOnEntry)
    #expect(SessionStatus.completed(exitCode: 0).latchesUnseenAttentionOnEntry)
    #expect(SessionStatus.error(message: "boom").latchesUnseenAttentionOnEntry)
}

@Test func attentionOnEntry_isFalseForStartingRunning() {
    #expect(SessionStatus.starting.latchesUnseenAttentionOnEntry == false)
    #expect(SessionStatus.running.latchesUnseenAttentionOnEntry == false)
}

@Test func attentionOnEntry_isFalseForIdle_becauseGatedByCompletionPath() {
    // idle は「本物の完了」か「escape/interrupt キャンセル」かを入口で区別できないため
    // ここでは拾わない（完了通知経路でのみラッチする）。
    #expect(SessionStatus.idle.latchesUnseenAttentionOnEntry == false)
}
