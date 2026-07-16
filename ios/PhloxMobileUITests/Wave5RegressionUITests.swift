import XCTest

/// wave-5 バグ修正の症状回帰（XCUITest）。
/// - task-3: 右上メニューの「名前変更」「モデル変更」を繰り返し開けること（presentation の取りこぼし回帰防止）。
/// - task-4: 一覧⇄詳細の往復後も上部の「Projects」タイトルが可視で、上部空白が出ないこと。
/// `-UITesting -UIScenario=goldenPath` のモック環境で実行する。
final class Wave5RegressionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UIScenario=goldenPath", "-UIViewAnimationsEnabled", "NO"]
        app.launch()
    }

    private func openRoseDetail() {
        let list = app.descendants(matching: .any)["sessionList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "セッション一覧が表示されること")
        app.descendants(matching: .any)["attentionRow.sess-rose"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["sessionDetail"].waitForExistence(timeout: 10),
            "詳細画面へ遷移すること"
        )
    }

    // MARK: - task-3: メニューの再表示（何度押しても開く）

    /// 「名前変更」を連続して3回開けること（rename アラートが毎回出る）。
    /// 修正前は presentation を同一 View に積みポーリング再評価で取りこぼし、2回目以降開かないことがあった。
    func testRenameReopensRepeatedly() throws {
        openRoseDetail()
        for i in 1...3 {
            app.buttons["セッションメニュー"].tap()
            let rename = app.buttons["名前変更"]
            XCTAssertTrue(rename.waitForExistence(timeout: 3), "メニューに『名前変更』が出ること(\(i))")
            rename.tap()
            let field = app.textFields["セッション名"]
            XCTAssertTrue(field.waitForExistence(timeout: 3), "『名前変更』が\(i)回目も開くこと")
            app.buttons["キャンセル"].tap()
            XCTAssertFalse(field.waitForExistence(timeout: 1), "キャンセルで閉じること(\(i))")
        }
    }

    /// 「モデル変更」→ シートが開き、閉じてから「名前変更」も開けること（排他 presentation の健全性）。
    func testModelChangeThenRenameBothOpen() throws {
        openRoseDetail()
        app.buttons["セッションメニュー"].tap()
        let model = app.buttons["モデル変更"]
        XCTAssertTrue(model.waitForExistence(timeout: 3), "メニューに『モデル変更』が出ること")
        model.tap()
        // モデル選択シート（ModelPickerSheet: navigationTitle "Model" + 「閉じる」）が提示されること。
        let close = app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "モデル選択シートが開くこと")
        // 「閉じる」で閉じる。
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 1), "モデルシートが閉じること")
        // 続けて名前変更も開けること（片方を出した後にもう片方が取りこぼされない）。
        app.buttons["セッションメニュー"].tap()
        let rename = app.buttons["名前変更"]
        XCTAssertTrue(rename.waitForExistence(timeout: 3), "続けてメニューが開くこと")
        rename.tap()
        XCTAssertTrue(app.textFields["セッション名"].waitForExistence(timeout: 3), "モデルシートの後に名前変更も開くこと")
        app.buttons["キャンセル"].tap()
    }

    // MARK: - task-4: 一覧⇄詳細往復で上部が空白にならない

    /// 詳細へ入って戻る往復を2回繰り返しても、一覧上部の「Projects」タイトルが可視であること。
    /// 修正前は UINavigationBar.appearance() の同一テーマ再適用で large title が消え上部が空白になった。
    func testListDetailRoundTripKeepsProjectsTitle() throws {
        let list = app.descendants(matching: .any)["sessionList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 3), "初期表示で Projects タイトルが可視")

        for i in 1...2 {
            app.descendants(matching: .any)["attentionRow.sess-rose"].tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["sessionDetail"].waitForExistence(timeout: 10),
                "詳細へ遷移(\(i))"
            )
            let back = app.buttons["戻る"]
            XCTAssertTrue(back.waitForExistence(timeout: 3), "戻るボタンが出ること(\(i))")
            back.tap()
            XCTAssertTrue(
                app.navigationBars["Projects"].waitForExistence(timeout: 5),
                "往復\(i)回目の後も Projects タイトルが可視（上部空白にならない）"
            )
            XCTAssertTrue(app.staticTexts["あなたの番"].waitForExistence(timeout: 3), "一覧の注目セクションが可視(\(i))")
        }
    }

    // MARK: - task-1(wave-7): 入力欄の整理（ドラッグバー廃止・音声ボタン廃止・送信/停止を右スロット常設）

    /// 整理後の入力欄アフォーダンスを実画面で確認する。画像添付（＋）と、右スロットに常設された
    /// 送信ボタンが描画され、廃止したドラッグハンドル・音声入力ボタンが描画されないこと。
    func testInputBarAffordancesAfterCleanup() throws {
        openRoseDetail()
        // ＋（PhotosPicker）と送信ボタン（空文字時は無効だが a11y ツリーには存在）は常設。
        XCTAssertTrue(app.descendants(matching: .any)["画像を添付"].waitForExistence(timeout: 5), "画像添付（＋）ボタンが描画されること")
        XCTAssertTrue(app.descendants(matching: .any)["送信"].waitForExistence(timeout: 3), "送信ボタンが右スロットに常設されること")
        // 廃止したアフォーダンスは描画されない。
        XCTAssertFalse(app.descendants(matching: .any)["入力欄を閉じる"].waitForExistence(timeout: 2), "ドラッグハンドルは廃止され描画されないこと")
        XCTAssertFalse(app.descendants(matching: .any)["音声入力を開始"].waitForExistence(timeout: 2), "音声入力ボタンは廃止され描画されないこと")
    }
}
