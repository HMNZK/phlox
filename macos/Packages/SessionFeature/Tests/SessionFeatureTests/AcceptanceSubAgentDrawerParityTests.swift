import Foundation
import Testing
@testable import SessionFeature

// subagent-view-parity run / task-2 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約: SubAgentDrawerView はメイン ChatTranscriptView と同じ意味論の表示述語
// SubAgentDrawerPresentation を経由して描画を決める。
// 1. Thinking インジケータはサブエージェントが running の間だけ表示する。
// 2. ツールコール（commandExecution）の実行中ローディングは
//    「transcript 末尾の item かつサブエージェント running」のときだけ true
//    （メイン ChatTranscriptView.isRunningCommand と同じ結合則）。
// 3. reasoningPreview は running 中のみ、transcript 中の最新 reasoning テキストを返す。

private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

@Test
func thinkingIndicatorShownOnlyWhileRunning() {
    #expect(SubAgentDrawerPresentation.showsThinkingIndicator(status: .running))
    #expect(!SubAgentDrawerPresentation.showsThinkingIndicator(status: .completed))
    #expect(!SubAgentDrawerPresentation.showsThinkingIndicator(status: .failed))
}

@Test
func lastCommandExecutionIsRunningOnlyWhileSubAgentRunning() {
    let cmd = ChatItem.commandExecution(id: "c1", command: "ls -la", output: "", timestamp: t0)
    #expect(SubAgentDrawerPresentation.isRunningCommand(item: cmd, lastItemID: "c1", status: .running))
    #expect(!SubAgentDrawerPresentation.isRunningCommand(item: cmd, lastItemID: "c2", status: .running))
    #expect(!SubAgentDrawerPresentation.isRunningCommand(item: cmd, lastItemID: "c1", status: .completed))
    #expect(!SubAgentDrawerPresentation.isRunningCommand(item: cmd, lastItemID: "c1", status: .failed))

    let msg = ChatItem.agentMessage(id: "m1", text: "hi", timestamp: t0)
    #expect(!SubAgentDrawerPresentation.isRunningCommand(item: msg, lastItemID: "m1", status: .running))
}

@Test
func reasoningPreviewReflectsLatestReasoningOnlyWhileRunning() {
    let transcript: [ChatItem] = [
        .userMessage(id: "p", text: "task prompt", timestamp: t0, attachments: []),
        .reasoning(id: "r1", text: "first thought", timestamp: t0),
        .reasoning(id: "r2", text: "latest thought", timestamp: t0),
    ]
    #expect(SubAgentDrawerPresentation.reasoningPreview(transcript: transcript, status: .running) == "latest thought")
    #expect(SubAgentDrawerPresentation.reasoningPreview(transcript: transcript, status: .completed) == nil)
    #expect(SubAgentDrawerPresentation.reasoningPreview(transcript: [], status: .running) == nil)
}
