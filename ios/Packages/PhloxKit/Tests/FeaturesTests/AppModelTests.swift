import XCTest
import PhloxCore
@testable import Features

// E4-10 検証。AppModel の 4 段階ルート分岐（認証→接続→到達性→セッション）を検証する。
@MainActor
final class AppModelTests: XCTestCase {

    func testLockedWhenAuthLocked() {
        XCTAssertEqual(
            AppModel.resolve(authState: .locked, hasConnectionConfig: true, reachability: .online),
            .locked
        )
    }

    func testSetupRequiredWhenUnlockedButNoConfig() {
        XCTAssertEqual(
            AppModel.resolve(authState: .unlocked, hasConnectionConfig: false, reachability: .online),
            .setupRequired
        )
    }

    func testSessionsWhenUnlockedConfiguredAndOnline() {
        XCTAssertEqual(
            AppModel.resolve(authState: .unlocked, hasConnectionConfig: true, reachability: .online),
            .sessions
        )
    }

    func testSessionsWhenUnreachableHost() {
        XCTAssertEqual(
            AppModel.resolve(authState: .unlocked, hasConnectionConfig: true, reachability: .unreachableHost),
            .sessions
        )
    }

    func testSessionsWhenOfflineNetwork() {
        XCTAssertEqual(
            AppModel.resolve(authState: .unlocked, hasConnectionConfig: true, reachability: .offlineNetwork),
            .sessions
        )
    }

    func testUnknownReachabilityTreatedAsSessions() {
        XCTAssertEqual(
            AppModel.resolve(authState: .unlocked, hasConnectionConfig: true, reachability: .unknown),
            .sessions
        )
    }

    func testInstanceStateReflectsProperties() {
        let model = AppModel(authState: .unlocked, hasConnectionConfig: true, reachability: .online)
        XCTAssertEqual(model.state, .sessions)
        model.authState = .locked
        XCTAssertEqual(model.state, .locked)
    }
}
