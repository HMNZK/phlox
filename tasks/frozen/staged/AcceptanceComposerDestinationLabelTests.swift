import Foundation
import Testing
@testable import SessionFeature

// task-43 受け入れテスト（PM 著・不変）。ComposerDestinationLabel 未実装のコンパイル RED が正常。
// 期待値は tasks/task-43.md のリテラル。製品の文字列や分岐から生成しない。
//
// 契約の正本: tasks/task-43.md
//   純粋モデル：表示文言 / 成功基準 1（SessionFeature）/ View 配線（単一・グリッドは同一モデル）

private struct SendabilityCase: Sendable {
    let hasDestination: Bool
    let isReadyForInput: Bool
    let hasContent: Bool
    let expected: String
}

@Suite("Acceptance: ComposerDestinationLabel 文言（task-43）")
struct AcceptanceComposerDestinationLabelTests {

    // MARK: - 成功基準 1.1 / 1.2

    @Test("Phlox / 入力欄改善 が完全一致する")
    func conversationPhloxExactMatch() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("別の宛先 Garden / 調査 へ変えると前の名前を残さない")
    func conversationDoesNotKeepPreviousName() {
        let previous = ComposerDestinationLabel.text(
            for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(previous == "Phlox / 入力欄改善")
        let next = ComposerDestinationLabel.text(
            for: .conversation(projectName: "Garden", taskName: "調査"),
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(next == "Garden / 調査")
        #expect(!next.contains("Phlox"))
        #expect(!next.contains("入力欄改善"))
    }

    // MARK: - 成功基準 1.3 / 1.4

    @Test("プロジェクト名の nil・空・空白・改行のみを プロジェクト名不明 にする")
    func projectNameMissingBecomesUnknown() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: nil, taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "プロジェクト名不明 / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "プロジェクト名不明 / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "   ", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "プロジェクト名不明 / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: " \n\t ", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "プロジェクト名不明 / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: " \nPhlox\t ", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("作業名の空白のみを 作業名不明 にし、日本語・英語・内部空白は保持する")
    func taskNameWhitespaceUnknownKeepsRealNames() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "   "),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 作業名不明"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: ""),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 作業名不明"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "\n\t"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 作業名不明"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: " 調査 "),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 調査"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "Composer destination"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / Composer destination"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力 欄 改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力 欄 改善"
        )
    }

    // MARK: - 成功基準 1.5 基本文言

    @Test("4種類の Destination の基本文言を固定する")
    func fourDestinationBaseLiterals() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .startDiscussion,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .discussionUtterance,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論への発言"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: "Phlox", taskName: "全体作業"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("親セッションで作業名がない場合は 親セッションへの送信 だけ")
    func parentSessionWithoutTaskName() {
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: "Phlox", taskName: nil),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "親セッションへの送信"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: "Phlox", taskName: ""),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "親セッションへの送信"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: "Phlox", taskName: "  \n "),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "親セッションへの送信"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: nil, taskName: "全体作業"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "プロジェクト名不明 / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("討論開始・発言に選択カードの作業名を付けない")
    func discussionLabelsDoNotIncludeCardNames() {
        let start = ComposerDestinationLabel.text(
            for: .startDiscussion,
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(start == "討論を開始")
        #expect(!start.contains("入力欄改善"))
        #expect(!start.contains("Garden"))
        let utterance = ComposerDestinationLabel.text(
            for: .discussionUtterance,
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(utterance == "討論への発言")
        #expect(!utterance.contains("子の調査"))
        #expect(!utterance.contains("全体作業"))
    }

    // MARK: - 成功基準 1.6 送信不可理由（各 Destination × 3 Bool の 8 組）

    @Test("conversation の送信不可理由 8 組と優先順位")
    func conversationSendabilityEightCases() {
        let cases: [SendabilityCase] = [
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: true, expected: "Phlox / 入力欄改善"),
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: false, expected: "Phlox / 入力欄改善 — 送信不可（メッセージを入力してください）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: true, expected: "Phlox / 入力欄改善 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: false, expected: "Phlox / 入力欄改善 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: true, expected: "Phlox / 入力欄改善 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: false, expected: "Phlox / 入力欄改善 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: true, expected: "Phlox / 入力欄改善 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: false, expected: "Phlox / 入力欄改善 — 送信不可（送信先がありません）"),
        ]
        #expect(cases.count == 8)
        for item in cases {
            #expect(
                ComposerDestinationLabel.text(
                    for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                    hasDestination: item.hasDestination,
                    isReadyForInput: item.isReadyForInput,
                    hasContent: item.hasContent
                ) == item.expected
            )
        }
    }

    @Test("startDiscussion の送信不可理由 8 組と優先順位")
    func startDiscussionSendabilityEightCases() {
        let cases: [SendabilityCase] = [
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: true, expected: "討論を開始"),
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: false, expected: "討論を開始 — 送信不可（メッセージを入力してください）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: true, expected: "討論を開始 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: false, expected: "討論を開始 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: true, expected: "討論を開始 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: false, expected: "討論を開始 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: true, expected: "討論を開始 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: false, expected: "討論を開始 — 送信不可（送信先がありません）"),
        ]
        #expect(cases.count == 8)
        for item in cases {
            #expect(
                ComposerDestinationLabel.text(
                    for: .startDiscussion,
                    hasDestination: item.hasDestination,
                    isReadyForInput: item.isReadyForInput,
                    hasContent: item.hasContent
                ) == item.expected
            )
        }
    }

    @Test("discussionUtterance の送信不可理由 8 組と優先順位")
    func discussionUtteranceSendabilityEightCases() {
        let cases: [SendabilityCase] = [
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: true, expected: "討論への発言"),
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: false, expected: "討論への発言 — 送信不可（メッセージを入力してください）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: true, expected: "討論への発言 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: false, expected: "討論への発言 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: true, expected: "討論への発言 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: false, expected: "討論への発言 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: true, expected: "討論への発言 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: false, expected: "討論への発言 — 送信不可（送信先がありません）"),
        ]
        #expect(cases.count == 8)
        for item in cases {
            #expect(
                ComposerDestinationLabel.text(
                    for: .discussionUtterance,
                    hasDestination: item.hasDestination,
                    isReadyForInput: item.isReadyForInput,
                    hasContent: item.hasContent
                ) == item.expected
            )
        }
    }

    @Test("parentSession（作業名あり）の送信不可理由 8 組と優先順位")
    func parentSessionNamedSendabilityEightCases() {
        let cases: [SendabilityCase] = [
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: true, expected: "Phlox / 全体作業 — 親セッションへの送信"),
            SendabilityCase(hasDestination: true, isReadyForInput: true, hasContent: false, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（メッセージを入力してください）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: true, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: true, isReadyForInput: false, hasContent: false, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（入力を受け付けられません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: true, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: true, hasContent: false, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: true, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（送信先がありません）"),
            SendabilityCase(hasDestination: false, isReadyForInput: false, hasContent: false, expected: "Phlox / 全体作業 — 親セッションへの送信 — 送信不可（送信先がありません）"),
        ]
        #expect(cases.count == 8)
        for item in cases {
            #expect(
                ComposerDestinationLabel.text(
                    for: .parentSession(projectName: "Phlox", taskName: "全体作業"),
                    hasDestination: item.hasDestination,
                    isReadyForInput: item.isReadyForInput,
                    hasContent: item.hasContent
                ) == item.expected
            )
        }
    }

    // MARK: - 成功基準 1.7 / 1.8

    @Test("本文が空でも hasContent true（添付あり）では本文未入力の理由が付かない")
    func attachmentOnlyDoesNotAddEmptyContentReason() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .startDiscussion,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .discussionUtterance,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論への発言"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: "Phlox", taskName: "全体作業"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("starting 相当: isReadyForInput false は入力不可理由を付ける")
    func startingReadinessAddsNotReadyReason() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: false,
                hasContent: true
            ) == "Phlox / 入力欄改善 — 送信不可（入力を受け付けられません）"
        )
    }

    @Test("running / awaitingApproval / awaitingUserQuestion / completed 相当: isReadyForInput true では入力不可理由を付けない")
    func otherStatusesDoNotAddNotReadyReason() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("error（復元失敗）相当: isReadyForInput true は復元を独自の送信禁止にしない")
    func restoreErrorIsNotAUniqueSendBlock() {
        let text = ComposerDestinationLabel.text(
            for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(text == "Phlox / 入力欄改善")
        #expect(!text.contains("送信不可"))
        #expect(!text.contains("復元"))
    }

    // MARK: - 単一・グリッド・チーム × 開始前 / 進行中 / 終了後 / 開始不可

    @Test("単一・開始前: conversation は 討論状態に影響されない")
    func singleBeforeStartConversationLiteral() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("単一・進行中: conversation は 討論への発言 にならない")
    func singleInProgressStillConversation() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("単一・終了後: conversation は 親セッションへの送信 にならない")
    func singleAfterEndStillConversation() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("単一・開始不可: conversation は送信不可理由を自動で付けない")
    func singleCannotStartStillConversation() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("グリッド・開始前: タイル自身の Garden / 調査")
    func gridBeforeStartConversationLiteral() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Garden", taskName: "調査"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Garden / 調査"
        )
    }

    @Test("グリッド・進行中: 選択カード名に差し替えない")
    func gridInProgressKeepsTileDestination() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Garden", taskName: "調査"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Garden / 調査"
        )
    }

    @Test("グリッド・終了後: タイル自身の送信先を維持")
    func gridAfterEndKeepsTileDestination() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Garden", taskName: "調査"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Garden / 調査"
        )
    }

    @Test("グリッド・開始不可: タイル自身の送信先を維持")
    func gridCannotStartKeepsTileDestination() {
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Garden", taskName: "調査"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Garden / 調査"
        )
    }

    @Test("チーム・開始前: 討論を開始")
    func teamBeforeStartLiteral() {
        #expect(
            ComposerDestinationLabel.text(
                for: .startDiscussion,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始"
        )
    }

    @Test("チーム・進行中: 討論への発言")
    func teamInProgressLiteral() {
        #expect(
            ComposerDestinationLabel.text(
                for: .discussionUtterance,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論への発言"
        )
    }

    @Test("チーム・終了後かつ開始可能: 討論を開始（親送信に固定しない）")
    func teamAfterEndCanStartLiteral() {
        #expect(
            ComposerDestinationLabel.text(
                for: .startDiscussion,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始"
        )
    }

    @Test("チーム・開始不可: 親セッションへの送信（送信不可理由は自動で付けない）")
    func teamCannotStartParentLiteral() {
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: nil, taskName: nil),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "親セッションへの送信"
        )
    }

    @Test("選択カードと送信先が異なる: 親送信は根の Phlox / 全体作業")
    func selectedCardDiffersFromSendTarget() {
        #expect(
            ComposerDestinationLabel.text(
                for: .parentSession(projectName: "Phlox", taskName: "全体作業"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
        let childCard = ComposerDestinationLabel.text(
            for: .conversation(projectName: "Garden", taskName: "子の調査"),
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(childCard == "Garden / 子の調査")
        let parent = ComposerDestinationLabel.text(
            for: .parentSession(projectName: "Phlox", taskName: "全体作業"),
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(!parent.contains("Garden"))
        #expect(!parent.contains("子の調査"))
    }
}
