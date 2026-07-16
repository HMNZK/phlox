import XCTest
import PhloxCore
import Features

/// PairingConnectGate の白箱テスト（実装役任意）。
final class PairingConnectGateWhiteboxTests: XCTestCase {

    func testContinuesWhileErrorWithinTimeout() {
        XCTAssertTrue(
            PairingConnectGate.shouldContinueConnecting(
                listState: .error(.unreachable),
                elapsed: 5,
                timeout: 20
            )
        )
    }

    func testStopsAfterTimeoutEvenIfLoading() {
        XCTAssertFalse(
            PairingConnectGate.shouldContinueConnecting(
                listState: .loading,
                elapsed: 25,
                timeout: 20
            )
        )
    }

    func testTimeoutTakesPriorityOverLoaded() {
        XCTAssertFalse(
            PairingConnectGate.shouldContinueConnecting(
                listState: .loaded([]),
                elapsed: 20,
                timeout: 20
            )
        )
    }
}
