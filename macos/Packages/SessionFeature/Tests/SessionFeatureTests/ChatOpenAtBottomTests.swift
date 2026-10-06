import Foundation
import Testing
@testable import SessionFeature

// デスクトップでチャット表示のセッションを開く／切り替えたとき、最下部（最新）から表示する。
// ChatTranscriptView は view identity を保ったまま viewModel だけ差し替わるため、
// 前のセッションで「上へ読み戻した（detached）」状態が次のセッションへ持ち越される。
@Suite("Chat open at bottom")
@MainActor
struct ChatOpenAtBottomTests {

    @Test("初期状態は追従（＝最下部から表示する）")
    func startsFollowing() {
        let controller = ChatAutoFollowController()

        #expect(controller.isFollowing == true)
    }

    @Test("上へ読み戻して離れていても、セッションを切り替えたら追従に戻る")
    func sessionSwitchRestoresFollowingAfterUserScroll() {
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: false)
        #expect(controller.isFollowing == false, "前提: 上へ離れて追従が外れている")

        controller.sessionDidChange()

        #expect(
            controller.isFollowing == true,
            "別セッションを開いたら追従状態を初期化し、最下部から表示すること"
        )
        #expect(
            controller.contentDidChange() == true,
            "切替後に届いた本文で最下部へ寄せること"
        )
    }

    @Test("「以前のメッセージを表示」で離れた状態も、セッション切替で追従に戻る")
    func sessionSwitchRestoresFollowingAfterJump() {
        let controller = ChatAutoFollowController()
        controller.userInitiatedJump()
        #expect(controller.isFollowing == false, "前提: ジャンプで追従が外れている")

        controller.sessionDidChange()

        #expect(controller.isFollowing == true)
    }

    @Test("同じセッションを読み戻している間は追従を再開しない")
    func staysDetachedWithoutSessionChange() {
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: false)

        #expect(
            controller.contentDidChange() == false,
            "上へ読み戻し中の新着で引き戻さないこと（既存の追従方針を壊さない）"
        )
    }

    @Test("本文更新は追従中だけ最下部へ寄せる")
    func contentUpdatesScrollOnlyWhileFollowing() {
        #expect(ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .transcript, isFollowing: true))
        #expect(ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .status, isFollowing: true))
        #expect(!ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .transcript, isFollowing: false))
        #expect(!ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .status, isFollowing: false))
        // .appear の真理値表が無検査だと「開いたら最下部」が 1 行の改変で無検査に壊れる。
        #expect(ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .appear, isFollowing: true))
        #expect(!ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .appear, isFollowing: false))
    }

    @Test("遅延した最下部スクロールは追従中かつ最新世代だけ実行する")
    func deferredBottomScrollRequiresFollowingAndCurrentGeneration() {
        #expect(
            ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                generation: 3,
                currentGeneration: 3,
                isFollowing: true
            )
        )
        #expect(
            !ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                generation: 3,
                currentGeneration: 3,
                isFollowing: false
            )
        )
        #expect(
            !ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                generation: 2,
                currentGeneration: 3,
                isFollowing: true
            )
        )
    }
}
