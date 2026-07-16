import XCTest
import PhloxCore
import Features

/// wave-9 「接続中…」オーバーレイの閉じ判定の凍結受け入れテスト（PM 著・実装役は編集禁止）。
/// 接続中は「到達性 online」ではなく「セッション一覧の取得成功（loaded/empty）」まで保持し、
/// タイムアウト到達時のみ（未達でも）閉じることを固定する（＝QRペアリング直後の即閉じ不具合の修正）。
final class PairingConnectGateAcceptanceTests: XCTestCase {

    /// 一覧が読めた（loaded）ら接続中を閉じる。
    func testStopsWhenListLoaded() {
        XCTAssertFalse(
            PairingConnectGate.shouldContinueConnecting(
                listState: .loaded([]), elapsed: 1, timeout: 20
            )
        )
    }

    /// 空一覧（empty）でも接続完了として閉じる。
    func testStopsWhenListEmpty() {
        XCTAssertFalse(
            PairingConnectGate.shouldContinueConnecting(
                listState: .empty, elapsed: 1, timeout: 20
            )
        )
    }

    /// オフライン中かつタイムアウト未満は接続中を継続（＝オフライン画面を挟まない）。
    func testContinuesWhileOfflineWithinTimeout() {
        XCTAssertTrue(
            PairingConnectGate.shouldContinueConnecting(
                listState: .offline, elapsed: 3, timeout: 20
            )
        )
    }

    /// ローディング中かつタイムアウト未満も継続。
    func testContinuesWhileLoadingWithinTimeout() {
        XCTAssertTrue(
            PairingConnectGate.shouldContinueConnecting(
                listState: .loading, elapsed: 3, timeout: 20
            )
        )
    }

    /// タイムアウト到達後は、まだオフラインでも接続中を閉じる（オフライン案内へ落とす・無限スピナー防止）。
    func testStopsAfterTimeoutEvenIfOffline() {
        XCTAssertFalse(
            PairingConnectGate.shouldContinueConnecting(
                listState: .offline, elapsed: 20, timeout: 20
            )
        )
    }
}
