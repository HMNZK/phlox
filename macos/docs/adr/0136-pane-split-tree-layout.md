---
status: accepted
last-verified: 2026-07-28
supersedes: 0084-grid-view-fixed-nxn-free-placement-merge.md
---

# ADR 0136: グリッドビューを「n 分岐の分割ツリー」で作り直す（k×k 等分割盤を撤去）

## 文脈

ADR 0084 の k×k 等分割盤（`SessionGridArrangement`）では、分割比が **1/k の整数倍**しか作れない。
そのため「左半分に1枚・右半分を上下に2枚」のような、ごく普通の要望が表現できなかった。
セル結合（右と結合／下と結合）を足しても、作れる比率の集合は 1/k 刻みのままで、
表現力の不足がそのまま UI の制約になっていた。

ユーザーの指示は「今のグリッドビューのことは完全に忘れて 0 から再設計する」。
パッチではなく、レイアウトモデルそのものを置き換える。

## 決定

レイアウトモデルを **n 分岐の分割ツリー**（BSP の一般形）にする。

```swift
indirect enum PaneNode {
    case leaf(id: PaneID, session: SessionID)
    case split(PaneSplit)   // axis, children: [PaneNode], weights: [Double]
}
```

k×k 等分割は、このモデルの部分集合（すべての weight が等しい2段の split）になる。

以下は本 ADR に含まれる設計判断で、いずれもゲート①でユーザーが選択したか、
実測・独立レビューで裏づけたもの。

### 1. 2分岐 BSP ではなく n 分岐にする

2分岐だと「3等分の列」が入れ子比 (1/3, 2/3) → (1/2, 1/2) になり、
**1本目の分割線を動かすと3列すべてが動く**。n 分岐なら隣接する2枚の間だけで比を再配分できる。
tmux / i3 / VS Code と同じ操作モデル。

**捨てた案**: ①等分割格子のままトラック幅を可変にする（CSS Grid 風）— 1本のトラックを動かすと
行/列全体が動き直感に反する ②任意矩形の自由配置（キャンバス）— 隙間・重なり・整列補助が必要で
スコープが跳ね上がる。ゲート①でユーザーが「入れ子の分割で十分」を選択。

### 2. 分割線ドラッグは「ゴースト方式」（ドラッグ中はレイアウトを確定しない）

ADR 0116 が実測で確定しているとおり、タイル幅が毎フレーム変わると非 Lazy な VStack 配下の
transcript 全件が CoreText で再 typeset され、メインスレッドが **470〜643ms** ハングする。
既存の緩和策（`GridChatColumn` の整形幅凍結）は `NSWindow` の live-resize 通知に依存しており、
**アプリ内の分割線ドラッグでは発火しない**。

そこで、ドラッグ中は半透明の分割線ゴーストだけを動かし、マウスアップ時に1回だけ weights を確定する。
ハングの**発生条件が構造的に成立しない**。

**捨てた案**: ①ドラッグ中も追従させ、アプリ独自の live-drag 信号を全タイルへ配って整形幅を凍結する
— 凍結中は表示がクリップされて崩れ、配線が広範になる ②量子化・デバウンス — ADR 0116 が実測で不十分と結論済み。

この保証を機械検査可能にするため、ドラッグ状態機械を SwiftUI に触れない純粋型
（`PaneDividerDragMachine` / `PaneDividerInteraction`）へ切り出し、
**`changed` は決してレイアウト操作を返さない**ことをテストで列挙的に固定した。
ビューの書き方に依存しない防壁になる。

### 3. 描画は「フラットな ZStack ＋ 絶対配置」を維持する

タイルのビュー identity・階層位置が変わると `NSViewRepresentable` の `coordinator.hostingView` が
別 SwiftUI parent に attach されて競合し、**タイルが空白になる**（旧 `SessionGridView` にも同じ注意書きがあった）。

分割ツリーは**矩形の計算にだけ**使い、描画は「セッション ID → 矩形」のフラットな絶対配置＋
`.id(session.id)` を保つ。ツリーを `HStack` / `VStack` の入れ子として描かない。
分割線ハンドルは ZStack の**最後**（最前面）に置く。AppKit の `NSView`（`TerminalView`）は
SwiftUI の overlay より前面に出るため、`.overlay` で置いた分割線は `.pty` タイルの境界で掴めない。

### 4. 絞り込みはレイアウトを書き換えない（永続ツリーと実効ツリーの2層）

旧実装は `gridSessionSelection` の `didSet` で配置を reconcile していたため、
一時的に隠したセッションの位置が失われた。

新モデルでは**永続ツリーは隠れているセッションの leaf も保持**し、
描画時に可視集合で刈り込んだ**実効ツリー**を導出する（`pruned(visible:)`）。
永続ツリーからの leaf 削除は、セッション自体が消えたときだけ。

### 5. 分割線の同一性は「index」でなく「両隣のノード ID」で表す

