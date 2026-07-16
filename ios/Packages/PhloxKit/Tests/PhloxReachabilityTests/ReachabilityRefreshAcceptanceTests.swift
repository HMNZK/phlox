import XCTest
import PhloxCore
@testable import PhloxReachability

/// wave-8 到達性オンデマンド再判定の凍結受け入れテスト（PM 著・実装役は編集禁止）。
/// `refresh()` が現在のネットワーク状態で healthCheck を即実行し `current` を更新することを固定する
/// （NWPathMonitor の経路イベントを待たずに再判定できること＝QRペアリング直後・手動リトライの修正）。
final class ReachabilityRefreshAcceptanceTests: XCTestCase {

    func testRefreshWithReachableHostGoesOnline() async {
        let monitor = ReachabilityMonitor(healthCheck: { true })
        await monitor.refresh()
        let current = await monitor.current
        XCTAssertEqual(current, .online)
    }

    func testRefreshWithUnreachableHostGoesUnreachable() async {
        let monitor = ReachabilityMonitor(healthCheck: { false })
        await monitor.refresh()
        let current = await monitor.current
        XCTAssertEqual(current, .unreachableHost)
    }

    /// 物理ネットワーク不満足時は、ホスト応答可否に依らず offlineNetwork（unreachableHost と取り違えない）。
    /// refresh() がキャッシュ既定 true を鵜呑みにせず、実ネット状態で判定することを固定する。
    func testRefreshWithUnsatisfiedNetworkGoesOffline() async {
        let monitor = ReachabilityMonitor(healthCheck: { true }, initialNetworkSatisfied: false)
        await monitor.refresh()
        let current = await monitor.current
        XCTAssertEqual(current, .offlineNetwork)
    }
}
