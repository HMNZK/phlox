import XCTest
import PhloxCore
@testable import Features

// DP-4-10 / E4-4 検証。一覧オーバーレイ用の到達不可表示と再接続を検証する。
@MainActor
final class UnreachableViewModelTests: XCTestCase {

    func testOfflineNetworkCardMentionsOutOfRange() {
        let vm = UnreachableViewModel(reachability: .offlineNetwork, onRetry: {})
        XCTAssertEqual(vm.cardTitle, "オフライン")
        XCTAssertTrue(vm.cardMessage.contains("圏外"))
    }

    func testUnreachableHostCardTitleAndPingDetail() {
        let vm = UnreachableViewModel(
            reachability: .unreachableHost,
            host: "100.64.0.1",
            onRetry: {}
        )
        XCTAssertEqual(vm.cardTitle, "Mac に到達できません")
        XCTAssertTrue(vm.cardMessage.contains("スリープ") || vm.cardMessage.contains("Tailscale"))
        XCTAssertEqual(vm.technicalDetail, "ping 100.64.0.1 → timeout")
    }

    func testBannerTextIncludesOfflineAndLastFetched() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let vm = UnreachableViewModel(
            reachability: .offlineNetwork,
            lastUpdated: now.addingTimeInterval(-120),
            onRetry: {}
        )
        XCTAssertEqual(vm.bannerText(now: now), "オフライン · 最終取得 2分前")
    }

    func testBannerTextOfflineOnlyWhenNoTimestamp() {
        let vm = UnreachableViewModel(reachability: .offlineNetwork, onRetry: {})
        XCTAssertEqual(vm.bannerText(), "オフライン")
    }

    func testLastUpdatedTextNilWhenNoTimestamp() {
        let vm = UnreachableViewModel(reachability: .offlineNetwork, onRetry: {})
        XCTAssertNil(vm.lastUpdatedText())
    }

    func testRetryInvokesCallback() async {
        var retried = false
        let vm = UnreachableViewModel(reachability: .unreachableHost, onRetry: { retried = true })
        await vm.retry()
        XCTAssertTrue(retried)
        XCTAssertFalse(vm.isRetrying)
    }
}
