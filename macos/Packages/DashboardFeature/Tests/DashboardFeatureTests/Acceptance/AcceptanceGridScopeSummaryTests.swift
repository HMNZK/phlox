// task-31（UX-04）の受け入れテスト。
//
// ベースラインでの red 理由: `GridScopeSummary` と `GridScopeSummary.make(projectName:visibleCount:hasSessionSelection:)`、
// `GridScopeSummary.ClearAction` は本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: グリッドの表示範囲と実表示件数を 1 箇所の要約で作り、解除ラベルと該当なし文言もそこから出す。
// 件数は候補数ではなく visibleCount。区切りは全角中黒 U+30FB。

import Foundation
import Testing
@testable import DashboardFeature

@Suite("task-31: grid scope summary")
struct AcceptanceGridScopeSummaryTests {
    @Test("title は trim 済み非空。nil・空・空白のみは既定「すべてのプロジェクト」")
    func titleDefaultsAndTrims() {
        #expect(GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false).title == "UI検証A")
        #expect(GridScopeSummary.make(projectName: "  UI検証A  ", visibleCount: 2, hasSessionSelection: false).title == "UI検証A")
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false).title == "すべてのプロジェクト")
        #expect(GridScopeSummary.make(projectName: "", visibleCount: 3, hasSessionSelection: false).title == "すべてのプロジェクト")
        #expect(GridScopeSummary.make(projectName: "   ", visibleCount: 0, hasSessionSelection: false).title == "すべてのプロジェクト")
    }

    @Test("countText は max(0, visibleCount) に「件」を付け、負数は 0 にクランプする")
    func countTextAndNegativeClamp() {
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false).countText == "3件")
        #expect(GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false).countText == "2件")
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 0, hasSessionSelection: false).countText == "0件")
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 1, hasSessionSelection: true).countText == "1件")
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: -1, hasSessionSelection: false).countText == "0件")
        #expect(GridScopeSummary.make(projectName: "A", visibleCount: -8, hasSessionSelection: true).countText == "0件")
    }

    @Test("text は title と countText を全角中黒 U+30FB でつなぐ")
    func textUsesIdeographicMiddleDot() {
        let scoped = GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false)
        #expect(scoped.text == "UI検証A・2件")
        #expect(scoped.text == "\(scoped.title)\u{30FB}\(scoped.countText)")

        let all = GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false)
        #expect(all.text == "すべてのプロジェクト・3件")

        let trimmed = GridScopeSummary.make(projectName: "  UI検証A  ", visibleCount: 2, hasSessionSelection: false)
        #expect(trimmed.text == "UI検証A・2件")

        let clamped = GridScopeSummary.make(projectName: nil, visibleCount: -3, hasSessionSelection: false)
        #expect(clamped.text == "すべてのプロジェクト・0件")
    }

    @Test("isEmpty は visibleCount <= 0（負数も含む）")
    func isEmptyWhenVisibleCountIsNotPositive() {
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 0, hasSessionSelection: false).isEmpty)
        #expect(GridScopeSummary.make(projectName: "UI検証A", visibleCount: -1, hasSessionSelection: true).isEmpty)
        #expect(!GridScopeSummary.make(projectName: nil, visibleCount: 1, hasSessionSelection: false).isEmpty)
        #expect(!GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: true).isEmpty)
    }

    @Test("emptyMessage は isEmpty の 3 分岐。非 empty では常に nil")
    func emptyMessageThreeBranchesAndNilWhenNotEmpty() {
        #expect(
            GridScopeSummary.make(projectName: nil, visibleCount: 0, hasSessionSelection: true).emptyMessage
                == "選択中のセッションはこの範囲にありません"
        )
        #expect(
            GridScopeSummary.make(projectName: "UI検証A", visibleCount: 0, hasSessionSelection: true).emptyMessage
                == "選択中のセッションはこの範囲にありません"
        )
        #expect(
            GridScopeSummary.make(projectName: "UI検証A", visibleCount: 0, hasSessionSelection: false).emptyMessage
                == "このプロジェクトに表示できるセッションがありません"
        )
        #expect(
            GridScopeSummary.make(projectName: "  UI検証A  ", visibleCount: -2, hasSessionSelection: false).emptyMessage
                == "このプロジェクトに表示できるセッションがありません"
        )
        #expect(
            GridScopeSummary.make(projectName: nil, visibleCount: 0, hasSessionSelection: false).emptyMessage
                == "表示できるセッションがありません"
        )
        #expect(
            GridScopeSummary.make(projectName: "   ", visibleCount: 0, hasSessionSelection: false).emptyMessage
                == "表示できるセッションがありません"
        )

        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false).emptyMessage == nil)
        #expect(GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false).emptyMessage == nil)
        #expect(GridScopeSummary.make(projectName: "UI検証A", visibleCount: 1, hasSessionSelection: true).emptyMessage == nil)
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 4, hasSessionSelection: true).emptyMessage == nil)
    }

    @Test("clearActions は projectFilter → sessionSelection の順。label は契約どおり")
    func clearActionsOrderAndLabels() {
        #expect(GridScopeSummary.ClearAction.projectFilter.label == "プロジェクトの絞り込みを解除")
        #expect(GridScopeSummary.ClearAction.sessionSelection.label == "セッションの選択を解除")

        #expect(
            GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false).clearActions
                == [.projectFilter]
        )
        #expect(
            GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: true).clearActions
                == [.sessionSelection]
        )
        #expect(
            GridScopeSummary.make(projectName: "UI検証A", visibleCount: 1, hasSessionSelection: true).clearActions
                == [.projectFilter, .sessionSelection]
        )
        #expect(
            GridScopeSummary.make(projectName: "  UI検証A  ", visibleCount: 0, hasSessionSelection: true).clearActions
                == [.projectFilter, .sessionSelection]
        )
        #expect(GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false).clearActions == [])
        #expect(GridScopeSummary.make(projectName: "", visibleCount: 0, hasSessionSelection: false).clearActions == [])
        #expect(GridScopeSummary.make(projectName: "   ", visibleCount: 0, hasSessionSelection: false).clearActions == [])

        let both = GridScopeSummary.make(projectName: "UI検証A", visibleCount: 1, hasSessionSelection: true)
        #expect(both.clearActions.map(\.label) == ["プロジェクトの絞り込みを解除", "セッションの選択を解除"])
    }

    @Test("accessibilityText は text に、clearActions の label を「。」で連結する")
    func accessibilityTextConcatenatesLabelsWithIdeographicFullStop() {
        #expect(
            GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false).accessibilityText
                == "UI検証A・2件。プロジェクトの絞り込みを解除"
        )
        #expect(
            GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: true).accessibilityText
                == "すべてのプロジェクト・3件。セッションの選択を解除"
        )
        #expect(
            GridScopeSummary.make(projectName: "UI検証A", visibleCount: 1, hasSessionSelection: true).accessibilityText
                == "UI検証A・1件。プロジェクトの絞り込みを解除。セッションの選択を解除"
        )
        #expect(
            GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false).accessibilityText
                == "すべてのプロジェクト・3件"
        )
        let none = GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false)
        #expect(none.accessibilityText == none.text)
        #expect(!none.accessibilityText.contains("。"))
    }

    @Test("GridScopeSummary と ClearAction は Equatable")
    func summariesAndClearActionsAreEquatable() {
        let a = GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false)
        let b = GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: false)
        #expect(a == b)
        #expect(a == GridScopeSummary.make(projectName: "  UI検証A  ", visibleCount: 2, hasSessionSelection: false))

        #expect(a != GridScopeSummary.make(projectName: "UI検証B", visibleCount: 2, hasSessionSelection: false))
        #expect(a != GridScopeSummary.make(projectName: "UI検証A", visibleCount: 1, hasSessionSelection: false))
        #expect(a != GridScopeSummary.make(projectName: "UI検証A", visibleCount: 2, hasSessionSelection: true))
        #expect(
            GridScopeSummary.make(projectName: nil, visibleCount: 3, hasSessionSelection: false)
                != GridScopeSummary.make(projectName: "UI検証A", visibleCount: 3, hasSessionSelection: false)
        )

        #expect(GridScopeSummary.ClearAction.projectFilter == .projectFilter)
        #expect(GridScopeSummary.ClearAction.sessionSelection == .sessionSelection)
        #expect(GridScopeSummary.ClearAction.projectFilter != .sessionSelection)
    }
}
