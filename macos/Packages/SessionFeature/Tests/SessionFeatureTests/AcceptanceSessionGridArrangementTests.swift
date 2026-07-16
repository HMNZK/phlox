// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — グリッドの N×N 固定化と配置モデル SessionGridArrangement。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面（未実装の間はコンパイル赤＝red 状態）:
// - sessionGridDimensions: fixed は常に (k, k)（auto は現行維持）
// - struct SessionGridArrangement（Region / placements / init(size:)）
// - reconciled(with:) / move(_:toCell:) / swap(_:_:) / canMergeRight(_:) / canMergeDown(_:) /
//   mergeRight(_:) / mergeDown(_:) / unmerge(_:) / isFree(cell:) / placement(at:)
// - enum SessionGridAction

import Foundation
import Testing
import AgentDomain
import DesignSystem
@testable import SessionFeature

@Suite("SessionGridArrangement acceptance (task-1)")
struct AcceptanceSessionGridArrangementTests {

    /// 決定論的な固定 SessionID（末尾 12 桁に n を埋め込む）。
    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    // MARK: - sessionGridDimensions（N×N 固定化）

    @Test func dimensions_fixedIsAlwaysSquare() {
        #expect(sessionGridDimensions(columns: .two, sessionCount: 3) == (2, 2))
        #expect(sessionGridDimensions(columns: .three, sessionCount: 2) == (3, 3))
        #expect(sessionGridDimensions(columns: .one, sessionCount: 3) == (1, 1))
        #expect(sessionGridDimensions(columns: .four, sessionCount: 1) == (4, 4))
        #expect(sessionGridDimensions(columns: .four, sessionCount: 20) == (4, 4))
    }

