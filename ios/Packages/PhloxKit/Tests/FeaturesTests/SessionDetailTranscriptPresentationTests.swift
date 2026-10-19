import Testing
import PhloxCore
@testable import Features

@Suite("会話表示の値")
struct SessionDetailTranscriptPresentationTests {
    @Test("添付時だけ本文内の画像識別子をサムネイルへ置き換える")
    func hidesImagePlaceholdersWhenPreviewsExist() {
        #expect(
            SessionDetailTranscriptPresentation.userText("確認 [Image #1] と [Image #2]", hasAttachments: true)
                == "確認 と"
        )
        #expect(
            SessionDetailTranscriptPresentation.userText("[Image #1] は文字", hasAttachments: false)
                == "[Image #1] は文字"
        )
    }

    @Test("転写には回答済み・期限切れの質問と各ターン行を残す")
    func separatesTranscriptQuestionsAndTurnRows() {
        let question = UserQuestionItem(question: "どれ？", header: "選択", options: [], multiSelect: false)
        let messages: [ChatMessage] = [
            .user(id: "user", text: "選んで"),
            .userQuestion(id: "pending", requestId: "p", questions: [question], answers: nil, state: .pending),
            .userQuestion(id: "answered", requestId: "a", questions: [question], answers: ["どれ？": ["A"]], state: .answered),
            .userQuestion(id: "expired", requestId: "e", questions: [question], answers: nil, state: .expired),
            .agent(id: "agent", text: "完了"),
            .turnCost(id: "cost", costUSD: 0.42),
        ]

        let transcript = SessionDetailTranscriptPresentation.messagesForTranscript(messages)
        #expect(transcript.map(\.id) == ["user", "answered", "expired", "agent", "cost"])
        #expect(SessionDetailTranscriptPresentation.visibleTranscriptRows(transcript).map(\.id) == [
            "user", "answered", "expired", "agent", "cost",
        ])
    }

    @Test("各ターンの金額行を会話の位置に残し、コンテキストは最後の金額行へ付ける")
    func turnCostRowsRemainAtTheirTranscriptPositions() {
        let earlierTurn: [ChatMessage] = [
            .user(id: "u1", text: "前の指示"),
            .agent(id: "a1", text: "前の返答"),
            .turnCost(id: "c1", costUSD: 0.12),
            .user(id: "u2", text: "今の指示"),
            .agent(id: "a2", text: "今の返答"),
            .turnCost(id: "c2", costUSD: 0.42),
        ]
        let pendingTurn: [ChatMessage] = [
            .user(id: "u3", text: "次の指示"),
            .turnCost(id: "c3", costUSD: 0.50),
        ]

        let earlierRows = SessionDetailTranscriptPresentation.visibleTranscriptRows(
            SessionDetailTranscriptPresentation.messagesForTranscript(earlierTurn)
        )
        let pendingRows = SessionDetailTranscriptPresentation.visibleTranscriptRows(
            SessionDetailTranscriptPresentation.messagesForTranscript(pendingTurn)
        )

        #expect(earlierRows.map(\.id) == ["u1", "a1", "c1", "u2", "a2", "c2"])
        #expect(SessionDetailTranscriptPresentation.latestTurnCostID(in: earlierRows) == "c2")
        #expect(pendingRows.map(\.id) == ["u3", "c3"])
        #expect(SessionDetailTranscriptPresentation.latestTurnCostID(in: pendingRows) == "c3")
    }

    @Test("回答済み質問は選択肢の説明・自由入力を分け、期限切れは送信なしとする")
    func presentsSettledQuestionDetailsWithoutView() {
        let question = UserQuestionItem(
            question: "進め方は？", header: "SCOPE",
            options: [UserQuestionOption(label: "v2", description: "新契約")],
            multiSelect: false
        )
        let answered = SessionDetailTranscriptPresentation.settledQuestion(
            state: .answered
        )
        let expired = SessionDetailTranscriptPresentation.settledQuestion(
            state: .expired
        )

        #expect(answered == .init(statusLabel: "回答済み", isAnswered: true))
        #expect(expired == .init(statusLabel: "期限切れ", isAnswered: false))
        #expect(SessionDetailTranscriptPresentation.settledQuestion(state: .pending) == nil)
        #expect(SessionDetailTranscriptPresentation.settledQuestionDetails(
            for: question,
            state: .answered,
            answers: ["進め方は？": ["v2", "補足"]]
        ) == [.option(label: "v2", description: "新契約"), .input("補足")])
        #expect(SessionDetailTranscriptPresentation.settledQuestionDetails(
            for: question,
            state: .expired,
            answers: nil
        ) == [.expired])
    }

    @Test("コマンド出力は20行で切り、残り行数を保持する")
    func commandOutputIsLimitedToTwentyLines() {
        let output = (1...23).map(String.init).joined(separator: "\n")
        let collapsed = SessionDetailTranscriptPresentation.commandOutput(output, expanded: false)
        let expanded = SessionDetailTranscriptPresentation.commandOutput(output, expanded: true)

        #expect(collapsed.displayed.split(separator: "\n").count == 20)
        #expect(collapsed.displayed.hasSuffix("20"))
        #expect(collapsed.hiddenLineCount == 3)
        #expect(expanded.displayed == output)
        #expect(expanded.hiddenLineCount == 0)
    }

    @Test("終了コードは先頭3つの非空行から読む")
    func parsesExitCodeLikeMac() {
        #expect(SessionDetailTranscriptPresentation.exitCode(in: "\nExit code 0\nresult") == 0)
        #expect(SessionDetailTranscriptPresentation.exitCode(in: "one\ntwo\nExit code 2\n") == 2)
        #expect(SessionDetailTranscriptPresentation.exitCode(in: "one\ntwo\nthree\nExit code 4") == nil)
    }

    @Test("サブエージェントは実行状態とタスクを分ける")
    func parsesSubAgentRow() {
        #expect(
            SessionDetailTranscriptPresentation.subAgent(from: "Sub-agent explore-map running: コードベース調査")
                == .init(taskName: "コードベース調査", status: .running)
        )
        #expect(
            SessionDetailTranscriptPresentation.subAgent(from: "Sub-agent explore-map completed: テスト確認")
                == .init(taskName: "テスト確認", status: .completed)
        )
        #expect(
            SessionDetailTranscriptPresentation.subAgent(from: "Sub-agent explore-map working: 調査")
                == .init(taskName: "調査", status: .unknown)
        )
    }

    @Test("ターン行は Mac の金額書式を使い、届かない値を省く")
    func formatsTurnUsage() {
        let usage = TurnUsage(costUSD: nil, contextUsedTokens: 44, contextWindowTokens: 200)
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: 0.42, usage: usage) == "$0.42 · コンテキスト 22%")
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: 0.0012, usage: nil) == "$0.0012")
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: nil, usage: TurnUsage(costUSD: nil, contextUsedTokens: nil, contextWindowTokens: nil)) == nil)
    }

    @Test("拡大文字の使用量は金額と割合を別行へ送り、通常の値と優先を変えない")
    func stacksTurnUsageWithoutDroppingValues() {
        let usage = TurnUsage(costUSD: 0.5, contextUsedTokens: 44, contextWindowTokens: 200)
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: 0.42, usage: usage, isAccessibilitySize: true)
            == "$0.42\nコンテキスト 22%")
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: nil, usage: usage, isAccessibilitySize: true)
            == "$0.50\nコンテキスト 22%")
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: nil, usage: TurnUsage(costUSD: nil, contextUsedTokens: 44, contextWindowTokens: 200), isAccessibilitySize: true)
            == "コンテキスト 22%")
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: 0.0012, usage: nil, isAccessibilitySize: true) == "$0.0012")
        #expect(SessionDetailTranscriptPresentation.turnUsageLine(costUSD: nil, usage: nil, isAccessibilitySize: true) == nil)
    }
}
