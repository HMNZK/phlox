// task-14 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-14.md — グリッド表示セッションの選択式フィルタ。

import Foundation
import Testing
@testable import DashboardFeature

private struct Item: Identifiable, Equatable {
    let id: String
}

@Test func gridSessionSelection_nilSelectionShowsAll() {
    let items = [Item(id: "a"), Item(id: "b"), Item(id: "c")]
    #expect(GridSessionSelectionFilter.apply(items, selection: nil) == items)
}

@Test func gridSessionSelection_selectionFiltersPreservingOrder() {
    let items = [Item(id: "a"), Item(id: "b"), Item(id: "c")]
    #expect(GridSessionSelectionFilter.apply(items, selection: ["c", "a"]) == [Item(id: "a"), Item(id: "c")])
}

@Test func gridSessionSelection_normalizedDropsUnknownIDs() {
    #expect(GridSessionSelectionFilter.normalized(selection: ["a", "ghost"], existing: ["a", "b"]) == ["a"])
}

@Test func gridSessionSelection_normalizedEmptyBecomesNil() {
    #expect(GridSessionSelectionFilter.normalized(selection: ["ghost"], existing: ["a", "b"]) == nil)
    #expect(GridSessionSelectionFilter.normalized(selection: nil, existing: ["a"]) == nil)
}
