---
id: task-34
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceHitTargetTests.swift
baseline_commit: c615c0a
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
  - **差し戻し 1 回目（PM ゲート実測）**: `Menu` + `.menuStyle(.borderlessButton)` では label の `.frame(24)` が AX 枠・押せる範囲に反映されず、行の「…」「＋」は 24×24 化後も AX 枠 20×14 のまま（中心以外の 24pt 枠内クリックでメニューが開かない）。実装役は **AX 枠 24×24 が実測で得られる構成へ変更してよい**（例: `.menuStyle(.button)` + `.buttonStyle(.plain)` に切り替えて label に `.frame(DSHitTarget.icon)`＋`.contentShape(Rectangle())`、または `Menu` 自体へ `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon).contentShape(Rectangle())` を付ける等）。ただしメニュー内容・`help`・`menuIndicator(.hidden)`・hover 時のみ表示する `opacity(actionOpacity)`・`HoverableIconButtonStyle` の見た目（背景面）と同等の hover 表現は維持し、`.contentShape(Rectangle())` の追加は許容する（配線検査は基準以上を許す）。実装役は隔離 Debug をビルドして `/tmp/phlox-t13-visual.SPfR9c/measure-t34.sh` で行の「＋」の AX size と端クリックを実測し、開示レポートに原文を貼ること。
  - **差し戻し 2 回目（PM ゲート実測）**: `.menuStyle(.button)` + `.buttonStyle(.plain)` + Menu 外側 `.frame(24)` で AX 枠 24×24 と端クリックは合格したが、**プロジェクト行（row 1）の AX 高さが 32pt → 40pt** に増えた（`measure-t34.sh` の `row1 size`）。契約の「増分 4pt 以内」を数値化する: **row 1 の高さは 36pt 以下**（task-34 着手前の実測 32pt＋4）。`.menuStyle(.button)` の固有高さ（コントロールの最小高）が行を押し広げているので、例えば `.controlSize(.small)`／`.controlSize(.mini)` の付与、Menu 外側の `.frame(width: 24, height: 24)` の後に `.fixedSize()`、`.frame(..., alignment:)` と `.clipped()`、または `.menuStyle(.borderlessButton)` に戻して Menu 外側に `.frame(24).contentShape(Rectangle())` を付け `.fixedSize()` を外す等を試し、**AX 枠 24×24・端クリック合格・row 1 高さ ≤ 36・見た目（`t34-r1-row1.png` 相当の範囲撮影）で行の余白リズムが崩れない**の 4 つを同時に満たす構成にする（ビルド＋実測は最大 3 回）。
  - **差し戻し 3 回目（ユーザー判断 2026-09-13・案 B）**: スパイク（decision-log 2026-09-12）で `.menuStyle(.button)` 系は全変種で row 1 が 40pt、`.borderlessButton` 系は端クリック不可と判明したため、ユーザー判断で **案 B** を採用する。構成は `docs/agent-output/task-34-r2.patch`（`.menuStyle(.button)` + `.buttonStyle(.plain)` + Menu 外側 `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon).contentShape(Rectangle())`）を基点にし、`ProjectSidebarHeader` の行コンテナ（現行 `DashboardSidebarView.swift:381` 付近の `.padding(.vertical, DSSpacing.xs)`、＋メニューの `.help("このプロジェクトで新規セッションを開始")` 直後の HStack 修飾子）を **`.padding(.vertical, DSSpacing.xxs)`** に変える（リテラル 2 は禁止。`DSSpacing.xxs == 2` は凍結テストが固定）。行の縦余白 4→2 は意図した変更であり、旧「余白のリズムが崩れない」は本行については **row 1 高さ ≤ 36pt** の数値条件へ置き換える（セッション行 `SidebarSessionRow` の `.padding(.vertical, DSSpacing.xs)` は変更しない）。4 条件: AX 枠 24×24・端クリック合格・row 1 高さ ≤ 36・名前とバッジが hover 前後で崩れない。実装役は隔離 Debug をビルドし `measure-t34.sh`／`edge-t34.sh` で実測して開示レポートに原文を貼る（ビルド＋実測は最大 3 回）。
  - `PaneLayoutView.swift` `PaneTileView.header` の × `.frame(width: 20, height: 20)` → `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon)`。`.imageScale(.small)` 不変。
