// 契約の正本: tasks/task-4.md — Usage バーの統一（Cursor バケット表記・残量色）。
// このファイルは PM が凍結する受け入れテスト。実装役は編集禁止（ハーネス欠陥は PM 承認の上でのみ修理可）。

import Foundation
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("Acceptance: Usage バー統一（task-4）")
struct AcceptanceUsageBarUnificationTests {
    /// Cursor の auto バケットは「Auto」表記（旧「Auto+Composer」）。id と usedPercent の意味は不変。
    @Test func cursorのautoバケットはAuto表記() throws {
        let json = Data(#"{"planUsage":{"autoPercentUsed":42.5,"apiPercentUsed":10.0}}"#.utf8)
        let buckets = try CursorUsageProvider.buckets(fromResponseData: json)

        #expect(buckets.count == 2)
        #expect(buckets[0].id == "auto")
        #expect(buckets[0].label == "Auto")
        #expect(buckets[0].usedPercent == 42.5)
        #expect(buckets[1].id == "api")
        #expect(buckets[1].label == "API")
        #expect(buckets[1].usedPercent == 10.0)
    }

    /// 残量に応じた統一色の正本は UsageDisplay.usageColor（statusline rate_color 移植）。
    /// 消費 0%（残量 100%）＝緑、消費 100%（残量 0%）＝赤 の両端を保護する（関数自体の変更禁止）。
    @Test func usageColorの両端は緑と赤() {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
        }
        #expect(UsageDisplay.usageColor(for: 0) == rgb(90, 200, 130))    // 残量 100% = 緑
        #expect(UsageDisplay.usageColor(for: 100) == rgb(240, 50, 55))   // 残量 0% = 赤
    }
}
