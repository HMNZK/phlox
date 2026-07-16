---
status: active
last-verified: 2026-07-14
---

# セッショングリッドのレイアウト（固定 N×N・自由配置・結合）

グリッドビューの固定列モード（`GridColumns.one`〜`four`）は、選択値 k を一辺とする **k×k 格子**でセッションを描画する。ユーザーはセルを移動・結合でき、配置は k ごとに永続化される。auto モードは別経路（`⌈√N⌉` 列・swap D&D）で本ドキュメントの対象外。

## コンポーネント

| 層 | 型 / 関数 | 役割 |
|---|---|---|
| モデル | `SessionGridArrangement`（SessionFeature） | k×k 盤の配置状態。`placements: [SessionID: Region]`、`Region { anchor, rowSpan, colSpan }`。move/swap/mergeRight/mergeDown/unmerge/reconciled を**純粋関数**（`Self?` を返し、事前条件不成立時は nil）で提供 |
| アクション | `SessionGridAction`（同上） | `moveToCell / swap / mergeRight / mergeDown / unmerge`。UI から VM への操作の値表現 |
| レイアウト | `sessionGridCellFrames(size:bounds:spacing:)` / `sessionGridRegionRect(region:size:bounds:spacing:)`（同上） | k×k の各セル矩形（row-major）と、結合領域の矩形（内側スペーシングを含めて連続）を計算 |
| 描画 | `SessionGridView.fixedGrid`（同上） | `arrangement` を受け取り、各セルに配置があれば `SessionGridTile`、無ければ `EmptySessionGridCell` を `sessionGridRegionRect` で配置 |
| 永続化 | `GridArrangementStore`（DashboardFeature） | k 別に配置を保存/復元。キー `phlox.grid.arrangement.<k>`。復元時に `arrangement.size == 要求 size` を照合し不一致は nil |
| 状態 | `DashboardViewModel.gridArrangements: [Int: SessionGridArrangement]` | サイズ 1〜4 の配置を常時保持（イベント側で reconcile 済み） |
| 配線 | `DashboardDetailView`（DashboardFeature） | 固定モード時に `arrangement: gridArrangement(size: k)` と `onGridAction: handleGridAction(_:size:)` を `SessionGridView` へ渡す |

## データフロー

**読み取り（描画）**: `DashboardDetailView` は `gridColumns.fixedCount`（固定モードなら k、auto なら nil）を見て、固定時のみ `viewModel.gridArrangement(size: k)` を `SessionGridView` に渡す。`gridArrangement(size:)` は `gridArrangements[size]` を返すだけの**純読み取り**で、状態更新も永続化もしない（view body から呼ばれるため）。

**書き込み（操作）**: セルの D&D・結合メニューは `SessionGridAction` を `onGridAction` へ送り、`DashboardViewModel.handleGridAction(_:size:)` が配置モデルの対応メソッドを呼ぶ。成功時（`Self?` が非 nil）だけ可視セッションで `reconciled` し、`gridArrangements[size]` を更新して `GridArrangementStore.save` する。ここが**唯一の書き込み経路**。

**整合（reconcile）**: 可視セッション集合が変わるイベント側で `reconcileGridArrangements` がサイズ 1〜4 の全配置を可視集合に合わせて再整合する（消えたセッションを配置から除去し、結合容量が可視数を下回る場合は縮約）。トリガはセッション追加/削除・グリッドフィルタ変更・プロジェクト削除・復元。**サイズ変更（k の切替）自体はトリガではない**——全サイズが常に reconcile 済みのため、view が新しい k で読むだけで正しい配置が得られる。復元時は `reloadAndReconcileGridArrangements` が k 別ストアから読み直してから reconcile する。

## 不変条件

- `placements` の各 `Region` は盤内（`0 ≤ anchor < size²`、行/列 span が盤に収まる）かつ互いに素（重複しない）。Codable の `init(from:)` がこれを検証し、破損データは `DecodingError` で拒否する。
- view body（`SessionGridView.fixedGrid` と `gridArrangement(size:)`）は `@Observable` 状態を mutate しない。配置の変更は必ずユーザー操作イベント（`onGridAction`）を起点とする（ADR 0010 の無限再無効化ハザード回避）。
- 固定モードの移動・結合は `sessionNodes` の順序に影響しない（配置は表示層の独立状態）。

決定の背景は ADR 0084 を参照。
