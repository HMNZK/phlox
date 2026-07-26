import Foundation
import Testing
@testable import SessionFeature

// task-3 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-3.md
// 目的（A-2）: デスクトップでチャット表示のセッションを開く／切り替えたとき、最下部（最新）から
//   表示する。ChatTranscriptView は view identity を保ったまま viewModel だけ差し替わるため、
//   前のセッションで「上へ読み戻した（detached）」状態が次のセッションへ持ち越される。
@MainActor
struct AcceptanceChatOpenAtBottomTests {

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

    @Test("View が開いた時と切替時に最下部へ寄せると宣言し、追従状態を初期化している")
    func viewOpensAtBottomAndResetsFollowState() throws {
        let source = try ChatOpenAtBottomSource.text("ChatTranscriptView.swift")

        #expect(
            ChatTranscriptView.providesOpenAtBottom,
            "実装と同時にフラグを反転すること（フラグだけの反転は虚偽報告として扱う）"
        )
        #expect(
            source.contains("autoFollow.sessionDidChange()"),
            "セッション切替（viewModel.id の変化）で追従状態を初期化すること"
        )
    }
}

/// テストファイル位置を起点に SessionFeature のソースを読む。
enum ChatOpenAtBottomSource {
    static func text(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SessionFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SessionFeature
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SessionFeature/\(relativePath)"),
            encoding: .utf8
        )
    }
}
