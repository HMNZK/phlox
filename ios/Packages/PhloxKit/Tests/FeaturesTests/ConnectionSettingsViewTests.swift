import XCTest
@testable import Features

// QR 専用設定画面の文言と読み取り専用表示の契約を保証する。
final class ConnectionSettingsViewTests: XCTestCase {
    func testTitleAndSubtitleDescribeQRSetup() {
        XCTAssertEqual(ConnectionSettingsCopy.title, "接続設定")
        XCTAssertEqual(ConnectionSettingsCopy.subtitle, "Mac の Phlox に QR コードで接続")
    }

    func testConnectionSectionDescribesReadOnlyDestination() {
        XCTAssertEqual(ConnectionSettingsCopy.connectionSection, "接続")
        XCTAssertEqual(ConnectionSettingsCopy.currentConnectionLabel, "現在の接続先")
        XCTAssertEqual(ConnectionSettingsCopy.notConnectedValue, "未接続")
    }

    func testQRButtonTitlesCoverInitialConnectionAndReconnection() {
        XCTAssertEqual(ConnectionSettingsCopy.connectButtonTitle, "QR で接続")
        XCTAssertEqual(ConnectionSettingsCopy.reconnectButtonTitle, "QR で再接続")
    }

    func testTestConnectionSuccessBannerCopy() {
        XCTAssertEqual(ConnectionSettingsCopy.testSuccessMessage, "接続成功 · GET /sessions → 200")
    }

    func testTestConnectionFailureBannerCopy() {
        XCTAssertEqual(ConnectionSettingsCopy.testFailureMessage, "到達不可 · Mac がスリープ中の可能性")
    }

    func testMissingConnectionGuidanceRequiresQR() {
        XCTAssertEqual(ConnectionSettingsCopy.noConnectionMessage, "QR コードを読み取って接続してください")
    }

    func testTestConnectionButtonTitleRemainsAvailable() {
        XCTAssertEqual(ConnectionSettingsCopy.testConnectionButtonTitle, "疎通テスト")
    }
}
