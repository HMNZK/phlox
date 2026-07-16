---
status: active
last-verified: 2026-07-14
---

# ADR 0084: グリッドビューの N×N 固定化・セッション自由配置・セル結合

## 文脈

グリッドビューの固定列モード（GridColumns の `one`〜`four`）は、選択値を「列数」として解釈していた。このため 3 セッションで「2」を選ぶと `⌈3/2⌉=2` 行 × 2 列のうち末尾行の空セルを省いて「上 2 マス・下 1 マス」になっていた（`SessionGridView` の「末尾行の空セルを置かない」挙動）。

ユーザーの要望は次のとおり:
- 「N」選択時は**セッション数に依らず常に N×N の正方グリッド**にする（「2」→ 2×2）。
- セッションが N² に満たないマスは**空欄**にする。
- セッションは**左上から順に配置**する。
- ユーザーが**セッションを任意のマスへ移動**できる。
- ユーザーが**隣接マスを結合**して 1 つの大きなマスとして表示できる（例: 2×2・3 セッションで、左列 2 マス＋右列は上下結合の 1 マス）。

## 決定

固定モードを「選択値 k を一辺とする常に k×k 格子」へ変更する。具体的な設計判断（ゲート①でユーザー承認）:

- **常に k×k**: `sessionGridDimensions` の固定分岐を `(k, k)` 固定にし、末尾空セル省略をやめる。旧挙動（末尾行の空セルを置かない）を**意図的に覆す**。
- **あふれ（n > k²）**: 先頭 k² 個だけ表示する。表示対象の絞り込みは既存の `GridSessionPicker` に委ねる（新規 UI を足さない）。
- **配置は表示層の状態**: 固定モードの移動・結合は `sessionNodes` の順序（auto モードの `persistSessionOrder`）に影響させない。配置は独立した表示状態として持つ。
- **結合 UI**: セルの右クリック（コンテキストメニュー）で「右と結合／下と結合／解除」。
- **永続化はグリッドサイズごとに独立**: 配置・結合は k ごとに別キー `phlox.grid.arrangement.<k>` で保存する（k を変えると別の配置になる）。
- **auto モードは現行維持**: `⌈√N⌉` 列・swap D&D・`persistSessionOrder` をそのまま残す。固定モードだけが新経路。

## 結果

- 新しい配置モデル `SessionGridArrangement`（`Region { anchor, rowSpan, colSpan }` と `placements: [SessionID: Region]`）を SessionFeature に追加。move/swap/mergeRight/mergeDown/unmerge/reconciled を純粋関数として実装。
- k×k のセル矩形計算 `sessionGridCellFrames` と結合矩形 `sessionGridRegionRect` を追加（結合矩形は内側スペーシングを含めて連続させる）。
- `GridArrangementStore`（k 別永続化）と、`DashboardViewModel` の `gridArrangement(size:)`（純読み取り）・`handleGridAction(_:size:)`（唯一の書き込み経路）・イベント側の `reconcileGridArrangements` を追加。
- **決定論の担保**: 配置の復元（Codable decode）で盤内・互いに素（Region の非重複）を検証し、不正データを `DecodingError` で拒否する。`placement(at:)` が辞書反復順に依存しないことを保証するため（ADR 0010 と同じ「決定論が最重要」の系）。
- **ハング非在の担保**: view body（`SessionGridView.fixedGrid`）は `gridArrangement(size:)` を**純読み取り**でのみ呼び、`@Observable` 状態を body 評価中に mutate しない。書き込みは常にユーザー操作の `onGridAction` コールバック経由に限る。これは「body 評価中の state 変更 → 無限再無効化ハング」（ADR 0010・`GraphHost.flushTransactions` 固着）の再発を構造的に防ぐため。

構造は architecture/session-grid-layout.md を参照。

## 検討した代替案

- **旧「末尾空セル省略」を維持**: ユーザー要望（常に N×N・空マス許容）に真っ向から反する。却下。
- **全 k で単一の配置状態を共有**: k を変えると結合・移動が別サイズの盤へ持ち越されて破綻する（2×2 の結合は 3×3 では無意味）。k 別独立保存を採用して却下。
- **結合 UI をドラッグ主体にする**: 右クリックメニューより発見性・実装コストの両面で不利。コンテキストメニューを採用。

## 関連

- ADR 0010（SwiftUI 描画中 state 変更による無限再無効化ハザードと純関数化）— 本 ADR の「ハング非在の担保」の根拠。
- ADR 0027（グリッドのワークスペースフィルタ）— 表示対象の絞り込み経路を共有。
