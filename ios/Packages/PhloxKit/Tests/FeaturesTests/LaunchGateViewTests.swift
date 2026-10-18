import XCTest
@testable import Features

// DP-4-6 検証。カンプ⑥の文言・寸法を View 層で保証する。
final class LaunchGateViewTests: XCTestCase {

    func testBrandNameMatchesCamp() {
        XCTAssertEqual(LaunchGateCopy.brandName, "Phlox")
    }

    func testTaglineMatchesCamp() {
        XCTAssertEqual(LaunchGateCopy.tagline, "エージェントを止めないリモコン")
    }

    func testLockAndAuthenticationCopyMatchesCamp() {
        XCTAssertEqual(LaunchGateCopy.locked, "ロックされています")
        XCTAssertEqual(LaunchGateCopy.faceIDUnlock, "Face ID で解除")
        XCTAssertEqual(LaunchGateCopy.authenticationFailed, "認証できませんでした")
        XCTAssertTrue(LaunchGateCopy.authenticationFailureBody.contains("パスコードで解除してください"))
    }

    func testKeychainFooterMatchesCamp() {
        XCTAssertEqual(
            LaunchGateCopy.keychainFooter,
            "トークンは Keychain に保護されています。認証するまで Mac には接続しません。"
        )
    }

    func testPasscodeFallbackLabelMatchesCamp() {
        XCTAssertEqual(LaunchGateCopy.passcodeFallback, "パスコードを使用")
    }

    func testLogoMetricsMatchCamp() {
        XCTAssertEqual(LaunchGateMetrics.logoSize, 84)
        XCTAssertEqual(LaunchGateMetrics.logoCornerRadius, 22)
    }

    func testUnlockButtonMetricsMatchCamp() {
        XCTAssertEqual(LaunchGateMetrics.unlockButtonHeight, 52)
    }
}
