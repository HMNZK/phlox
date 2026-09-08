import XCTest

/// Layer B GUI スモーク（launch + render）。
/// R1 パッケージ分割などの構造変更が「アプリ起動 → ダッシュボード描画」を壊していないことを検証する。
///
/// 起動方式: 所有権とデータ分離を確認した LaunchServices 起動に接続する。
/// 直バイナリ起動（`XCUIApplication.launch()`）はこの環境で窓を出せないため使わない。
/// 隔離: `PHLOX_DATA_DIR`（一時dir）＋ `PHLOX_DEFAULTS_SUITE`（専用suite）＋ Keychain 非接触起動。
@MainActor
final class PhloxLaunchSmokeTests: XCTestCase {
    /// 表示モード改善前の観測用。意味や選択状態の合格判定はまだ行わない。
    func testViewModeAccessibilityObservation() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app = try isolated.application()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        for index in 0..<4 {
            try isolated.assertExclusiveOwnership()
            let window = app.windows.firstMatch
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "mode-baseline-\(index)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print("MODE BASELINE \(index): \(window.debugDescription)")
            for button in window.buttons.allElementsBoundByIndex {
                print("MODE BUTTON: id=\(button.identifier) label=\(button.label) value=\(String(describing: button.value)) selected=\(button.isSelected) frame=\(button.frame)")
            }
            if index < 3 {
                try isolated.assertExclusiveOwnership()
                app.typeKey("g", modifierFlags: [.command, .control])
                try await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    /// アプリが起動し、ダッシュボード（メインウィンドウ＋操作可能な UI）が描画されることを検証する。
    func testDashboardRendersOnLaunch() async throws {
        let isolated = try await IsolatedPhloxApplication.launch(in: self)
        let app = try isolated.application()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30),
            "メインウィンドウが 30 秒以内に表示されなかった"
        )
        // 空/エラー窓ではなくダッシュボードが描画されている証明として、操作可能なボタンの存在を確認する。
        try isolated.assertExclusiveOwnership()
        XCTAssertTrue(
            app.buttons.firstMatch.waitForExistence(timeout: 30),
            "ダッシュボードの UI 要素（ボタン）が描画されなかった"
        )
    }
}