    @Test func dimensions_autoUnchanged() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 3) == (2, 2))
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 5) == (3, 2))
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 9) == (3, 3))
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 0) == (1, 1))
    }

    // MARK: - reconciled（未配置の充填・不在の除去・既配置の保持）

    @Test func reconciled_placesUnplacedInListOrderToLowestFreeCells() throws {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1), sid(2)])
        #expect(try #require(a.placement(at: 0)).id == sid(0))
        #expect(try #require(a.placement(at: 1)).id == sid(1))
        #expect(try #require(a.placement(at: 2)).id == sid(2))
        #expect(a.isFree(cell: 3))
    }

    @Test func reconciled_dropsSessionsBeyondCapacity() {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1), sid(2), sid(3), sid(4)])
        #expect(a.placements.count == 4)
        #expect(a.placements[sid(4)] == nil)
        #expect(a.placements[sid(0)] != nil)
    }

    @Test func reconciled_removesAbsentSessions() {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        let b = a.reconciled(with: [sid(1)])
        #expect(b.placements[sid(0)] == nil)
        #expect(b.placements[sid(1)] != nil)
    }

    @Test func reconciled_preservesExistingMergedRegions() throws {
        let merged = try #require(
            SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)]).mergeRight(sid(0))
        )
        let re = merged.reconciled(with: [sid(0), sid(1)])
        #expect(try #require(re.placement(at: 0)).region.colSpan == 2)
        #expect(try #require(re.placement(at: 2)).id == sid(1))
    }

    // MARK: - move（空マスへ 1×1 配置・結合解消）

    @Test func move_placesAtEmptyCellAsSingle() throws {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        let moved = try #require(a.move(sid(0), toCell: 3))
        #expect(try #require(moved.placement(at: 3)).id == sid(0))
        #expect(moved.isFree(cell: 0))
    }

    @Test func move_returnsNilForOccupiedCell() {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        #expect(a.move(sid(0), toCell: 1) == nil)
    }

    @Test func move_dissolvesMergedRegion() throws {
        let merged = try #require(
            SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)]).mergeRight(sid(0))
        )
        // s0 は cell0-1（colSpan2）、s1 は cell2 へ退避済み、cell3 は空き。
        let moved = try #require(merged.move(sid(0), toCell: 3))
        let p3 = try #require(moved.placement(at: 3))
        #expect(p3.region.colSpan == 1)
        #expect(p3.region.rowSpan == 1)
        #expect(moved.isFree(cell: 0))
        #expect(moved.isFree(cell: 1))
    }

    // MARK: - swap（Region 丸ごと交換・span 込み）

    @Test func swap_exchangesRegionsWholesale() throws {
        let merged = try #require(
            SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)]).mergeRight(sid(0))
        )
        // s0 = cell0-1（colSpan2）、s1 = cell2（1×1）。swap で領域が丸ごと入れ替わる。
        let swapped = try #require(merged.swap(sid(0), sid(1)))
        #expect(try #require(swapped.placement(at: 0)).id == sid(1))
        #expect(try #require(swapped.placement(at: 0)).region.colSpan == 2)
        #expect(try #require(swapped.placement(at: 2)).id == sid(0))
        #expect(try #require(swapped.placement(at: 2)).region.colSpan == 1)
    }

    @Test func swap_returnsNilWhenSessionMissing() {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0)])
        #expect(a.swap(sid(0), sid(9)) == nil)
    }

    // MARK: - mergeRight / mergeDown（吸収・決定論的退避・端の範囲外）

    @Test func mergeRight_relocatesOccupantToLowestFreeCell() throws {
        // size=2: s0=cell0, s1=cell1。mergeRight(s0) は cell1 を吸収し s1 を最小の空きセル cell2 へ退避。
        let base = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        #expect(base.canMergeRight(sid(0)))
        let merged = try #require(base.mergeRight(sid(0)))
        let p0 = try #require(merged.placement(at: 0))
        #expect(p0.id == sid(0))
        #expect(p0.region.colSpan == 2)
        #expect(p0.region.rowSpan == 1)
        #expect(try #require(merged.placement(at: 1)).id == sid(0))   // 覆いの解決
        #expect(try #require(merged.placement(at: 2)).id == sid(1))   // 決定論的退避先
        #expect(merged.isFree(cell: 3))
    }

    @Test func mergeRight_returnsNilWhenNoFreeCellForOccupant() {
        // 全 4 マス占有。cell1 の占有者を退避させる空きが無いので nil。
        let full = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1), sid(2), sid(3)])
        #expect(full.canMergeRight(sid(0)) == false)
        #expect(full.mergeRight(sid(0)) == nil)
    }

    @Test func mergeRight_returnsNilAtRightEdge() throws {
        var a = SessionGridArrangement(size: 2).reconciled(with: [sid(0)])
        a = try #require(a.move(sid(0), toCell: 1))   // cell1 = 右端列
        #expect(a.canMergeRight(sid(0)) == false)
        #expect(a.mergeRight(sid(0)) == nil)
    }

    @Test func mergeDown_expandsRowSpanAbsorbingEmptyCell() throws {
        // size=2: s0=cell0, s1=cell1。cell2 は空きなので退避不要で吸収。
        let base = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        let merged = try #require(base.mergeDown(sid(0)))
        let p0 = try #require(merged.placement(at: 0))
        #expect(p0.region.rowSpan == 2)
        #expect(p0.region.colSpan == 1)
        #expect(try #require(merged.placement(at: 2)).id == sid(0))
        #expect(merged.isFree(cell: 3))
    }

    @Test func mergeDown_returnsNilAtBottomEdge() throws {
        var a = SessionGridArrangement(size: 2).reconciled(with: [sid(0)])
        a = try #require(a.move(sid(0), toCell: 2))   // cell2 = 下端行
        #expect(a.canMergeDown(sid(0)) == false)
        #expect(a.mergeDown(sid(0)) == nil)
    }

    // MARK: - unmerge（1×1 へ戻す）

    @Test func unmerge_returnsToSingleAtAnchor() throws {
        let merged = try #require(
            SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)]).mergeRight(sid(0))
        )
        let un = try #require(merged.unmerge(sid(0)))
        let p0 = try #require(un.placement(at: 0))
        #expect(p0.region.colSpan == 1)
        #expect(p0.region.rowSpan == 1)
        #expect(un.isFree(cell: 1))
    }

    @Test func unmerge_returnsNilForSingleCell() {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0)])
        #expect(a.unmerge(sid(0)) == nil)
    }

    // MARK: - isFree / placement

    @Test func isFree_and_placement_resolveCoverage() throws {
        let a = SessionGridArrangement(size: 2).reconciled(with: [sid(0)])
        #expect(a.isFree(cell: 0) == false)
        #expect(a.isFree(cell: 1) == true)
        #expect(try #require(a.placement(at: 0)).id == sid(0))
        #expect(a.placement(at: 1) == nil)
    }

    // MARK: - Codable / Equatable（凍結面）

    @Test func arrangement_isCodableRoundtrippable() throws {
        let a = try #require(
            SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)]).mergeRight(sid(0))
        )
        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(SessionGridArrangement.self, from: data)
        #expect(decoded == a)
    }

    @Test func gridAction_casesAreEquatable() {
        #expect(SessionGridAction.moveToCell(sid(0), cell: 3) == .moveToCell(sid(0), cell: 3))
        #expect(SessionGridAction.swap(sid(0), sid(1)) == .swap(sid(0), sid(1)))
        #expect(SessionGridAction.mergeRight(sid(0)) == .mergeRight(sid(0)))
        #expect(SessionGridAction.mergeDown(sid(0)) != .mergeRight(sid(0)))
        #expect(SessionGridAction.unmerge(sid(0)) == .unmerge(sid(0)))
    }

    // MARK: - Codable の不変条件検証（レビュー指摘の恒久化：復元時に不正配置を拒否）

    @Test func decoding_rejectsOverlappingRegions() throws {
        struct Payload: Encodable {
            let size: Int
            let placements: [SessionID: SessionGridArrangement.Region]
        }
        let payload = Payload(size: 2, placements: [
            sid(0): .init(anchor: 0, rowSpan: 1, colSpan: 2),  // cell 0,1 を被覆
            sid(1): .init(anchor: 1, rowSpan: 1, colSpan: 1),  // cell 1 と重複
        ])
        let data = try JSONEncoder().encode(payload)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SessionGridArrangement.self, from: data)
        }
    }

    @Test func decoding_rejectsOutOfBoundsRegion() throws {
        struct Payload: Encodable {
            let size: Int
            let placements: [SessionID: SessionGridArrangement.Region]
        }
        let payload = Payload(size: 2, placements: [
            sid(0): .init(anchor: 1, rowSpan: 1, colSpan: 2),  // col1 + colSpan2 = 3 > 2（盤外）
        ])
        let data = try JSONEncoder().encode(payload)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SessionGridArrangement.self, from: data)
        }
    }

    // MARK: - reconcile：既存結合が容量を圧迫した状態での溢れ drop（カバレッジ補強）

    @Test func reconciled_dropsWhenPreservedMergeReducesCapacity() throws {
        // size=2 で s0 を colSpan2（cell0-1）へ結合 → 空きは cell2,3 の2枠。
        let merged = try #require(
            SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)]).mergeRight(sid(0))
        )
        let re = merged.reconciled(with: [sid(0), sid(1), sid(2), sid(3)])
        #expect(try #require(re.placement(at: 0)).region.colSpan == 2)  // 既結合は保持
        #expect(try #require(re.placement(at: 2)).id == sid(1))          // list 順・index 昇順
        #expect(try #require(re.placement(at: 3)).id == sid(2))
        #expect(re.placements[sid(3)] == nil)                           // 容量超過で drop
    }
}
