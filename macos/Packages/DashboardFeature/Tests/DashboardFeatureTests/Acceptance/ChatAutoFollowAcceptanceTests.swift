import Testing
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（チャット自動スクロール追従）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 契約: 追従判定の状態機械 `ChatAutoFollowController`（internal・専用ファイルへ切り出し）。
/// 状態は following（自動追従中）/ userScrolling（ユーザー操作中）/ detached（手動離脱中）の3値。
/// - `userScrollBegan()` — ユーザーのスクロール操作開始（NSScrollView willStartLiveScroll 由来）
/// - `userScrollEnded(isAtBottom:)` — 操作終了。最下部なら追従再開、離れていれば離脱
/// - `scrollPositionChanged(isAtBottom:)` — スクロール位置変化（boundsDidChange 由来）。
///   **detached 中に最下部へ達したときだけ**追従を再開する（慣性スクロール対応）。
///   following 中・userScrolling 中は状態を変えない（プログラム起因 scrollTo の誤検知防止）。
/// - `contentDidChange() -> Bool` — トランスクリプト更新の通知。**状態を一切変えず**、
///   following 中のみ true（呼び出し側が scrollTo を発行）。
/// - `isFollowing` — following かどうか。
///
/// 核心契約: **コンテンツ増加だけでは追従は絶対に解除されない**（従来の bottomOffset
/// ヒューリスティクスがストリーミング伸長を手動離脱と誤認していた欠陥の是正）。
/// 離脱はユーザーのスクロール操作（userScrollBegan）のみが引き起こす。
/// View 配線・NSScrollView 通知購読・CPU 非固着は swift test では判定できないため、
/// レビュー Rubric と実機 runtime 検証が担う。ここでは状態機械の契約を凍結する。
@MainActor
@Suite("task-1 chat auto-follow acceptance")
struct ChatAutoFollowAcceptanceTests {

    @Test
    func initialStateFollows() {
        // 初期状態は追従 ON。表示直後から最新出力へ追従する。
        let controller = ChatAutoFollowController()
        #expect(controller.isFollowing)
        #expect(controller.contentDidChange())
    }

    @Test
    func contentGrowthNeverDetaches() {
        // ストリーミングでコンテンツが何回伸びても、ユーザー操作なしでは絶対に離脱しない。
        let controller = ChatAutoFollowController()
        for _ in 0..<500 {
            #expect(controller.contentDidChange())
        }
        #expect(controller.isFollowing)
    }

    @Test
    func positionChangeWhileFollowingDoesNotDetach() {
        // following 中の位置変化（コンテンツ伸長・プログラム起因 scrollTo・一時的な
        // 「最下部でない」報告）では離脱しない。離脱はユーザー操作のみ。
        let controller = ChatAutoFollowController()
        controller.scrollPositionChanged(isAtBottom: false)
        #expect(controller.isFollowing)
        #expect(controller.contentDidChange())
    }

    @Test
    func userScrollSuspendsFollowImmediately() {
        // ユーザーがスクロール操作を始めたら、操作中は追従（scrollTo 発行）をしない。
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        #expect(!controller.isFollowing)
        #expect(!controller.contentDidChange())
    }

    @Test
    func gestureEndAwayFromBottomStaysDetached() {
        // 最下部から離れた位置で操作を終えたら離脱を維持し、以後の更新でも追従しない。
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: false)
        #expect(!controller.isFollowing)
        #expect(!controller.contentDidChange())
    }

    @Test
    func gestureEndAtBottomResumesFollow() {
        // 最下部（しきい値内）で操作を終えたら追従を再開する。
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: true)
        #expect(controller.isFollowing)
        #expect(controller.contentDidChange())
    }

    @Test
    func momentumCoastToBottomResumesFollow() {
        // 慣性スクロール: 操作終了時点では最下部でなくても、その後の位置変化で
        // 最下部へ達したら追従を再開する（didEndLiveScroll が慣性完了前に発火する対策）。
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: false)
        controller.scrollPositionChanged(isAtBottom: false)
        #expect(!controller.isFollowing)
        controller.scrollPositionChanged(isAtBottom: true)
        #expect(controller.isFollowing)
        #expect(controller.contentDidChange())
    }

    @Test
    func midGesturePositionChangeDoesNotResume() {
        // 操作の途中で最下部を通過しても再開しない（指を離した時点の位置で判定する）。
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.scrollPositionChanged(isAtBottom: true)
        #expect(!controller.isFollowing)
        controller.userScrollEnded(isAtBottom: false)
        #expect(!controller.isFollowing)
    }

    @Test
    func detachResumeCycleIsRepeatable() {
        // 離脱→復帰のサイクルを繰り返しても状態機械が壊れない。
        let controller = ChatAutoFollowController()
        for _ in 0..<3 {
            controller.userScrollBegan()
            #expect(!controller.contentDidChange())
            controller.userScrollEnded(isAtBottom: false)
            #expect(!controller.contentDidChange())
            controller.scrollPositionChanged(isAtBottom: true)
            #expect(controller.isFollowing)
            #expect(controller.contentDidChange())
        }
    }

    @Test
    func jumpNavigationDetachesFollow() {
        // ユーザーが特定メッセージへのジャンプ（requestedScrollTarget 経由の
        // プログラムスクロール）を要求したら、それはユーザー意図の離脱として扱う。
        // following のまま残すと、次のストリーミング更新でジャンプ先から最下部へ
        // 引き戻されてしまう（fix round で追加された契約）。
        let controller = ChatAutoFollowController()
        controller.userInitiatedJump()
        #expect(!controller.isFollowing)
        #expect(!controller.contentDidChange())
        // ジャンプ先が最下部近傍なら、着地後の位置変化で自然に追従再開する。
        controller.scrollPositionChanged(isAtBottom: true)
        #expect(controller.isFollowing)
    }

    @Test
    func jumpAwayStaysDetachedUntilBottomReturn() {
        // 最下部から離れた位置へのジャンプ後は、ストリーミングが進んでも留まり、
        // 最下部へ戻ったときだけ追従を再開する。
        let controller = ChatAutoFollowController()
        controller.userInitiatedJump()
        controller.scrollPositionChanged(isAtBottom: false)
        for _ in 0..<50 {
            #expect(!controller.contentDidChange())
        }
        controller.scrollPositionChanged(isAtBottom: true)
        #expect(controller.isFollowing)
    }

    @Test
    func streamingWhileDetachedStaysPut() {
        // 離脱中にストリーミングが進んでも追従は再開されない（読み返しを邪魔しない）。
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: false)
        for _ in 0..<100 {
            #expect(!controller.contentDidChange())
        }
        #expect(!controller.isFollowing)
    }
}
