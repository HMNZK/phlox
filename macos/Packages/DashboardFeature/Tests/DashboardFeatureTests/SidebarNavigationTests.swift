import Foundation
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature

@Suite("03 Sidebar: ↑↓ と文字入力の頭出し")
struct SidebarNavigationTests {
    private let projectA = SidebarItem.project(ProjectID())
    private let sessionA1 = SidebarItem.session(SessionID())
    private let sessionA2 = SidebarItem.session(SessionID())
    private let projectB = SidebarItem.project(ProjectID())

    private var items: [SidebarItem] { [projectA, sessionA1, sessionA2, projectB] }

    @Test("↓ は見えている並びで次の行、↑ は前の行")
    func stepMovesToNeighbor() {
        #expect(SidebarNavigation.step(from: sessionA1, by: 1, in: items) == sessionA2)
        #expect(SidebarNavigation.step(from: sessionA1, by: -1, in: items) == projectA)
    }

    @Test("端では止まる（巡回しない）")
    func stepStopsAtEnds() {
        #expect(SidebarNavigation.step(from: projectB, by: 1, in: items) == projectB)
        #expect(SidebarNavigation.step(from: projectA, by: -1, in: items) == projectA)
    }

    @Test("未選択（または見えない行を選択中）なら ↓ で先頭、↑ で末尾")
    func stepFromNothingStartsAtEdge() {
        #expect(SidebarNavigation.step(from: nil, by: 1, in: items) == projectA)
        #expect(SidebarNavigation.step(from: .session(SessionID()), by: -1, in: items) == projectB)
    }

    @Test("頭出しは今の行から下へ探し、末尾で先頭へ戻る。大文字小文字は区別しない")
    func typeSelectSearchesDownwardAndWraps() {
        let named: [(item: SidebarItem, name: String)] = [
            (projectA, "phlox-core"), (sessionA1, "Tsubaki"), (sessionA2, "Peony"), (projectB, "mobile-proxy"),
        ]
        #expect(SidebarNavigation.typeSelect("p", from: sessionA1, in: named) == sessionA2)
        #expect(SidebarNavigation.typeSelect("PH", from: projectB, in: named) == projectA)
        #expect(SidebarNavigation.typeSelect("mob", from: nil, in: named) == projectB)
    }

    @Test("名前の途中に含まれるだけでは頭出ししない")
    func typeSelectMatchesPrefixOnly() {
        let named: [(item: SidebarItem, name: String)] = [(projectA, "phlox-core"), (sessionA1, "Tsubaki")]
        #expect(SidebarNavigation.typeSelect("core", from: nil, in: named) == nil)
    }
}

@Suite("03 Sidebar: 畳んだ行の要約")
struct SidebarCollapsedSummaryTests {
    @Test("対応待ちは種類ごとに数え、承認待ち・質問待ち・エラー・無応答の順に並べる")
    func countsAttentionByKindInFixedOrder() {
        let summary = SidebarCollapsedSummary.make([.error, .approval, .running, .approval, .stalled])
        #expect(summary.attention == [
            .init(kind: .approval, count: 2),
            .init(kind: .error, count: 1),
            .init(kind: .stalled, count: 1),
        ])
    }

    @Test("完了の未読は対応待ちとは別に数える（既読の完了は数えない）")
    func countsUnreadSeparately() {
        let summary = SidebarCollapsedSummary.make([.doneUnread, .done, .doneUnread, .question])
        #expect(summary.unread == 2)
        #expect(summary.attention == [.init(kind: .question, count: 1)])
    }

    @Test("待機・実行中・既読の完了だけなら要約は空")
    func quietStatesMakeEmptySummary() {
        #expect(SidebarCollapsedSummary.make([.idle, .running, .done, .starting]).isEmpty)
    }
}

@Suite("03 Sidebar: プロジェクト行の選択とグリッドの表示範囲")
@MainActor
struct SidebarProjectScopeTests {
    @Test("単体表示で行を選ぶと、そのプロジェクトがグリッドの表示範囲にもなる")
    func showProjectInSingleModeAlsoSetsGridScope() {
        let router = AppRouter(viewMode: .single)
        let project = ProjectID()
        router.selectedSession = SessionID()

        router.showProject(project)

        #expect(router.selectedProjectID == project)
        #expect(router.gridFilterProjectID == project)
        #expect(router.selectedSession == nil)
    }

    @Test("↑↓ で同じプロジェクトを選び直しても、グリッドの範囲は外れない")
    func showProjectDoesNotToggleScope() {
        let router = AppRouter(viewMode: .grid)
        let project = ProjectID()

        router.showProject(project)
        router.showProject(project)

        #expect(router.gridFilterProjectID == project)
    }

    @Test("⌘クリックで選択中のプロジェクトを外し、グリッドの範囲を「すべて」に戻す")
    func clearProjectScopeResetsSelectionAndScope() {
        let router = AppRouter(viewMode: .grid)
        let project = ProjectID()
        router.showProject(project)

        router.clearProjectScope()

        #expect(router.selectedProjectID == nil)
        #expect(router.gridFilterProjectID == nil)
        #expect(router.viewMode == .grid)
    }
}

@Suite("03 Sidebar: 経過時間の英語表記")
struct SidebarRelativeTimeEnglishTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let english = Locale(identifier: "en")

    @Test("英語では now / 分 m / 時間 h / 日 d / か月 mo / 年 y の短い表記にする")
    func englishLabelsUseShortUnits() {
        func label(_ seconds: TimeInterval) -> String {
            SidebarRelativeTime.label(from: base, to: base.addingTimeInterval(seconds), locale: english)
        }
        #expect(label(30) == "now")
        #expect(label(5 * 60) == "5m")
        #expect(label(3 * 3600) == "3h")
        #expect(label(2 * 86_400) == "2d")
        #expect(label(60 * 86_400) == "2mo")
        #expect(label(800 * 86_400) == "2y")
    }

    @Test("日本語の表示言語では従来の表記のまま")
    func japaneseLocaleKeepsExistingLabels() {
        let label = SidebarRelativeTime.label(from: base, to: base.addingTimeInterval(3 * 3600), locale: Locale(identifier: "ja"))
        #expect(label == "3時間")
    }
}