- 禁止: `.focusable(`／`.focusEffectDisabled(`／`.accessibilityHidden(` の追加・削除、`DSIconSize` の値変更、絵柄サイズの変更、トップバー `.frame(height: 32)` の変更、他ボタン（設定・エージェント管理・サイドバー/インスペクター切替 28×28）の変更。
- 不変条件: 3 モードボタンの `accessibilityIdentifier("view-mode-…")`／`.isSelected` trait（task-8）、`HoverableIconButtonStyle` の hover 面、task-32 のマーカー・バッジ。

## 成功基準

1. 凍結テスト `AcceptanceHitTargetTests`（DesignSystem）green: 不等式（`icon >= 24`、`modeSegmentHeight >= 24`、`modeSegmentWidth >= modeSegmentHeight`、`modeSegmentHeight + 2 * DSSpacing.xxs <= 32`）に加えて等値 `icon == 24`・`modeSegmentWidth == 30`・`modeSegmentHeight == 24`・`DSSpacing.xxs == 2`、指紋 `DSIconSize.s == 10 && .m == 12 && .l == 15`（敵対レビュー 3）。DesignSystem 全数 green、DashboardFeature／SessionFeature ビルド成功。
2. 配線検査 `.claude/scripts/task34-wiring.rb` OK（コメント行除去・空白除去後に: `ModeSegmentButton` struct 本文に `.frame(width:DSHitTarget.modeSegmentWidth,height:DSHitTarget.modeSegmentHeight)` が 1 回、`width:26,height:20` 無し、`size:13` あり、`.contentShape(Rectangle())`・`.help(help)`・`.accessibilityAddTraits`・`.pointingHandCursor()`・`.accessibilityIdentifier(identifier)` が残る／`ViewModeToggle` 本文に `.padding(DSSpacing.xxs)` が残る／`DashboardSidebarView.swift` に `.frame(width:DSHitTarget.icon,height:DSHitTarget.icon)` が 3 回以上、`width:22,height:22`・`width:20,height:20` 無し／`PaneLayoutView.swift` の `"xmark"` から直後の `.help(` までの範囲に `.frame(width:DSHitTarget.icon,height:DSHitTarget.icon)` と `.contentShape(Rectangle())` があり `width:20,height:20` 無し（`Button(action:){}` と `Button{}label:{}` の両記法を許容）／3 ファイルの `focusable(`・`focusEffectDisabled(`・`accessibilityHidden(true)`・`.contentShape(Rectangle())`・`.help(` の出現数が基準 `TASK34_BASELINE`（verify スクリプトが固定 SHA を渡す）と同じ／`.frame(height:32)` が `DashboardTopBarControls.swift` の `trailingControls`（現在それを含む本文）に残る）。
3. PM 目視ゲート（隔離 Debug、自 PID への AX 取得と occlusion 検査付き座標クリックのみ。key code は使わない）: AX で `size of button "view-mode-grid"`（または help 一致）が 30×24、サイドバー＋が 24×24、プロジェクト行の＋が 24×24。**端クリック**: グリッド表示ボタンの AX 枠の左上から内側 1pt をクリックしてグリッドへ切り替わること、隣接する単体表示ボタンとの境界の両側 1pt で意図した側だけが切り替わること、プロジェクト行＋の枠端 1pt でメニューが開き「…」が開かないこと（敵対レビュー 8）。1440pt と 1024pt でトップバー右側が折り返さず、モードトラックの高さが 28pt 前後で 32pt 行に収まる（スクリーンショット）。プロジェクト行高さの増分が 4pt 以内で hover 前後に名前・バッジが崩れない。AX で `set focused of <グリッド表示ボタン> to true` を自 PID に対して行い、フォーカスリングが選択面（fillSelected）と別に見え、`perform action "AXPress"` で切り替わること。フォーカス設定が拒否された場合は「キーボード到達性は未検証・未達」として残す（成功扱いにしない）。

## レビュー観点（Rubric）

- 押せる範囲だけが広がり、絵柄と余白のリズムが変わっていない（密度維持）。
- 隣接する「…」「＋」が 24pt 化しても互いに重ならず、hover 表示の切替が壊れていない。
- フォーカス表示をコードで上書きしていない（システム標準に委ねる方針が保たれている）。
- サイズ数値で規格適合を主張していない（契約は「押しやすさの改善」であり HIG 準拠の断定ではない）。
