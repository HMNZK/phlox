import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

@Suite("04 会話画面: 使用量・要約・追従")
@MainActor
struct SessionChatRedesignTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("トークン数は 1.9k / 18.2k / 142k / 1.2M の短い表記")
    func compactTokenCounts() {
        #expect(TurnCostCell.compact(950) == "950")
        #expect(TurnCostCell.compact(1_900) == "1.9k")
        #expect(TurnCostCell.compact(18_200) == "18.2k")
        #expect(TurnCostCell.compact(142_000) == "142k")
        #expect(TurnCostCell.compact(1_200_000) == "1.2M")
    }

    @Test("コンテキスト使用率は使用 / 上限の四捨五入。どちらか無ければ出さない")
    func contextPercent() {
        #expect(TurnCostCell.contextPercent(TurnUsage(contextUsedTokens: 92_000, contextWindowTokens: 200_000)) == 46)
        #expect(TurnCostCell.contextPercent(TurnUsage(contextUsedTokens: 92_000)) == nil)
        #expect(TurnCostCell.contextPercent(nil) == nil)
    }

    @Test("トークン内訳は持っている値だけを出す（コストだけのエージェントは行を足さない）")
    func tokenTextOnlyWhenPresent() {
        #expect(TurnCostCell.tokenText(TurnUsage(costUSD: 0.4)) == nil)
        #expect(TurnCostCell.tokenText(TurnUsage(inputTokens: 18_200)) != nil)
    }

    @Test("要約は最後のユーザー入力以降の最後のコマンド・ファイル変更。5 秒未満は出さない")
    func recapFollowsLatestActivity() {
        let items: [ChatItem] = [
            .commandExecution(id: "old", command: "make", output: "", timestamp: t0),
            .userMessage(id: "u", text: "直して", timestamp: t0),
            .commandExecution(id: "c1", command: "cat Foo.swift", output: "", timestamp: t0),
            .fileChange(id: "f1", changes: [FilePatchChange(path: "Sources/App/Foo.swift", diff: "")], timestamp: t0),
            .commandExecution(id: "c2", command: "swift build", output: "", timestamp: t0),
        ]
        #expect(ChatRecap.summary(transcript: items, elapsed: 10) == .activity(.running("swift build")))
        #expect(ChatRecap.summary(transcript: Array(items.prefix(4)), elapsed: 10) == .activity(.editing("Foo.swift")))
        #expect(ChatRecap.summary(transcript: items, elapsed: 3) == nil)
    }

    @Test("コマンドが無ければ推論の見出しを使い、ユーザー入力より前の活動は数えない")
    func recapFallsBackToReasoningHeadline() {
        let items: [ChatItem] = [
            .commandExecution(id: "old", command: "make", output: "", timestamp: t0),
            .userMessage(id: "u", text: "設計して", timestamp: t0),
            .reasoning(id: "r", text: "まず全体を見る\n## 認証フローを設計", timestamp: t0),
        ]
        #expect(ChatRecap.summary(transcript: items, elapsed: 10) == .headline("認証フローを設計"))
    }

    @Test("後続の推論と空のファイル変更があっても最後のコマンドを要約する")
    func recapKeepsLatestActivityAcrossNonActivityItems() {
        let items: [ChatItem] = [
            .userMessage(id: "u", text: "確認して", timestamp: t0),
            .commandExecution(id: "c", command: "cat Source.swift", output: "内容", timestamp: t0),
            .reasoning(id: "r", text: "## 次の修正を検討", timestamp: t0),
            .fileChange(id: "empty-change", changes: [], timestamp: t0),
            .agentMessage(id: "answer", text: "確認しています", timestamp: t0),
        ]

        let summary = ChatRecap.summary(transcript: items, elapsed: 10)

        #expect(summary == .activity(.reading("cat Source.swift")))
    }

    @Test("最新の推論が空なら古い推論の見出しへ戻らない")
    func emptyLatestReasoningDoesNotReuseOldHeadline() {
        let items: [ChatItem] = [
            .userMessage(id: "u", text: "調べて", timestamp: t0),
            .reasoning(id: "old", text: "## 古い検討", timestamp: t0),
            .reasoning(id: "new", text: "", timestamp: t0),
        ]

        let summary = ChatRecap.summary(transcript: items, elapsed: 10)

        #expect(summary == nil)
    }

    @Test("ユーザー入力が無い履歴では最新の推論見出しを要約する")
    func recapWithoutUserUsesLatestReasoning() {
        let items: [ChatItem] = [
            .reasoning(id: "old", text: "## 調査を開始", timestamp: t0),
            .reasoning(id: "new", text: "## テストを検討", timestamp: t0),
            .error(id: "error", message: "一時的な接続エラー", timestamp: t0),
        ]

        let summary = ChatRecap.summary(transcript: items, elapsed: 10)

        #expect(summary == .headline("テストを検討"))
    }

    @Test("新しいユーザー入力より前の活動や推論を要約しない")
    func recapStopsAtLatestUserMessage() {
        let items: [ChatItem] = [
            .commandExecution(id: "old-command", command: "swift build", output: "成功", timestamp: t0),
            .reasoning(id: "old-reasoning", text: "## ビルド完了", timestamp: t0),
            .userMessage(id: "new-user", text: "次の確認をして", timestamp: t0),
            .fileChange(id: "empty-change", changes: [], timestamp: t0),
        ]

        let summary = ChatRecap.summary(transcript: items, elapsed: 10)

        #expect(summary == nil)
    }

    @Test("未指定コマンドも新しい活動として直前のファイル変更より優先する")
    func nilCommandOverridesPreviousFileActivity() {
        let items: [ChatItem] = [
            .fileChange(id: "file", changes: [FilePatchChange(path: "Sources/Previous.swift", diff: "+変更")], timestamp: t0),
            .commandExecution(id: "command", command: nil, output: "実行中", timestamp: t0),
        ]

        let summary = ChatRecap.summary(transcript: items, elapsed: 5)

        #expect(summary == .activity(.running("コマンド")))
    }

    @Test("「↓ 最新へ」は読み戻しで追従を外したときだけ（スクロール中・最下部では出さない）")
    func detachedOnlyAfterScrollingAway() {
        let controller = ChatAutoFollowController()
        #expect(!controller.isDetached)
        controller.userScrollBegan()
        #expect(!controller.isDetached)
        controller.userScrollEnded(isAtBottom: false)
        #expect(controller.isDetached)
        controller.scrollPositionChanged(isAtBottom: true)
        #expect(!controller.isDetached)
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: true)
        #expect(!controller.isDetached)
    }
}

