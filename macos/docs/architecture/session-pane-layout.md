---
status: active
last-verified: 2026-10-24
---

# セッションペインのレイアウト（n 分岐の分割ツリー）

> **このファイルの役割**: グリッドビューのレイアウトを支える分割ツリー（`PaneTree`）の現行構造 —
> モデル・幾何計算・操作・描画・永続化の各層と、それらの境界。
> **書かないもの**: なぜ等分割盤でなく分割ツリーなのか（→ adr/0136）、満たすべき要件（→ specs/pane-layout.md）、
> ウィンドウの3ペイン幅（→ dashboard-pane-layout.md）。

グリッドビューは、セッションを **n 分岐の分割ツリー**のとおりに並べる。
旧 k×k 等分割盤（`SessionGridArrangement` / `GridColumns`）は撤去済み（ADR 0136）。
自動整列は表示対象と利用可能領域から木を導出し、カスタムは保存した全件の木を可視集合で刈り込む。
自動整列とカスタムの分離は[ADR 0218](../adr/0218-grid-automatic-layout-and-custom-state.md)で決定した。

## コンポーネント

| 層 | 型 / 関数 | 役割 |
|---|---|---|
| モデル | `PaneTree` / `PaneNode` / `PaneSplit`（SessionFeature/PaneLayout） | `leaf(id:session:)` と `split(axis:children:weights:)` の再帰木。`init(root:)` が正規化してから不変条件を検証し、破れていれば throw する。`schemaVersion = 1`、`Codable` |
| 識別子 | `PaneID` / `PaneDividerID` | 全ノードが安定 `PaneID` を持つ。分割線は `{ split, leading, trailing }`（両隣のノード ID）で識別する。index では絞り込み時に別の分割線を指してしまう（ADR 0136 §5） |
| 幾何 | `PaneTree.frames(in:spacing:)` → `PaneLayoutFrames`（`tiles` / `dividers`） | 累積エッジの差分でタイル矩形を出す。実効間隔は `max(0, min(spacing, length/(n-1)))` で、隙間が領域に収まらない退化ケースでもタイルが bounds の外へ出ない |
| 操作 | `PaneTreeOperations`（`pruned` / `removing` / `swapping` / `inserting(_:splitting:edge:)` / `insertingIntoLargestPane` / `settingDivider` / `equalizing` / `reconciled`） | すべて純粋関数（`PaneTree` を返す）。`settingDivider` は leading と trailing の合計取り分の中だけで再配分し、間に隠れた子の weight は変えない |
| プリセット | `PaneLayoutPreset` / `PaneLayoutPresetMenu` | 9 種（`balanced` / `single` / `columns2` / `columns3` / `rows2` / `rows3` / `grid2x2` / `mainLeftStackRight` / `mainTopStackBottom`）。素の形で受け止める数を超えた分は最大ペインの分割で足す |
| 自動配置 | `PaneGridLayout.automatic(sessions:viewport:)`（SessionFeature/PaneLayout） | 表示順のID列と利用可能領域から、木とcanvas寸法を純粋に算出する。540×440pt以上、隙間8pt、末尾の空きを直上タイルへ吸収する |
| モード | `GridLayoutState` / `CustomGridLayout`（DashboardFeature） | `automatic(previousCustom:)` または `custom`。カスタムは全件ツリー、プリセット、canvas下限を持つ。モードだけの不整合な保存を避ける |
| 領域 | `GridViewport`（DashboardFeature） | DashboardViewがウィンドウごとに所有する。確定寸法、最新の未確定寸法、ライブリサイズの凍結を扱う。操作中の領域はFocusedValuesからメニューとキー操作へ渡す |
| 操作の値表現 | `PaneLayoutAction`（`setDivider` / `insertBySplitting` / `swap` / `equalize` / `applyPreset`） | UI から VM への操作。UI 側に閾値や確定ロジックを置かない |
| ドラッグ | `PaneDividerDragMachine` / `PaneDividerInteraction` | SwiftUI / AppKit を import しない純粋型。`changed` は**必ず nil を返す**（＝ドラッグ中はレイアウトを更新できない） |
| ドロップ判定 | `PaneDropZone.target(for:in:)` | タイル内のローカル座標から `.swap` / `.split(edge)` を決める。4辺への距離を**絶対値**の比で測り、点がタイルの外なら常に最も近い辺への split |
| 描画 | `PaneLayoutView` / `PaneDividerHandleView`（SessionFeature） | フラットな `ZStack` にタイルを絶対配置し、分割線ハンドルを最前面に置く |
| クリック選択 | `PaneTileClickSelectionPolicy` / `PaneTileClickSelector` / `PaneTileClickObserver` / `PaneTileWindowFrameSource`（SessionFeature） | タイル矩形内の左マウスダウンで即選択する（ADR 0153）。`NSEvent` のローカル監視だが**イベントは無変更で素通し**し、矩形はクリックのたびに backing view から取り直す（キャッシュしない） |
| 殻 | `SessionGridView` | 常設ScrollViewの中で同じ `PaneLayoutView` を描く。余白、canvas寸法、ウィンドウ限定のリサイズ通知を扱う |
| 永続化 | `PaneLayoutStore`（DashboardFeature） | `phlox.grid.layoutState`へモードとカスタムを一括保存。新キーが無い場合だけ旧 `phlox.grid.paneLayout` とプリセットを読み、カスタムとして移行する |
| 配線 | `DashboardViewModel.gridLayoutForDisplay(in:)` / `handlePaneLayoutAction(_:in:)` / `reconcilePaneLayout(persist:)` | 表示集合とサイドバー順からの導出、カスタムへの切り替え、保存、増減を集約する |

