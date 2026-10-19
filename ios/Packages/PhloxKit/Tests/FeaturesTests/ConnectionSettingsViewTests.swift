import XCTest
@testable import Features

// QR 専用設定画面の文言と読み取り専用表示の契約を保証する。
final class ConnectionSettingsViewTests: XCTestCase {
    func testTitleAndSubtitleDescribeQRSetup() {
        XCTAssertEqual(ConnectionSettingsCopy.title, "Mac とつなぐ")
        XCTAssertEqual(ConnectionSettingsCopy.subtitle, "Mac で動いている Claude Code・Codex・Cursor のセッションを、この iPhone から見て、応答できるようにします。")
    }

    func testConnectionSectionDescribesReadOnlyDestination() {
        XCTAssertEqual(ConnectionSettingsCopy.connectionSection, "接続")
        XCTAssertEqual(ConnectionSettingsCopy.currentConnectionLabel, "現在の接続先")
        XCTAssertEqual(ConnectionSettingsCopy.notConnectedValue, "未設定")
    }

    func testQRButtonTitlesCoverInitialConnectionAndReconnection() {
        XCTAssertEqual(ConnectionSettingsCopy.connectButtonTitle, "QR を読み取る")
        XCTAssertEqual(ConnectionSettingsCopy.reconnectButtonTitle, "QR で再接続")
    }

    func testTestConnectionSuccessBannerCopy() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 7, minute: 23)))
        XCTAssertEqual(ConnectionSettingsCopy.successMessage(at: date), "GET /sessions → 200 · 07:23 に確認")
        XCTAssertTrue(ConnectionSettingsCopy.successMessage(at: Date()).range(of: #"^GET /sessions → 200 · \d{2}:\d{2} に確認$"#, options: .regularExpression) != nil)
    }

    func testTestConnectionFailureBannerCopy() {
        XCTAssertEqual(ConnectionSettingsCopy.testFailureMessage, "Mac がスリープしているか、Mac か iPhone の Tailscale が切れています。確かめてから、もう一度テストしてください。")
    }

    func testMissingConnectionGuidanceRequiresQR() {
        XCTAssertEqual(ConnectionSettingsCopy.noConnectionMessage, "QR コードを読み取って、接続先を保存してください。")
    }

    func testTestConnectionButtonTitleRemainsAvailable() {
        XCTAssertEqual(ConnectionSettingsCopy.testConnectionButtonTitle, "疎通テスト")
    }
}
