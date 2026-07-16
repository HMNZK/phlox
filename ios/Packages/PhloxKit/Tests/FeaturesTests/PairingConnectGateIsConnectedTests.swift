import XCTest
import PhloxCore
import Features

/// `PairingConnectGate.isConnected` の単体テスト。接続待ちループが停止したとき、
/// それが成功（一覧到達）かタイムアウト失敗かを判別する述語であることを固定する。
final class PairingConnectGateIsConnectedTests: XCTestCase {

    func testLoadedIsConnected() {
        XCTAssertTrue(PairingConnectGate.isConnected(listState: .loaded([])))
    }

    func testEmptyIsConnected() {
        XCTAssertTrue(PairingConnectGate.isConnected(listState: .empty))
    }

    func testOfflineIsNotConnected() {
        XCTAssertFalse(PairingConnectGate.isConnected(listState: .offline))
    }

    func testLoadingIsNotConnected() {
        XCTAssertFalse(PairingConnectGate.isConnected(listState: .loading))
    }
}
