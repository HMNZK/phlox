import AgentDomain
import DesignSystem
import Foundation
import Testing
@testable import SessionFeature

// 11 通知: 種類ごとの見出しと本文。「待ち」は承認待ち・質問待ちにだけ使い、完了は「作業が完了しました」。

@Suite("Notification redesign (11)")
struct NotificationRedesignTests {
    private let ja = Locale(identifier: "ja")

    @Test func titles_nameTheSession_andUseWaitOnlyForApprovalAndQuestion() {
        #expect(SessionNotificationText.title(.completed, sessionName: "準備", locale: ja) == "作業が完了しました: 準備")
        #expect(SessionNotificationText.title(.awaitingApproval(prompt: nil), sessionName: "準備", locale: ja) == "承認待ち: 準備")
        #expect(SessionNotificationText.title(.awaitingQuestion(question: nil, isSecret: false), sessionName: "準備", locale: ja) == "質問があります: 準備")
        #expect(SessionNotificationText.title(.error(message: "x"), sessionName: "準備", locale: ja) == "エラーで止まりました: 準備")
        #expect(!SessionNotificationText.title(.completed, sessionName: "準備", locale: ja).contains("待ち"))
    }

    @Test func bodies_showTheApprovalTarget_andTheFirstErrorLine() {
        #expect(SessionNotificationText.body(.awaitingApproval(prompt: "swift test"), locale: ja) == "swift test")
        #expect(SessionNotificationText.body(.awaitingApproval(prompt: nil), locale: ja) == "")
        #expect(SessionNotificationText.body(.error(message: "error: linker failed\nsecond line"), locale: ja) == "error: linker failed")
        #expect(SessionNotificationText.body(.completed, locale: ja) == "次の指示を待っています。")
        #expect(SessionNotificationText.body(.awaitingQuestion(question: "移しますか?", isSecret: false), locale: ja) == "移しますか?")
        #expect(SessionNotificationText.body(.awaitingQuestion(question: "API キー", isSecret: true), locale: ja) == "入力を求めています")
    }

    @Test func testNotification_hasItsOwnText() {
        #expect(SessionNotificationText.title(.test, sessionName: "", locale: ja) == "Phlox の通知テスト")
        #expect(SessionNotificationText.subtitle(.test, locale: ja) == "設定 > 通知")
        #expect(SessionNotificationText.body(.test, locale: ja) == "このように通知されます。")
        #expect(SessionNotificationText.subtitle(.completed, locale: ja) == "")
    }

    @Test func stalled_namesTheLastAction_whenKnown() {
        #expect(SessionNotificationText.title(.stalled(lastAction: nil), sessionName: "準備", locale: ja) == "応答がありません: 準備")
        #expect(SessionNotificationText.body(.stalled(lastAction: "swift test を実行中"), locale: ja) == "2 分以上反応がありません。最後の動作: swift test を実行中")
        #expect(SessionNotificationText.body(.stalled(lastAction: nil), locale: ja) == "2 分以上反応がありません。")
    }

    @Test func subtitle_isProjectAndAgent_skippingUnknownParts() {
        #expect(SessionNotificationText.subtitle(projectName: "phlox", agentName: "Claude Code") == "phlox · Claude Code")
        #expect(SessionNotificationText.subtitle(projectName: nil, agentName: "Codex") == "Codex")
        #expect(SessionNotificationText.subtitle(projectName: nil, agentName: nil) == "")
    }

    @Test func completedBody_isTheFirstLineOfTheLastReply_orTheFallback() {
        #expect(SessionNotificationText.completedBody(lastReply: "テストを直しました。\n詳細は…", locale: ja) == "テストを直しました。")
        #expect(SessionNotificationText.completedBody(lastReply: "  \n", locale: ja) == "次の指示を待っています。")
        #expect(SessionNotificationText.completedBody(lastReply: nil, locale: ja) == "次の指示を待っています。")
    }

    @Test func summary_countsByKind_inListOrder() {
        #expect(SessionNotificationText.summaryTitle(projectName: "phlox", count: 3, locale: ja) == "phlox で 3 件が対応待ち")
        #expect(SessionNotificationText.summarySubtitle(kinds: [.question, .approval, .approval], locale: ja) == "承認待ち 2 · 質問待ち 1")
        #expect(SessionNotificationText.summaryBody(newestName: "準備", count: 3, locale: ja) == "準備 ほか 2 件")
    }

    @Test func attentionBook_summarizesFromTheThirdInAProject_andStaysSummarizedUntilCleared() {
        var book = AttentionNotificationBook()
        func item(_ id: String, _ kind: AttentionKind = .question) -> AttentionNotificationBook.Item {
            .init(sessionID: id, kind: kind, name: id)
        }
        #expect(book.record(item("a"), projectID: "p") == .single)
        #expect(book.record(item("x"), projectID: "q") == .single)
        #expect(book.record(item("b", .approval), projectID: "p") == .single)
        // 同じセッションの再通知は数え直さない。
        #expect(book.record(item("b", .approval), projectID: "p") == .single)
        #expect(book.record(item("c"), projectID: "p") == .summary(items: [item("c"), item("b", .approval), item("a")]))

        // 一部が済んでも、まとめたプロジェクトは 1 枚のまま書き換える。
        book.prune(keeping: ["c", "x"])
        #expect(book.record(item("d"), projectID: "p") == .summary(items: [item("d"), item("c")]))

        // 対応待ちが無くなったら、まとめの 1 枚を消す先として返し、次は個別から数え直す。
        #expect(book.prune(keeping: ["x"]) == ["p"])
        #expect(book.record(item("e"), projectID: "p") == .single)
    }
}
