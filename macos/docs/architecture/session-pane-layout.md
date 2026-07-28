---
status: active
last-verified: 2026-07-28
---

# セッションペインのレイアウト（n 分岐の分割ツリー）

> **このファイルの役割**: グリッドビューのレイアウトを支える分割ツリー（`PaneTree`）の現行構造 —
> モデル・幾何計算・操作・描画・永続化の各層と、それらの境界。
> **書かないもの**: なぜ等分割盤でなく分割ツリーなのか（→ adr/0135）、満たすべき要件（→ specs/pane-layout.md）、
> ウィンドウの3ペイン幅（→ dashboard-pane-layout.md）。

グリッドビューは、セッションを **n 分岐の分割ツリー**のとおりに並べる。
旧 k×k 等分割盤（`SessionGridArrangement` / `GridColumns`）は撤去済み（ADR 0135）。

## コンポーネント

| 層 | 型 / 関数 | 役割 |
|---|---|---|
| モデル | `PaneTree` / `PaneNode` / `PaneSplit`（SessionFeature/PaneLayout） | `leaf(id:session:)` と `split(axis:children:weights:)` の再帰木。`init(root:)` が正規化してから不変条件を検証し、破れていれば throw する。`schemaVersion = 1`、`Codable` |
| 識別子 | `PaneID` / `PaneDividerID` | 全ノードが安定 `PaneID` を持つ。分割線は `{ split, leading, trailing }`（両隣のノード ID）で識別する。index では絞り込み時に別の分割線を指してしまう（ADR 0135 §5） |
| 幾何 | `PaneTree.frames(in:spacing:)` → `PaneLayoutFrames`（`tiles` / `dividers`） | 累積エッジの差分でタイル矩形を出す。実効間隔は `max(0, min(spacing, length/(n-1)))` で、隙間が領域に収まらない退化ケースでもタイルが bounds の外へ出ない |
| 操作 | `PaneTreeOperations`（`pruned` / `removing` / `swapping` / `inserting(_:splitting:edge:)` / `insertingIntoLargestPane` / `settingDivider` / `equalizing` / `reconciled`） | すべて純粋関数（`PaneTree` を返す）。`settingDivider` は leading と trailing の合計取り分の中だけで再配分し、間に隠れた子の weight は変えない |
| プリセット | `PaneLayoutPreset` / `PaneLayoutPresetMenu` | 9 種（`balanced` / `single` / `columns2` / `columns3` / `rows2` / `rows3` / `grid2x2` / `mainLeftStackRight` / `mainTopStackBottom`）。素の形で受け止める数を超えた分は最大ペインの分割で足す |
| 操作の値表現 | `PaneLayoutAction`（`setDivider` / `insertBySplitting` / `swap` / `equalize` / `applyPreset`） | UI から VM への操作。UI 側に閾値や確定ロジックを置かない |
| ドラッグ | `PaneDividerDragMachine` / `PaneDividerInteraction` | SwiftUI / AppKit を import しない純粋型。`changed` は**必ず nil を返す**（＝ドラッグ中はレイアウトを更新できない） |
| ドロップ判定 | `PaneDropZone.target(for:in:)` | タイル内のローカル座標から `.swap` / `.split(edge)` を決める。4辺への距離を**絶対値**の比で測り、点がタイルの外なら常に最も近い辺への split |
| 描画 | `PaneLayoutView` / `PaneDividerHandleView`（SessionFeature） | フラットな `ZStack` にタイルを絶対配置し、分割線ハンドルを最前面に置く |
| 殻 | `SessionGridView` | `PaneLayoutView` を包み、余白と背景だけを与える薄いラッパ |
| 永続化 | `PaneLayoutStore`（DashboardFeature） | キー `phlox.grid.paneLayout`。保存失敗時も throw せず、壊れたデータは nil を返して既定へフォールバック |
| 配線 | `DashboardViewModel.paneLayout` / `paneLayoutForDisplay()` / `handlePaneLayoutAction(_:)` / `reconcilePaneLayout(persist:)` | 永続ツリーの保持と、描画用の実効ツリーの導出 |

## データモデルの不変条件

`PaneTree.init(root:)` が正規化してから検証する。破れていれば `PaneTreeError` を throw する。

1. `split` の子は 2 個以上（1 個なら正規化でその子に畳む）。同じ軸の split が入れ子なら平坦化する。
2. `weights` は子と同数・全て正・合計 1。
3. 同じ `SessionID` の leaf は 1 つだけ。`PaneID` はツリー全体で一意。
4. 刈り込み・正規化で生き残ったノードの `PaneID` は再生成しない（分割線の同一性が保たれる）。

