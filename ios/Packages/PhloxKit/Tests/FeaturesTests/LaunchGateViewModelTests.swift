import XCTest
import PhloxCore
@testable import Features

// E4-1 検証。生体認証の成功/失敗による状態遷移を検証する。
@MainActor
final class LaunchGateViewModelTests: XCTestCase {

    func testSuccessfulAuthenticationUnlocks() async {
        let vm = LaunchGateViewModel(authenticator: StubAuthenticator(allows: true))
        await vm.authenticate()
        XCTAssertEqual(vm.state, .unlocked)
        XCTAssertTrue(vm.isUnlocked)
        XCTAssertNil(vm.errorMessage)
    }

    func testDeniedAuthenticationFails() async {
        let vm = LaunchGateViewModel(authenticator: StubAuthenticator(allows: false))
        await vm.authenticate()
        if case .failed = vm.state {} else {
            XCTFail("expected .failed, got \(vm.state)")
        }
        XCTAssertFalse(vm.isUnlocked)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testThrowingAuthenticatorFails() async {
        let vm = LaunchGateViewModel(authenticator: ThrowingAuthenticator())
        await vm.authenticate()
        XCTAssertFalse(vm.isUnlocked)
        XCTAssertNotNil(vm.errorMessage)
    }
}

private struct ThrowingAuthenticator: Authenticating {
    func authenticate(reason: String) async throws -> Bool {
        throw AuthError.boom
    }
    enum AuthError: Error { case boom }
}
