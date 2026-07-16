---
status: active
last-verified: 2026-07-16
---

# Dashboard 3ペインレイアウトと幅クランプ

> **このファイルの役割**: メインウィンドウの3ペイン（左サイドバー・detail・右インスペクター）構成と、ペイン幅の決定・クランプ機構の現行仕様。
> **書かないもの**: なぜこの方式か（→ adr/0090）、空状態カードの中身（→ dashboard-empty-state-agent-cards.md）、使用量サイドバーの内容（→ claude-usage-supply.md）。

## 構成（Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/）

- `DashboardView.navigationShell` — `GeometryReader` + `HStack(spacing: 0)` の自前3ペイン。左=`DashboardSidebarView`（`.frame(width: sidebarWidth)`）、中央=`DashboardDetailView`（`.frame(maxWidth: .infinity)`）、右=`UsageSidebarView`（`.frame(width: inspectorWidth)`）。表示状態は `AppRouter.sidebarVisible` / `inspectorVisible`。
- `PaneWidthPolicy` — ペイン幅決定の単一の正本（純関数）。定数 `sidebarMinWidth=240` / `inspectorMinWidth=240` / `detailMinWidth=400`。`clamped(windowWidth:sidebarVisible:inspectorVisible:sidebarWidth:inspectorWidth:) -> PaneWidths` は「縮小方向のみ・インスペクター優先で縮小・両 min で床止め・非表示ペインはパススルー」（意味論の理由は ADR 0090）。
- クランプの発火点（`DashboardView.applyPaneWidthClamp`）: ①`onChange(of: geometry.size.width, initial: true)`（ウィンドウリサイズ・起動直後）②`router.sidebarVisible` の `onChange` ③`router.inspectorVisible` の `onChange`。適用後は `sidebarWidthAtDragStart` / `inspectorWidthAtDragStart` も同期する（次のドラッグ開始基準の飛び防止）。
- リサイズグリップ（`ResizeGripView` のオーバーレイ）: ドラッグ中のクランプは従来式のまま（`min(max(min幅, 提案), 窓幅 − detailMin − 反対側)`）。定数は `PaneWidthPolicy` を参照。

## テスト

- 受け入れ（凍結）: `AcceptancePaneWidthPolicyTests.swift` — 定数凍結・縮小のみ・インスペクター優先・床止め・パススルーの境界値と総性質。
- 白箱: `PaneWidthPolicyWhiteboxTests.swift`。
- ランタイム描画: `DashboardPaneClampRuntimeTests.swift` — 実 `DashboardView` を `NSHostingView` でホストし、900pt（クランプ 260/240・右サイドバー完全表示・カード縦積み）と 1400pt（無クランプ 280/300・横並び）の参照 PNG を `/tmp/dashboard-both-sidebars-*.png` へ出力。`ImageRenderer` は `ScrollView` 内容と `onChange` 更新を描画できないため使わない。

## 前提・境界

- ウィンドウ幅 882pt（= 240+400+240+区切り2）未満は両ペイン min 床止めのまま理論上あふれ得る（許容。ADR 0090）。
- `TrailingTopBarLayout.occupiedWidthForUsageLayout` の凍結シグネチャ（usageAvailableWidth 契約）はこの機構と独立に維持。