@Test func commandExitCode_parsesClaudeBashFailureHeader() {
    #expect(CommandExitCode.parse("Exit code 127\nzsh: command not found: foo") == 127)
    #expect(CommandExitCode.parse("Exit code 0") == 0)
    #expect(CommandExitCode.parse("ok\nall good") == nil)
    #expect(CommandExitCode.parse("") == nil)
}

@Test func turnCostFormat_hasNoSpaceAndTwoDigits() {
    #expect(TurnCostCell.format(0.4213) == "$0.42")
    #expect(TurnCostCell.format(0.0012) == "$0.0012")
    #expect(TurnCostCell.format(0) == "$0.00")
}

/// Claude の Write / Edit の差分は hunk 見出しが無く末尾が改行で終わる。末尾の空行は差分の行として出さない。
@Test @MainActor func diffCodeView_dropsTrailingEmptyLineAndHasNoNumbersWithoutHunk() {
    let view = DiffCodeViewData(diff: "+import Foundation\n+\n+struct Demo {}\n", path: "A.swift")
    #expect(view.lines.count == 3)
    #expect(view.hasLineNumbers == false)
}

/// 保存済みのサブエージェント記録も、ライブと同じ 1 行（「Read /path」）にし、<system-reminder> は発言として出さない。
@Test func subAgentTranscript_formatsToolLikeLiveAndHidesSystemReminder() {
    let jsonl = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"見出しを列挙"},{"type":"text","text":"<system-reminder>\\ninternal\\n</system-reminder>"}]}}
    {"type":"user","message":{"role":"user","content":"<system-reminder>\\nreport via handback\\n</system-reminder>"}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Read","input":{"file_path":"/r/README.md"}}]}}
    """
    let items = SubAgentTranscriptLoader.parse(jsonl: jsonl)
    let texts = items.compactMap { item -> String? in
        if case .userMessage(_, let text, _, _) = item { return text }
        return nil
    }
    #expect(texts == ["見出しを列挙"])
    #expect(items.contains {
        if case .commandExecution(_, let command, _, _) = $0 { return command == "Read /r/README.md" }
        return false
    })
}
