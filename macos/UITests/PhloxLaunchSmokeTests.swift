import XCTest

/// Layer B GUI スモーク（launch + render）。
/// R1 パッケージ分割などの構造変更が「アプリ起動 → ダッシュボード描画」を壊していないことを検証する。
///
/// 起動方式: `open`（LaunchServices）で起動し `XCUIApplication(bundleIdentifier:)` で attach。
/// 直バイナリ起動（`XCUIApplication.launch()`）はこの環境で窓を出せないため使わない。
/// 隔離: `PHLOX_DATA_DIR`（一時dir）＋ `PHLOX_DEFAULTS_SUITE`（専用suite）＋ Keychain 非接触起動。
final class PhloxLaunchSmokeTests: XCTestCase {
    private static let bundleID = "com.phlox.Phlox.debug"

    /// ビルド成果物ディレクトリから Phlox.app のパスを導出する（derivedDataPath 非依存）。
    /// UITest バンドル（`.../<Products>/PhloxUITests-Runner.app/Contents/PlugIns/PhloxUITests.xctest`）から
    /// 親を辿り、Phlox.app を兄弟に持つディレクトリ（= <Products>）を見つける。
    private static var appPath: String {
        var dir = Bundle(for: PhloxLaunchSmokeTests.self).bundleURL
        for _ in 0..<6 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("Phlox.app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return dir.appendingPathComponent("Phlox.app").path
    }

    private func launchIsolated() -> XCUIApplication {
        let tmp = NSTemporaryDirectory() + "phlox-uitest-" + UUID().uuidString
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [
            "-n",
            "--env", "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1",
            "--env", "PHLOX_DATA_DIR=\(tmp)",
            "--env", "PHLOX_DEFAULTS_SUITE=phlox.uitest." + UUID().uuidString,
            Self.appPath,
        ]
        try? open.run()
        open.waitUntilExit()
        // open は約 1 秒で窓を出す。レンダリング猶予を置いてから attach する。
        Thread.sleep(forTimeInterval: 4)
        return XCUIApplication(bundleIdentifier: Self.bundleID)
    }

    /// アプリが起動し、ダッシュボード（メインウィンドウ＋操作可能な UI）が描画されることを検証する。
    func testDashboardRendersOnLaunch() {
        let app = launchIsolated()
        defer { app.terminate() }

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30),
            "メインウィンドウが 30 秒以内に表示されなかった"
        )
        // 空/エラー窓ではなくダッシュボードが描画されている証明として、操作可能なボタンの存在を確認する。
        XCTAssertTrue(
            app.buttons.firstMatch.waitForExistence(timeout: 30),
            "ダッシュボードの UI 要素（ボタン）が描画されなかった"
        )
    }
}
