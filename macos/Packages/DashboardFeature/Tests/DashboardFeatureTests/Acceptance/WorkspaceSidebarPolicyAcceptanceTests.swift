// task-13 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-13.md — サイドバーの相対時刻ラベルとプロジェクトアイコン表示規則。

import Foundation
import Testing
@testable import DashboardFeature

@Test func workspaceSidebar_relativeTime_boundaries() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func label(_ seconds: TimeInterval) -> String {
        SidebarRelativeTime.label(from: base, to: base.addingTimeInterval(seconds))
    }
    #expect(label(0) == "今")
    #expect(label(59) == "今")
    #expect(label(60) == "1分")
    #expect(label(59 * 60) == "59分")
    #expect(label(60 * 60) == "1時間")
    #expect(label(23 * 3600) == "23時間")
    #expect(label(24 * 3600) == "1日")
    #expect(label(29 * 86_400) == "29日")
    #expect(label(30 * 86_400) == "1か月")
    #expect(label(364 * 86_400) == "12か月")
    #expect(label(365 * 86_400) == "1年")
    #expect(label(800 * 86_400) == "2年")
}

@Test func workspaceSidebar_relativeTime_futureTimestampClampsToNow() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(SidebarRelativeTime.label(from: base.addingTimeInterval(120), to: base) == "今")
}

@Test func workspaceSidebar_projectIconPolicy_hiddenByDefault_dimWhenUnseenCompletion() {
    #expect(ProjectIconPolicy.opacity(hasUnseenCompletion: false) == nil)
    #expect(ProjectIconPolicy.opacity(hasUnseenCompletion: true) == 0.45)
}
