import XCTest
import PhloxCore
@testable import Features

@MainActor
final class UnreachableViewModelTests: XCTestCase {
    func testOfflineNetworkUsesNeutralInternetMessage() {
        let model = UnreachableViewModel(reachability: .offlineNetwork)

        XCTAssertEqual(model.cardTitle, "インターネットにつながっていません")
        XCTAssertEqual(model.cardMessage, "iPhone が圏外か、機内モードになっています。通信が戻ると自動でつなぎ直します。")
        XCTAssertNil(model.technicalDetail)
    }

    func testUnreachableHostShowsRedStateDetailAndLastFetchFooter() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let model = UnreachableViewModel(
            reachability: .unreachableHost,
            endpoint: "100.64.0.1:8765",
            lastUpdated: fetchedAt
        )

        XCTAssertEqual(model.cardTitle, "Mac に届きません")
        XCTAssertEqual(model.technicalDetail, "100.64.0.1:8765 · 無応答")
        XCTAssertEqual(model.lastUpdatedText(now: fetchedAt.addingTimeInterval(180)), "最終取得 3 分前")
        XCTAssertEqual(
            model.footerText(now: fetchedAt.addingTimeInterval(180)),
            "最終取得 3 分前 · 下の「再接続を試す」で今すぐ確認"
        )
    }

    func testUnknownStateUsesConnectionJudgingCopy() {
        let model = UnreachableViewModel(reachability: .unknown)

        XCTAssertEqual(model.cardTitle, "接続を確かめています")
        XCTAssertEqual(model.cardMessage, "Mac からの応答を待っています。最大 20 秒ほどかかります。")
        XCTAssertNil(model.technicalDetail)
    }

    func testFooterExplainsWhenThereWasNoSuccessfulFetch() {
        let model = UnreachableViewModel(reachability: .offlineNetwork)

        XCTAssertEqual(model.footerText(), "最終取得なし · 下の「再接続を試す」で今すぐ確認")
    }

    func testRetryCallsTheProvidedReconnectAction() async {
        var retryCount = 0
        let model = UnreachableViewModel(reachability: .unreachableHost) {
            retryCount += 1
        }

        await model.retry()

        XCTAssertEqual(retryCount, 1)
        XCTAssertFalse(model.isRetrying)
    }
}
