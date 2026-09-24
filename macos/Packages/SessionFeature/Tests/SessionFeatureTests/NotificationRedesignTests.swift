import AgentDomain
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
}
