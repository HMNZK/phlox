import XCTest
import PhloxCore
@testable import PhloxReachability

final class ReachabilityMonitorRefreshTests: XCTestCase {
    func testRefreshRunsHealthCheck() async {
        let calls = CallCounter()
        let monitor = ReachabilityMonitor {
            await calls.increment()
            return true
        }

        await monitor.refresh()
        let callCount = await calls.value
        let current = await monitor.current

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(current, .online)
    }

    func testRepeatedRefreshUsesLatestHealthCheckResult() async {
        let health = MutableHealth(false)
        let monitor = ReachabilityMonitor {
            await health.value
        }

        await monitor.refresh()
        let initialResult = await monitor.current
        XCTAssertEqual(initialResult, .unreachableHost)

        await health.set(true)
        await monitor.refresh()
        let refreshedResult = await monitor.current
        XCTAssertEqual(refreshedResult, .online)
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor MutableHealth {
    private(set) var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func set(_ value: Bool) {
        self.value = value
    }
}