## データモデルの不変条件

`PaneTree.init(root:)` が正規化してから検証する。破れていれば `PaneTreeError` を throw する。

1. `split` の子は 2 個以上（1 個なら正規化でその子に畳む）。同じ軸の split が入れ子なら平坦化する。
2. `weights` は子と同数・全て正・合計 1。
3. 同じ `SessionID` の leaf は 1 つだけ。`PaneID` はツリー全体で一意。
4. 刈り込み・正規化で生き残ったノードの `PaneID` は再生成しない（分割線の同一性が保たれる）。

## 自動整列とカスタム

自動配置は `filteredGridSessionNodes(projectID:)` が返す表示対象だけを並べる。
サイドバーのプロジェクト順と親から子の順を、ローカルなforest構築から求める。
既存の `sidebarOrderedSessionIDs` は内部セッションを除外する平坦な配列なので、配置順には使わない。
キャッシュを書き換える `sessionForest(in:)` もbodyからの導出に使わない。

木の根を等幅の列に分け、列の内側を縦へ分ける。
末尾のタイルが2段分を使う場合、その実高さは基本段高の2倍と隙間8ptの和となる。
列ごとに隙間の数が違うため、weightを単純な整数比にせず、この実高さから求める。
番号、隣接探索、境界のキー操作は描画と同じcanvas寸法と隙間を使う。

自動からカスタムへ移るとき、非表示群は可視根と異なる軸の枝へ保持する。
可視IDで刈り込むと元の木へ戻り、操作が受け取った分割線IDも保つ。
単純な最大ペイン分割で非表示群を足すと、同軸の平坦化によって可視比率が変わるため使わない。

`restoreAutomaticGridLayout()` はカスタムを退避して自動へ戻す。
`undoAutomaticGridLayout()` は現在実在するIDに合わせて退避カスタムを復元する。
選択集合と絞り込みは巻き戻さず、終了したセッションも復活させない。
一般的な配置操作の履歴や、会話入力のUndoManagerは追加しない。

## カスタムの永続ツリーと実効ツリー

- **永続ツリー**は `CustomGridLayout.tree`。隠れているセッションのleafも保持する。
- **実効ツリー**はカスタムの全件ツリーを可視集合で `pruned(visible:)` したもの。描画専用。

`gridLayoutForDisplay(in:)` と `paneLayoutForDisplay(in:)` はview bodyから呼ばれるため、状態更新も永続化もしない（ADR 0010）。

永続ツリーへの書き込み経路は 2 系統だけ:

1. **ユーザー操作** — `handlePaneLayoutAction(_:in:)`とモードの切り替え・復元
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
  DragGesture がマウスダウンを取り切り、ドラッグセッションが開始しない（ADR 0136 の受容残余）。
- **タイル選択のためにマウスダウンを消費しない。** クリック選択のローカル監視は受け取った `NSEvent` を
  必ずそのまま返す（`AcceptancePaneTileClickPassthroughTests` が凍結）。飲み込むとアプリ全体のクリックが死ぬ。
- **タイル矩形をキャッシュしない。** `.position` による原点だけの移動では AppKit の `layout()` が呼ばれず、
  push したキャッシュが陳腐化して別セッションを誤選択する（ADR 0153）。
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
| 540pt / 440pt | `PaneGridLayout.minimumTileWidth` / `minimumTileHeight` | 自動整列のタイル外寸下限。カスタムの分割線クランプとは別 |
| 556pt | グリッド時の中央必要幅 | 1タイルの540ptと左右余白各8pt。既存のサイドバー縮退とインスペクター重ね表示へ渡す |

## テスト

| ファイル | 固定している性質 |
|---|---|
| `PaneTreeTests` | モデルの不変条件・操作の純粋性・幾何（bounds への接触・spacing・退化ケース） |
| `PaneTreeCodableTests` | `Codable` の往復とスキーマ互換 |
| `PaneDividerDragTests` | `changed` が決してレイアウト操作を返さないこと（ADR 0116 の防壁） |
| `PaneTileClickSelectionTests` | タイル矩形内クリックでの選択条件（半開区間・選択済みなら非発火・矩形未確定なら非発火） |
| `AcceptancePaneTileClickPassthroughTests` | ローカル監視が左マウスダウンを消費しないこと（ADR 0153 の防壁） |
| `PaneLayoutViewTests` / `PaneLayoutViewHostedTests` | 描画の制約（フラット ZStack・`.id`・禁止修飾子・純粋型経由・`.draggable` の適用順）、スクロール範囲、端末ビューの維持、ウィンドウ別のリサイズ通知 |
| `PaneLayoutVMTests` / `PaneLayoutStoreTests` | 永続ツリーと実効ツリーの分離・書き込み経路・永続化の往復 |
| `PaneLayoutPresetMenuTests` | プリセットの一覧と幾何、トップバーとグリッドへの配線 |
| `PaneGridLayoutTests` | 自動配置の列数・段数・末尾延長・最小寸法・採番・非表示枝保持 |
| `GridAutoLayoutTests` | 保存形式・移行・モード復帰、表示対象とサイドバー順、ウィンドウ別の領域、閉じる操作の採番 |
| `DesignSnapshotRenderTests` | 画面外のDashboard描画とフルHD相当の5枚・6枚の実タイル寸法 |
| `GridMenuHostedTests` | 実際のレイアウトメニューからの自動整列、保存したカスタムの木とcanvasの復元 |
