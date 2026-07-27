import XCTest

/// セッション詳細からの端スワイプで戻れることを、実 UIKit のジェスチャ経路で検証する E2E。
///
/// 詳細画面は `.toolbar(.hidden, for: .navigationBar)` でナビゲーションバーを隠すため、
/// UIKit は `interactivePopGestureRecognizer` を無効化する。これを復帰させる実装
/// （`InteractivePopGestureRestorer`）は `UIViewControllerRepresentable` 越しに
/// `UINavigationController` へ触るため、in-process のユニットテストでは判定層しか検証できない。
/// 実際に指のスワイプで戻れるかはここでしか確かめられない。
final class SessionDetailBackSwipeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// 端スワイプでセッション一覧へ戻る。
    func testEdgeSwipeFromSessionDetailReturnsToList() throws {
        let detail = try openSessionDetail()

        swipeFromLeftEdge(to: 0.9)

        XCTAssertTrue(
            app.navigationBars["Projects"].waitForExistence(timeout: 5),
            "端スワイプでセッション一覧へ戻ること（ナビゲーションバーを隠しても端スワイプを復帰させる）"
        )
        XCTAssertFalse(detail.exists, "詳細画面が pop されていること")
    }

    /// 戻ったあと同じ行を開き直せる（pop でジェスチャ状態が壊れていないこと）。
    func testCanReopenSessionAfterEdgeSwipeBack() throws {
        _ = try openSessionDetail()
        swipeFromLeftEdge(to: 0.9)
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))

        let reopened = try openSessionDetail(waitForList: false)

        XCTAssertTrue(reopened.exists, "戻ったあとも同じセッションを開き直せること")
    }

    /// 途中で離した端スワイプはキャンセルされ、詳細画面に留まる。
    func testCancelledEdgeSwipeStaysOnSessionDetail() throws {
        let detail = try openSessionDetail()

        swipeFromLeftEdge(to: 0.12)

        XCTAssertTrue(
            detail.waitForExistence(timeout: 5),
            "浅い端スワイプは pop せず詳細画面に留まること"
        )
        XCTAssertFalse(app.navigationBars["Projects"].exists, "一覧へ戻っていないこと")
    }

    /// キャンセルした端スワイプの直後でも、もう一度端スワイプすれば戻れる。
    /// キャンセル時は `viewWillDisappear` → `viewWillAppear` の順に呼ばれるため、
    /// 離脱時に元のデリゲートへ戻す実装は、復帰時に再設定できていないと2回目が効かなくなる。
    func testEdgeSwipeAfterCancelledEdgeSwipeStillReturnsToList() throws {
        let detail = try openSessionDetail()

        swipeFromLeftEdge(to: 0.12)
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "浅い端スワイプはキャンセルされ詳細に留まること")
        XCTAssertFalse(app.navigationBars["Projects"].exists, "キャンセル時点では一覧へ戻っていないこと")

        swipeFromLeftEdge(to: 0.9)

        XCTAssertTrue(
            app.navigationBars["Projects"].waitForExistence(timeout: 5),
            "キャンセル後の2回目の端スワイプでも戻れること"
        )
    }

    /// 根の一覧で端スワイプしても、その後のナビゲーションが壊れない。
    func testRootEdgeSwipeAfterPopKeepsNavigationUsable() throws {
        _ = try openSessionDetail()
        swipeFromLeftEdge(to: 0.9)
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))

        // 根の画面（深さ1）での端スワイプ。何も起きないのが正。
        swipeFromLeftEdge(to: 0.9)
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5), "根の画面では何も起きないこと")

        _ = try openSessionDetail(waitForList: false)
        swipeFromLeftEdge(to: 0.9)

        XCTAssertTrue(
            app.navigationBars["Projects"].waitForExistence(timeout: 5),
            "根での端スワイプ後に開き直した詳細からも戻れること"
        )
    }

    /// 横スクロールする出力カードの高さから始めた端スワイプでも戻れる。
    /// 端スワイプと横スクロールの同時認識を禁じているため、取り合いで戻れなくならないことを確かめる。
    func testEdgeSwipeOverHorizontalScrollAreaReturnsToList() throws {
        _ = try openSessionDetail()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.42))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        XCTAssertTrue(
            app.navigationBars["Projects"].waitForExistence(timeout: 5),
            "横スクロール領域の上から始めた端スワイプでも戻れること"
        )
    }

    /// 画面中央からの右スワイプでは戻らない（端スワイプだけが pop する）。
    /// 本文へ横方向のジェスチャを敷いて戻る実装にすると、出力カードや表の横スクロールを奪う。
    func testMiddleSwipeDoesNotPopSessionDetail() throws {
        let detail = try openSessionDetail()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        XCTAssertTrue(detail.waitForExistence(timeout: 5), "中央からの横スワイプでは pop しないこと")
        XCTAssertFalse(app.navigationBars["Projects"].exists, "一覧へ戻っていないこと")
    }

    // MARK: - ヘルパー

    private func openSessionDetail(waitForList: Bool = true) throws -> XCUIElement {
        if waitForList {
            app.launchArguments = ["-UITesting", "-UIScenario=goldenPath", "-UIViewAnimationsEnabled", "NO"]
            app.launch()
            let list = app.descendants(matching: .any)[AccessibilityID.sessionList]
            XCTAssertTrue(list.waitForExistence(timeout: 10), "セッション一覧が表示されること")
        }

        app.descendants(matching: .any)[AccessibilityID.attentionRow("sess-rose")].tap()

        let detail = app.descendants(matching: .any)[AccessibilityID.sessionDetail]
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "セッション詳細へ遷移すること")
        return detail
    }

    /// 画面左端から水平にドラッグする。
    /// 端スワイプは対話的トランジションなので、瞬間移動に近い高速ドラッグでは認識されないことがある。
    /// 実際の指の動きに近づけるため速度を落とし、離す前に保持する。
    private func swipeFromLeftEdge(to endX: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.2
        )
    }
}

private enum AccessibilityID {
    static let sessionList = "sessionList"
    static let sessionDetail = "sessionDetail"
    static func attentionRow(_ id: String) -> String { "attentionRow.\(id)" }
}
