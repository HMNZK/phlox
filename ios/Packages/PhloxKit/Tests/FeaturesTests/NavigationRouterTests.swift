import XCTest
@testable import Features

// E4-10 検証。NavigationRouter のスタック操作とモーダル提示を検証する。
@MainActor
final class NavigationRouterTests: XCTestCase {

    func testPushIncrementsDepth() {
        let router = NavigationRouter()
        XCTAssertEqual(router.depth, 0)
        router.push(.sessionDetail(id: "s1"))
        XCTAssertEqual(router.depth, 1)
        router.push(.settings)
        XCTAssertEqual(router.depth, 2)
    }

    func testPopDecrementsDepth() {
        let router = NavigationRouter()
        router.push(.sessionDetail(id: "s1"))
        router.push(.settings)
        router.pop()
        XCTAssertEqual(router.depth, 1)
    }

    func testPopOnEmptyIsNoOp() {
        let router = NavigationRouter()
        router.pop()
        XCTAssertEqual(router.depth, 0)
    }

    func testPopToRootClearsStack() {
        let router = NavigationRouter()
        router.push(.sessionDetail(id: "s1"))
        router.push(.settings)
        router.popToRoot()
        XCTAssertEqual(router.depth, 0)
    }

    func testPresentAndDismissModal() {
        let router = NavigationRouter()
        XCTAssertNil(router.presented)
        router.present(.deleteConfirmation(id: "s1", cascadeCount: 3))
        XCTAssertEqual(router.presented, .deleteConfirmation(id: "s1", cascadeCount: 3))
        router.dismiss()
        XCTAssertNil(router.presented)
    }
}