フェーズ1のタスク分解を独立レビュー（Codex, read-only）にかけて着手前に発見した実バグ経路。
永続ツリー `[A, B, C]` から B を隠した実効ツリー `[A, C]` の `index: 0` は A|C 境界だが、
永続ツリーの `index: 0` は A|B 境界を指す。ビューは実効ツリーの ID を VM へ渡すため、
**絞り込み中に分割線を動かすと別の分割線が動く**。

`PaneDividerID = { split, leading, trailing }`（両隣のノード ID）とし、leaf にも安定 `PaneID` を持たせる。
刈り込み・正規化で生き残ったノードの ID は再生成しない。

### 6. 旧データは移行しない

新キー `phlox.grid.paneLayout` を新設し、旧キー `phlox.grid.arrangement.<k>` からの移行は行わない。
等分割格子 → 比率ツリーの意味的対応が一意に決まらないため。旧キーは削除せず放置する。

### 7. その他の数値

- 最小ペイン長: 幅 **240pt** / 高さ **160pt**（ヘッダー・transcript・composer が最低限収まる目安）。
  領域が最小値の2倍未満のときは 50:50 に倒す。
- 分割線の比率下限 `minimumDividerFraction = 0.05`。各 weight の絶対下限にはしない
  （下限にすると 21 子以上の split が作れなくなる）。
- タイル端へのドロップで分割と判定する帯 `PaneDropZone.edgeFraction = 0.25`（中央は常に 50%×50% 残る）。

## 結果

- `GridColumns`（1/2/3/4/auto）のセグメントは UI から消え、**レイアウトプリセット選択メニュー**に置き換わった
  （自動整列 / 1枚 / 2列 / 3列 / 2段 / 3段 / 2×2 / 左1枚＋右に2枚 / 上1枚＋下に2枚）。
- 旧モデル（`SessionGridArrangement` / `SessionGridCellFrames` / `SessionGridLayout` / `GridColumns` /
  `GridArrangementStore`）は撤去した。撤去した受け入れテストと、性質を引き継いだ新テストの対応は下表。
- 現行の構造は architecture/session-pane-layout.md、要件は specs/pane-layout.md を参照。

### 撤去した受け入れテストと引き継ぎ先

| 撤去した旧テスト | 検証していた性質 | 引き継ぎ先 |
|---|---|---|
| `AcceptanceSessionGridArrangementTests` | k×k 盤の move/swap/merge/unmerge と reconcile の純粋性 | `AcceptancePaneTreeTests`（分割ツリーの insert/remove/swap/setDivider/equalize/reconciled） |
| `SessionGridArrangementWhiteboxTests` | 同上の内部不変条件 | `PaneTreeWhiteboxTests` |
| `AcceptanceSessionGridCellFramesTests` | セル矩形・結合領域矩形が bounds と spacing に整合する | `AcceptancePaneTreeTests` の幾何節（最外周が bounds に接する・隣接間隔がちょうど spacing・退化ケース） |
| `SessionGridCellFramesWhiteboxTests` | 同上の内部計算 | `PaneTreeGeometry` の白箱テスト |
| `SessionGridLayoutTests` | `sessionGridDimensions` の列数決定 | `PaneLayoutPresets`（`.balanced` が ⌈√N⌉ 列を作る）を `AcceptancePaneLayoutPresetMenuTests` で検証 |
| `AcceptanceGridArrangementVMTests` | VM が配置を保持・reconcile・永続化する | `AcceptancePaneLayoutVMTests` / `ContractPaneLayoutPersistenceTests` |
| `GridArrangementVMWhiteboxTests` | 同上の内部経路 | `AcceptancePaneLayoutVMTests` |
| `AcceptanceGridSelectionFocusTests` の枠ポリシー配線テスト | タイルの枠決定が `GridTileBorderPolicy` 経由であること | 同テストを維持し、走査先を `SessionGridView.swift` → `PaneLayoutView.swift` に付け替えた |

### 受容した残余（直さないと決めたもの）

- **浮動小数の ULP レベルの誤差**: 分割線位置に 5.82e-11 pt の偏差が出る経路があるが、契約の許容差
  0.5pt より10桁小さく実害が無いため修正しない。
- **削除カスケードで保存が複数回走る**: プロジェクト削除など複数セッションを一操作で消すと、
  セッション数と同じ回数 `paneLayoutStore.save` が走る。reconcile は冪等で最終状態は正しく、
  UserDefaults の書き込みはメモリ上の操作のため受容する。バッチ境界の導入は削除カスケード自体の
  restructure が必要でスコープ外。
- **タイルのドラッグ移動・分割**: ヘッダーの `.draggable` はゼロ距離 `DragGesture` より先に適用する必要がある
  （順序が逆だとドラッグセッションが開始しない。最小の SwiftUI アプリで A/B 実測）。
  この順序はソーススキャンの受け入れテストで固定した。なお合成マウスイベントでは Phlox 内でドラッグを
  開始させられず、実機の手動操作でのみ動作確認した。
