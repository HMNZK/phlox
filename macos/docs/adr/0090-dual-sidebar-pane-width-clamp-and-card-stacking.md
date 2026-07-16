---
status: active
last-verified: 2026-07-16
---

# 0090: 両サイドバー表示のペイン幅クランプと狭幅カード縦積みのレイアウト方針

## 文脈

Dashboard のメインウィンドウは自前の3ペイン実装（`GeometryReader` + `HStack`。左サイドバー・detail・右インスペクター=使用量サイドバー）で、左右のペイン幅は `@State` の固定値を `.frame(width:)` で与えている。幅の再クランプは**リサイズグリップのドラッグ中にしか走らず**、さらに空状態のエージェント選択カード列（横 `HStack`・各カード minWidth 148+padding）が detail に**圧縮不能な最小幅**を作っていた。両サイドバーを表示して合計幅がウィンドウ幅を超えると、HStack があふれて**末尾の右サイドバーが右端で見切れる**（回復経路なし）。

## 決定

1. **幅決定を純関数 `PaneWidthPolicy.clamped` に一元化**し、ウィンドウリサイズ（`onChange(of: geometry.size.width, initial: true)`）とサイドバー開閉トグル（`sidebarVisible`/`inspectorVisible` の `onChange`）でも発火させる。意味論は「**縮小方向のみ**（ウィンドウ拡大でユーザー設定幅を勝手に広げない）・**インスペクター優先で縮小**（補助情報であり、ナビゲーションと作業領域を優先）・**両者 min（240/240）で床止め**（budget = 窓幅 − detailMin 400）」。クランプ後は `*AtDragStart` も同期する。
2. **エージェント選択カードは、利用可能幅が必要幅（`AgentStartCardsLayoutPolicy.requiredHorizontalWidth`）を下回ったら縦積み**に切り替える（`shouldStackVertically`）。縦積み時は `ScrollView` で全カードへ到達可能にし、ヘッダーの上端揃えは許容する。
3. **幅計測は「ビュー全体を `GeometryReader` で包んで得る提案幅」を正とする**。`GeometryReader` は提案サイズを採用し、子のはみ出しで膨張しないため、計測がオーバーフローにフィードバックされない。

## 棄却した代替案

- **高さ0の全幅計測行（`Color.clear`+`onGeometryChange`）を膨張しうるコンテナの兄弟に置く方式** — 当初契約の推奨だったが、SwiftUI の `VStack` は配置時に**膨張後の幅を flexible な兄弟へ再提案**するため、計測値が `max(提案幅, コンテンツ最小幅)` に張り付き、狭幅（バグ発生時）に限って提案幅を測れない。独立レビューが `ImageRenderer` 実測（pane=300/400/500 → いずれも measured=572=必要幅）で反証した。
- **`ViewThatFits`** — 判定ロジックがフレームワーク内に隠れ、純関数ポリシーが死蔵になって受け入れテストと実挙動が乖離するため不採用。
- **`NavigationSplitView`/`.inspector()` への移行** — 3ペインの自前実装（トップバーオーバーレイ・リサイズグリップとの統合）を保つため今回のスコープ外。
- **ウィンドウ最小幅（882pt = 240+400+240+2）の強制** — 882pt 未満では両ペイン min 床止めのまま理論上あふれ得るが許容し、導入は見送り（必要になれば別 ADR）。

## 結果

- 実行時検証（`NSHostingView` ホスト描画）: 窓 900pt で 280/300→260/240 へ自動クランプされ右サイドバーが右端まで表示、detail 400pt でカードは縦積み。窓 1400pt ではクランプなし・横並び。
- 検証機構の教訓: `ImageRenderer` は macOS の `ScrollView` 内容を描画せず、`onChange`/`@State` の更新ループも回らない。**ビュー配線の検証は `NSHostingView` + `cacheDisplay`**（実 SwiftUI ランタイム）を使う。純関数テストの green だけでは配線の不具合を検出できないため、実ビュー描画の配線テストを受け入れ配下に常設した。
- 契約面: `PaneWidthPolicy` / `AgentStartCardsLayoutPolicy` の定数・シグネチャは受け入れテスト（`AcceptancePaneWidthPolicyTests` / `AcceptanceAgentStartCardsLayoutTests`）が凍結する。
