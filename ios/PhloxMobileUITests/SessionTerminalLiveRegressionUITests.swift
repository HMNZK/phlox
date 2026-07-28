import XCTest

/// Mac の端末画面が「最新から開き、履歴は自分でスクロールして遡れる」ことの回帰テスト（ライブ接続版）。
///
/// **通常のテストスイートからは外している**。`-UITesting` のモック環境は ANSI 画面を配信しないため
/// この経路自体が動かない。ローカル偽サーバー（実機実測と同じ 138 桁の画面＋履歴 200 行）へ
/// live 接続して回す。
///
/// 守っている退行は 2 つある。
/// - 端末エミュレータの固定行数の枠へ嵌めると、枠より中身が高い分の先頭が消えて二度と読めない
///   （→ ADR 0039）。
/// - Mac が viewport しか送らないと、受け手はどう作っても 1 行も遡れない
///   （→ macos/docs/adr/0134）。
///
/// 実行手順:
/// ```
/// python3 ios/scripts/fake-phlox-server.py --port 53099 &
/// xcodebuild test -scheme PhloxMobile \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -only-testing:PhloxMobileUITests/SessionTerminalLiveRegressionUITests \
///   -parallel-testing-enabled NO
/// ```
final class SessionTerminalLiveRegressionUITests: XCTestCase {

    /// Mac の可視画面の先頭行にしか出ない文字列（履歴の下・画面の途中にある）。
    private let viewportFirstRowMarker = "v2.1.220"
    /// 画面の最終行（＝最新）にしか出ない文字列。
    private let lastRowMarker = "bypass permissions on"
    /// 履歴のいちばん古い行にしか出ない文字列（偽サーバーと合わせている）。
    private let oldestHistoryMarker = "oldest-history-line"
    /// 画面幅より広い表の行にしか出ない文字列（偽サーバーと合わせている）。
    private let wideTableMarker = "wide-table-row"

    func testTerminalOpensAtTheBottomAndScrollsBackThroughHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-phlox.connection.host", "127.0.0.1",
            "-phlox.connection.port", "53099",
        ]
        app.launch()
        dismissSystemAlerts()

        XCTAssertTrue(
            app.descendants(matching: .any)["sessionList"].waitForExistence(timeout: 20),
            "偽サーバーへ接続して一覧が表示されること（サーバーを起動しているか確認）"
        )
        app.descendants(matching: .any)["sessionRow.s-2"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["sessionDetail"].waitForExistence(timeout: 20),
            "セッション詳細へ遷移すること"
        )

        // 開いた直後は最新（最終行）が見えていること。
        let lastRow = staticText(in: app, containing: lastRowMarker)
        XCTAssertTrue(lastRow.waitForExistence(timeout: 20), "開いた直後に最新の行が描かれていること")
        XCTAssertTrue(
            app.windows.firstMatch.frame.intersects(lastRow.frame),
            "最新の行が画面内にあること（最下部から開くこと）"
        )
        add(screenshot(named: "terminal-latest-on-open"))

        // 前提: 履歴の先頭はここからでは見えない（見えていたら遡る検証にならない）。
        XCTAssertFalse(
            isVisible(staticText(in: app, containing: oldestHistoryMarker), in: app),
            "前提: 履歴の先頭は開いた時点では画面外にあること"
        )

        // Mac の可視画面の先頭行まで遡れること（＝枠に嵌めて先頭を捨てていない）。
        XCTAssertTrue(
            scrollUpUntilVisible(in: app, marker: viewportFirstRowMarker),
            "Mac の可視画面の先頭行まで遡れること"
        )
        // さらにその上の履歴まで遡れること（＝viewport だけでなく履歴が届いている）。
        XCTAssertTrue(
            scrollUpUntilVisible(in: app, marker: oldestHistoryMarker),
            "履歴のいちばん古い行まで遡れること（Mac の可視画面だけしか届いていないと到達できない）"
        )
        add(screenshot(named: "terminal-oldest-history"))
    }

    /// 画面幅より広い行を折り返さないこと。折り返すと表・枠線が桁ごとずれて崩れる
    /// （ユーザー報告: 「デスクトップでは正常に表示されている表がモバイルだと崩れる」→ ADR 0040）。
    func testWideTableRowIsNotWrapped() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-phlox.connection.host", "127.0.0.1",
            "-phlox.connection.port", "53099",
        ]
        app.launch()
        dismissSystemAlerts()

        XCTAssertTrue(
            app.descendants(matching: .any)["sessionList"].waitForExistence(timeout: 20),
            "偽サーバーへ接続して一覧が表示されること（サーバーを起動しているか確認）"
        )
        app.descendants(matching: .any)["sessionRow.s-2"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["sessionDetail"].waitForExistence(timeout: 20),
            "セッション詳細へ遷移すること"
        )

        XCTAssertTrue(
            scrollUpUntilVisible(in: app, marker: wideTableMarker),
            "画面幅より広い表の行まで遡れること"
        )
        add(screenshot(named: "terminal-wide-table"))

        let row = staticText(in: app, containing: wideTableMarker)
        let windowWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(
            row.frame.width,
            windowWidth,
            "行が画面幅を超えたまま1行で描かれること（折り返していれば画面幅以下に収まる）"
        )
    }

    /// 目印が画面内へ入るまで上へ遡る。入ったら true。
    private func scrollUpUntilVisible(in app: XCUIApplication, marker: String) -> Bool {
        let target = staticText(in: app, containing: marker)
        for _ in 1...40 {
            if isVisible(target, in: app) { return true }
            swipe(in: app, fromY: 0.25, toY: 0.85)
        }
        return isVisible(target, in: app)
    }

    /// 実際に画面へ収まっているか。`exists` だけでは足りない——端末は画面外の行も
    /// アクセシビリティツリーに持つので、存在は「見えている」を意味しない。
    private func isVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && app.windows.firstMatch.frame.intersects(element.frame)
    }

    private func staticText(in app: XCUIApplication, containing marker: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", marker))
            .firstMatch
    }

    private func screenshot(named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    /// 通知許可などの SpringBoard アラートを片付ける（出たままだと操作が全部吸われる）。
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["許可", "Allow"] where springboard.buttons[label].waitForExistence(timeout: 3) {
            springboard.buttons[label].tap()
        }
    }

    private func swipe(in app: XCUIApplication, fromY: CGFloat, toY: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY)),
                withVelocity: .default,
                thenHoldForDuration: 0.05
            )
    }
}
