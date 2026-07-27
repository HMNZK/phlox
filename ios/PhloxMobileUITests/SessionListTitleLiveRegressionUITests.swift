import XCTest

/// 一覧の大タイトル「Projects」がスクロール往復で消えないことの回帰テスト（ライブ接続版）。
///
/// **通常のテストスイートからは外している**。`-UITesting` のモック環境では 1ms 間隔の再取得で
/// 画面が絶えず作り直されるため、この症状（iOS 26 でシステム大タイトルが戻らない → ADR 0036）を
/// 再現できない。実データが動いている状態でしか出ないので、ローカル偽サーバーへ live 接続して回す。
///
/// 実行手順:
/// ```
/// python3 ios/scripts/fake-phlox-server.py --port 53099 --churn &
/// xcodebuild test -scheme PhloxMobile \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -only-testing:PhloxMobileUITests/SessionListTitleLiveRegressionUITests \
///   -parallel-testing-enabled NO
/// ```
final class SessionListTitleLiveRegressionUITests: XCTestCase {

    func testScrollingTheListKeepsProjectsTitle() throws {
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
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 5), "初期表示で Projects タイトルが可視")

        // タイトルが消えてもアクセシビリティ要素と枠は残る（描画だけが落ちる）ので、
        // exists / isHittable では検出できない。実際に描かれた画素を数えて判定する。
        let band = app.staticTexts["Projects"].frame
        let before = try drawnPixelCount(in: band)
        XCTAssertGreaterThan(before, 0, "初期表示で大タイトルが実際に描かれていること")

        swipe(in: app, fromY: 0.7, toY: 0.3)
        swipe(in: app, fromY: 0.3, toY: 0.85)
        sleep(2)

        let after = try drawnPixelCount(in: band)
        XCTAssertGreaterThan(
            after, before / 2,
            "スクロール往復の後も大タイトルが描かれていること（前=\(before) 後=\(after)）"
        )
    }

    /// 指定範囲に実際に描かれている暗い画素の数。要素の有無ではなく「見えているか」を測る。
    private func drawnPixelCount(in frame: CGRect) throws -> Int {
        let image = XCUIScreen.main.screenshot().image
        let cgImage = try XCTUnwrap(image.cgImage, "スクリーンショットを取得できること")
        let scale = CGFloat(cgImage.width) / image.size.width
        let rect = CGRect(
            x: frame.minX * scale,
            y: frame.minY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        ).integral
        let cropped = try XCTUnwrap(cgImage.cropping(to: rect), "判定範囲を切り出せること")

        let width = cropped.width
        let height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ),
            "グレースケールへ描き直せること"
        )
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        // 明るい地に濃い文字（またはその逆）。中間より暗い画素を「描かれている」とみなす。
        let darkCount = pixels.filter { $0 < 128 }.count
        return min(darkCount, pixels.count - darkCount) == darkCount ? darkCount : pixels.count - darkCount
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
