import XCTest

/// Layer B GUI スモーク（launch + render）。
/// R1 パッケージ分割などの構造変更が「アプリ起動 → ダッシュボード描画」を壊していないことを検証する。
///
/// 起動方式: 所有権とデータ分離を確認した LaunchServices 起動に接続する。
/// 直バイナリ起動（`XCUIApplication.launch()`）はこの環境で窓を出せないため使わない。
/// 隔離: `PHLOX_DATA_DIR`（一時dir）＋ `PHLOX_DEFAULTS_SUITE`（専用suite）＋ Keychain 非接触起動。
@MainActor
final class PhloxLaunchSmokeTests: XCTestCase {
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
