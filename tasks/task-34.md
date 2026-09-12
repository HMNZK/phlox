---
id: task-34
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceHitTargetTests.swift
baseline_commit: 73a66ca
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift
  - docs/agent-output/task-34.md
---

## 目的

UI-04。表示モードボタンの押せる範囲は 26×20pt、サイドバーの＋は 22×22pt、プロジェクト行の「…」「＋」とグリッドタイルの「×」は 20×20pt。
絵柄の大きさは変えず、押せる範囲だけを揃えて広げる。トップバーの 32pt 行と macOS の密度は保つ。キーボード到達性と
フォーカスリング（システム標準）は現状のまま維持し、選択状態（面の塗り）と混同させない。

## 入出力契約

- `Tokens.swift` に追加:
  ```swift
  /// 小さなアイコン操作の押せる範囲。絵柄（DSIconSize）とは別系統。
  public enum DSHitTarget {
      public static let icon: CGFloat = 24            // サイドバー＋/…、タイル×
      public static let modeSegmentWidth: CGFloat = 30
      public static let modeSegmentHeight: CGFloat = 24 // トラック padding 2pt×2 を足して 28pt。行 32pt に収まる
  }
  ```
- 配線:
  - `DashboardTopBarControls.swift` `ModeSegmentButton`: `.frame(width: 26, height: 20)` → `.frame(width: DSHitTarget.modeSegmentWidth, height: DSHitTarget.modeSegmentHeight)`。グリフ `.font(.system(size: 13, weight: .medium))`、`.contentShape(Rectangle())`、`.buttonStyle(.plain)`、背景・hover・help・accessibility 各 modifier は不変。`ViewModeToggle` の `.padding(DSSpacing.xxs)` も不変。
  - `DashboardSidebarView.swift`: `sidebarProjectTitleBar` の＋ `.frame(width: 22, height: 22)`、`ProjectSidebarHeader` の「…」と「＋」 `.frame(width: 20, height: 20)` → いずれも `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon)`。グリフサイズ（`DSIconSize.s`）不変。
  - `PaneLayoutView.swift` `PaneTileView.header` の × `.frame(width: 20, height: 20)` → `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon)`。`.imageScale(.small)` 不変。
- 禁止: `.focusable(`／`.focusEffectDisabled(`／`.accessibilityHidden(` の追加・削除、`DSIconSize` の値変更、絵柄サイズの変更、トップバー `.frame(height: 32)` の変更、他ボタン（設定・エージェント管理・サイドバー/インスペクター切替 28×28）の変更。
- 不変条件: 3 モードボタンの `accessibilityIdentifier("view-mode-…")`／`.isSelected` trait（task-8）、`HoverableIconButtonStyle` の hover 面、task-32 のマーカー・バッジ。

## 成功基準

1. 凍結テスト `AcceptanceHitTargetTests`（DesignSystem）green: `DSHitTarget.icon >= 24`、`modeSegmentHeight >= 24`、`modeSegmentWidth >= modeSegmentHeight`、`modeSegmentHeight + 2 * DSSpacing.xxs <= 32`（行に収まる）、`DSIconSize.s == 10 && DSIconSize.m == 12`（絵柄を大きくしていない指紋）。DesignSystem 全数 green、DashboardFeature／SessionFeature ビルド成功。
2. 配線検査 `.claude/scripts/task34-wiring.rb` OK（`ModeSegmentButton` struct 本文に `DSHitTarget.modeSegmentWidth`／`modeSegmentHeight` の frame と `size: 13` が共存／`DashboardSidebarView.swift` に `DSHitTarget.icon` の frame が 3 箇所以上、`width: 22, height: 22`・`width: 20, height: 20` が残っていない／`PaneLayoutView.swift` の xmark Button 内に `DSHitTarget.icon`、`width: 20, height: 20` 無し／各対象ファイルの `focusable(`・`focusEffectDisabled(`・`accessibilityHidden(` の出現数が基準コミットと同じ／`.frame(height: 32)` が `DashboardTopBarControls.swift` に残る）。
3. PM 目視ゲート（隔離 Debug、自 PID への AX 取得のみ）: AX で `size of button "view-mode-grid"`（または help 一致）が 30×24、サイドバー＋が 24×24、プロジェクト行の＋が 24×24 になること。1440pt と 1024pt でトップバー右側が折り返さず、モードトラックの高さが 28pt 前後で 32pt 行に収まること（スクリーンショット）。プロジェクト行高さの増分が 4pt 以内。AX で `set focused of <グリッド表示ボタン> to true` を自 PID に対して行い、フォーカスリングが選択面（fillSelected）と別に見えること（フォーカス設定が拒否されたら未検証と記録）。

## レビュー観点（Rubric）

- 押せる範囲だけが広がり、絵柄と余白のリズムが変わっていない（密度維持）。
- 隣接する「…」「＋」が 24pt 化しても互いに重ならず、hover 表示の切替が壊れていない。
- フォーカス表示をコードで上書きしていない（システム標準に委ねる方針が保たれている）。
- サイズ数値で規格適合を主張していない（契約は「押しやすさの改善」であり HIG 準拠の断定ではない）。
