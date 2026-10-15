---
status: active
last-verified: 2026-10-15
---

# Dashboard 3ペインレイアウトと幅クランプ

> **このファイルの役割**: メインウィンドウの3ペイン（左サイドバー・detail・右インスペクター）構成と、ペイン幅の決定・クランプ機構の現行仕様。
> **書かないもの**: なぜこの方式か（→ adr/0090）、空状態カードの中身（→ dashboard-empty-state-agent-cards.md）、使用量サイドバーの内容（→ claude-usage-supply.md）。

## 構成（Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/）

- `DashboardView.navigationShell` — `GeometryReader` + `HStack(spacing: 0)` の自前3ペイン。左=`DashboardSidebarView`（`.frame(width: sidebarWidth)`）、中央=`DashboardDetailView`（`.frame(maxWidth: .infinity)`）、右=`InspectorView`（ファイルツリー。`.frame(width: inspectorWidth)`）。表示状態は `AppRouter.sidebarVisible` / `inspectorVisible`。
- `PaneWidthPolicy` — ペイン幅決定の単一の正本（純関数）。定数 `sidebarMinWidth=240` / `inspectorMinWidth=240` / `detailMinWidth=400`。`clamped(windowWidth:sidebarVisible:inspectorVisible:sidebarWidth:inspectorWidth:) -> PaneWidths` は「縮小方向のみ・インスペクター優先で縮小・両 min で床止め・非表示ペインはパススルー」（意味論の理由は ADR 0090）。
- クランプの発火点（`DashboardView.applyPaneWidthClamp`）: ①`onChange(of: geometry.size.width, initial: true)`（ウィンドウリサイズ・起動直後）②`router.sidebarVisible` の `onChange` ③`router.inspectorVisible` の `onChange`。適用後は `sidebarWidthAtDragStart` / `inspectorWidthAtDragStart` も同期する（次のドラッグ開始基準の飛び防止）。
- リサイズグリップ（`ResizeGripView` のオーバーレイ）: ドラッグ中のクランプは従来式のまま（`min(max(min幅, 提案), 窓幅 − detailMin − 反対側)`）。定数は `PaneWidthPolicy` を参照。

## 中央の下部パネル（ADR 0196・0197）

`SessionTabsContainer` がタブ列より下の中央本文を `BottomPanelContainer` で包み、その下だけに `BottomPanelView` を配置する。左右のペインと `.safeAreaInset` の使用量バーはこの容器の外側。開閉・フォーカスは ウィンドウごとの `DashboardView` の `BottomPanelState` に分離し、親の `DashboardView` は開閉・ドラッグの値を読まない。ドラッグ中は境界の予告線だけを更新して内容の高さを固定し、終了時だけ保存・レイアウト更新する。

`BottomPanelLayout` はタブ列より下の本文高（使用量バーは親の safeAreaInset）から最大 `min(本文高×0.7, 本文高−200)` を計算する。通常は120pt以上、320pt未満の中央では上の内容の確保を優先する。保存した希望高はウィンドウを縮めても書き換えず、広げると復元する。高さ変更は VoiceOver の増減操作と、境界へのフォーカス中の上下キーでも行える。

プロジェクトは単体では選択中のプロジェクト、グリッドでは選択中のタイルのプロジェクト。選択タイルの装飾を変更しない。表示メニューは `FocusedValues` で操作中のウィンドウへ接続する。操作はヘッダー右端、表示メニュー、⌘J（ADR 0200）。ヘッダーの開閉ボタンは閉じているときに透明な面・補助文字色、開いているときにインスペクタと同じ選択の塗り・主文字色を使う（ADR 0198）。アクセシビリティ表現は Toggle とし、実際の開閉を AXValue のオン／オフで公開する（[ADR 0199](../adr/0199-file-rename-menu-and-accessibility-state.md)）。表示モード・下部パネル・インスペクタは別々の ToolbarItem として公開し、読み上げ名を互いに継承させない。開いたことがないプロジェクトの再起動メニューは無効、起動済みなら閉じていても再起動して開く。

シェル終了の案内と再起動ボタンは、ライトでも暗いターミナルの面の内側に置く。専用の DesignSystem トークンで補助文字・ボタンの面・文字・縁を揃える。

`ToolbarInteractionTests` は標準タイトルバーの AX 操作要素を日英・明暗で検査する。下部パネル、インスペクタの順で開閉し、各押下後に両者の状態と AXCheckBox の AXValue を確認する。VoiceOver の音声出力は未検証。

下部パネルのテストは `BottomPanelTests` と `DesignSnapshotRenderTests.bottomPanelSnapshots` に置く。

## テスト

- 受け入れ（凍結）: `AcceptancePaneWidthPolicyTests.swift` — 定数凍結・縮小のみ・インスペクター優先・床止め・パススルーの境界値と総性質。
- 白箱: `PaneWidthPolicyWhiteboxTests.swift`。
- ランタイム描画: `DashboardPaneClampRuntimeTests.swift` — 実 `DashboardView` を `NSHostingView` でホストし、900pt（クランプ 260/240・右サイドバー完全表示・カード縦積み）と 1400pt（無クランプ 280/300・横並び）の参照 PNG を `/tmp/dashboard-both-sidebars-*.png` へ出力。`ImageRenderer` は `ScrollView` 内容と `onChange` 更新を描画できないため使わない。

## 前提・境界

- ウィンドウ幅 882pt（= 240+400+240+区切り2）未満は両ペイン min 床止めのまま理論上あふれ得る（許容。ADR 0090）。
- `TrailingTopBarLayout.occupiedWidthForUsageLayout` の凍結シグネチャ（usageAvailableWidth 契約）はこの機構と独立に維持。
