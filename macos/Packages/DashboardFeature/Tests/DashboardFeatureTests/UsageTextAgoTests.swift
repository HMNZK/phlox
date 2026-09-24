import Foundation
import Testing
@testable import DashboardFeature

// 07 U1: 取得した直後や取得時刻がわずかに先でも「0 秒後に取得」と書かない（読み上げのラベルで出ていた）。

@Test func agoNeverSaysInTheFuture() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let ja = Locale(identifier: "ja_JP")

    #expect(UsageText.ago(now, now: now, locale: ja) == "1秒前")
    #expect(UsageText.ago(now.addingTimeInterval(0.5), now: now, locale: ja) == "1秒前")
    #expect(UsageText.ago(now.addingTimeInterval(-120), now: now, locale: ja) == "2分前")
    #expect(UsageText.ago(now.addingTimeInterval(-120), now: now, locale: Locale(identifier: "en_US")) == "2m ago")
}
