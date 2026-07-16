---
status: active
last-verified: 2026-07-14
---

# グリッドビューのレイアウト要件（固定 N×N・自由配置・セル結合）

ダッシュボードのグリッドビュー（固定列モード）が満たすべき要件。決定の理由は ADR 0084、現行の実装構造は architecture/session-grid-layout.md を参照。

## 用語

- **固定モード**: `GridColumns` が `one`〜`four`（選択値 k）。本要件の対象。
- **auto モード**: `GridColumns.auto`（`⌈√N⌉` 列）。本要件の対象外（現行挙動を維持）。
- **配置（arrangement）**: どのセッションが k×k 格子のどのセル（またはどの結合領域）に居るかの状態。表示層の状態で、`sessionNodes` の順序とは独立。
- **結合（merge）**: 隣接する空きセルを取り込み、1 セッションのタイルを複数セル分の大きさで表示すること。

## 機能要件

- **FR1（常に k×k）**: 固定モードで k を選ぶと、セッション数に依らず常に k×k の正方グリッドを表示する。行数はセッション数から算出しない。
- **FR2（空マスは空表示）**: セッションが k² に満たないセルは空欄（空セル）として描画する（末尾行の空セルを省略しない）。
- **FR3（左上から配置）**: 初期配置はセッションを row-major 順で左上から詰める。
- **FR4（自由移動）**: ユーザーはセッションを空きセルへ移動、または他セッションと交換（swap）できる。移動は `sessionNodes` の順序に影響しない。
- **FR5（セル結合）**: ユーザーは右クリックのコンテキストメニューから、隣接する空き方向へ「右と結合／下と結合」、および「解除」ができる。結合したタイルは複数セル分（内側スペーシングを含めて連続）の矩形で描画する。
- **FR6（あふれ）**: セッション数が容量（k² から結合で消費した分を引いた数）を超える場合、超過分は表示しない。表示対象の絞り込みは既存の `GridSessionPicker` に委ねる。
- **FR7（サイズ別永続化）**: 配置・結合は k ごとに独立して永続化する（キー `phlox.grid.arrangement.<k>`）。k を切り替えると各 k の配置が復元される。

## 非機能要件

- **NFR1（決定論）**: 同一入力に対する配置は決定論的（辞書反復順に依存しない）。永続データの復元時は盤内・互いに素（Region 非重複）を検証し、破損データは拒否して空配置へフォールバックする。
- **NFR2（描画ハング非在）**: view body 評価中に観測対象状態を変更しない（`gridArrangement(size:)` は純読み取り、配置変更はユーザー操作イベント経由のみ）。SwiftUI の無限再無効化ハング（ADR 0010）を構造的に回避する。

## 受け入れテスト（凍結・不変）

- `Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionGridArrangementTests.swift`（配置モデル）
- `Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionGridCellFramesTests.swift`（セル/結合矩形）
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/AcceptanceGridArrangementVMTests.swift`（VM の配置 API・永続化）

## スコープ外

- auto モードの挙動変更（現行の `⌈√N⌉` 列・swap D&D・`persistSessionOrder` を維持）。
