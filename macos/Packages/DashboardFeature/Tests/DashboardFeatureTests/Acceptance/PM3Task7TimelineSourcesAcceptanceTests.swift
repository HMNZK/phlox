import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// PM3 task-7 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-7.md — makeSources の ID→ノード解決（TeamTimelineNodeOrdering.ordered）の
// セマンティクス凍結。O(n) 化しても出力（順序・欠落・重複の扱い）が1ビットも変わらないこと。
// 性能タスクのため着手時 green（naive 実装の凍結）が正しい。

private struct PM3Task7Item: Equatable {
    let id: SessionID
    let tag: String
}

@Suite(.serialized)
struct PM3Task7TimelineSourcesAcceptanceTests {

    @Test
    func ordered_preservesIDOrderAndDropsMissing() {
        let a = SessionID(), b = SessionID(), c = SessionID(), missing = SessionID()
        let items = [
            PM3Task7Item(id: c, tag: "c"),
            PM3Task7Item(id: a, tag: "a"),
            PM3Task7Item(id: b, tag: "b"),
        ]
        let result = TeamTimelineNodeOrdering.ordered(ids: [a, missing, c, b], items: items, id: \.id)
        #expect(result.map(\.tag) == ["a", "c", "b"], "ids の順序保存と欠落 id の除去が崩れている")
    }

    @Test
    func ordered_duplicateItemIDsTakeFirstOccurrence() {
        let dup = SessionID()
        let items = [
            PM3Task7Item(id: dup, tag: "first"),
            PM3Task7Item(id: dup, tag: "second"),
        ]
        let result = TeamTimelineNodeOrdering.ordered(ids: [dup], items: items, id: \.id)
        #expect(result.map(\.tag) == ["first"], "items 側の重複 id は最初の一致を採る（現行セマンティクス）")
    }

    @Test
    func ordered_duplicateRequestedIDsEmitEachTime() {
        let x = SessionID(), y = SessionID()
        let items = [PM3Task7Item(id: x, tag: "x"), PM3Task7Item(id: y, tag: "y")]
        let result = TeamTimelineNodeOrdering.ordered(ids: [x, y, x], items: items, id: \.id)
        #expect(result.map(\.tag) == ["x", "y", "x"], "ids 側の重複はその回数だけ出力する（現行セマンティクス）")
    }

    @Test
    func ordered_emptyInputs() {
        let x = SessionID()
        let items = [PM3Task7Item(id: x, tag: "x")]
        #expect(TeamTimelineNodeOrdering.ordered(ids: [], items: items, id: \.id).isEmpty)
        #expect(TeamTimelineNodeOrdering.ordered(ids: [x], items: [PM3Task7Item](), id: \.id).isEmpty)
    }

    // 大きめ入力での同値性（naive 実装との突き合わせ）。O(n) 化後も完全一致すること。
    @Test
    func ordered_matchesNaiveSemanticsOnLargeShuffledInput() {
        var items: [PM3Task7Item] = []
        var ids: [SessionID] = []
        for i in 0..<300 {
            let id = SessionID()
            items.append(PM3Task7Item(id: id, tag: "t\(i)"))
            ids.append(id)
        }
        // 前半を逆順・一部欠落・一部重複させた要求列。
        var requested = Array(ids.prefix(150).reversed())
        requested.append(contentsOf: [ids[10], ids[10], SessionID()])
        let naive = requested.compactMap { target in items.first { $0.id == target } }
        let result = TeamTimelineNodeOrdering.ordered(ids: requested, items: items, id: \.id)
        #expect(result == naive, "naive セマンティクスとの完全一致が崩れている")
    }
}