## 永続ツリーと実効ツリー（2層）

- **永続ツリー** = `DashboardViewModel.paneLayout`。**隠れているセッションの leaf も保持する**。
- **実効ツリー** = `paneLayoutForDisplay()` = 永続ツリーを可視集合で `pruned(visible:)` したもの。描画専用。

`paneLayoutForDisplay()` は view body から呼ばれるため、**状態更新も永続化もしない**（ADR 0010）。

永続ツリーへの書き込み経路は 2 系統だけ:

1. **ユーザー操作** — `handlePaneLayoutAction(_:)`
2. **セッションの増減** — `reconcilePaneLayout(persist:)`（追加・削除・プロジェクト削除・ワークスペース変更）

**絞り込み（表示セッション選択・ワークスペース絞り込み）は永続ツリーを書き換えない**。
隠したセッションを戻すと、元の取り分のまま元の位置へ戻る。

起動時の復元中は `layoutRestoreInProgress` が真で、reconcile の結果を書き戻さない。

## 描画の制約（守らないと壊れるもの）

- **ツリーを `HStack` / `VStack` の入れ子として描かない。** `tree.frames()` の結果をフラットな `ZStack` に
  `.frame(width:height:).position(x:y:)` で絶対配置し、各タイルに `.id(session.id)` を付ける。
  タイルの階層位置が変わると `NSViewRepresentable` の attach が競合してタイルが空白になる。
- **分割線ハンドルは ZStack の最後（最前面）に置く。** AppKit の `NSView`（`TerminalView`）は SwiftUI の
  overlay より前面に出るため、`.overlay` で置くと `.pty` タイルの境界で掴めない。
- **ドラッグ中（`onChanged`）にタイルの矩形を変えない。** ドラッグ中に更新してよい `@State` はゴースト位置だけ
  （ADR 0116 の 470〜643ms ハングの再発防止）。ビューは `PaneDividerInteraction` の戻り値が非 nil のときだけ
  `onLayoutAction` を呼ぶ。
- **タイルヘッダーは `.draggable` をゼロ距離 `DragGesture` より先に適用する。** 順序が逆だとゼロ距離の
  DragGesture がマウスダウンを取り切り、ドラッグセッションが開始しない（ADR 0135 の受容残余）。
- `LazyVStack` / `LazyHStack` を使わない（ADR 0030）。`fixedSize` を新規に足さない（ADR 0045 の趣旨）。
- view body 評価中に `@Observable` を変更しない（ADR 0010）。

## 数値

| 値 | 場所 | 意味 |
|---|---|---|
| 240pt / 160pt | `PaneLayoutView.minimumPaneWidth` / `minimumPaneHeight` | 分割線ドラッグのクランプ。領域が最小値の2倍未満なら 50:50 に倒す |
| 0.05 | `PaneTree.minimumDividerFraction` | 分割線操作時の局所クランプ。各 weight の絶対下限にはしない |
| 0.25 | `PaneDropZone.edgeFraction` | 端と判定する帯の割合。中央は常に 50%×50% 残る |
| 8pt | `PaneTreeGeometry.dividerHitThickness` | 分割線の当たり判定の太さ |
| 1600×1000 | `PaneLayoutStore.reconcileBounds` | reconcile 時に「最大のペイン」を選ぶための固定基準サイズ（相対比較にしか使わない） |

## テスト

| ファイル | 固定している性質 |
|---|---|
| `AcceptancePaneTreeTests` | モデルの不変条件・操作の純粋性・幾何（bounds への接触・spacing・退化ケース） |
| `ContractPaneTreeCodableTests` | `Codable` の往復とスキーマ互換 |
| `AcceptancePaneDividerDragTests` / `ContractPaneDividerCommitTests` | `changed` が決してレイアウト操作を返さないこと（ADR 0116 の防壁） |
| `AcceptancePaneLayoutViewTests` | 描画の制約（フラット ZStack・`.id`・禁止修飾子・純粋型経由・`.draggable` の適用順） |
| `AcceptancePaneLayoutVMTests` / `ContractPaneLayoutPersistenceTests` | 永続ツリーと実効ツリーの分離・書き込み経路・永続化の往復 |
| `AcceptancePaneLayoutPresetMenuTests` | プリセットの一覧と幾何、トップバーとグリッドへの配線 |
