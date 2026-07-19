---
status: active
last-verified: 2026-07-19
---

# ADR 0099: Usage の鮮度注記は可視テキストを撤去し、鮮度シグナルは dimming のみで表す

> **関係**: [ADR 0039](0039-claude-usage-statusline-terminal-only.md) が定めた「行を消さず鮮度を可視化する」方針のうち、**鮮度注記を可視 `Text` として描画する**部分を本 ADR が覆す（partially supersedes）。ADR 0039 の他の決定（Claude Usage 行を `.unavailable` でも常に表示・stale 時は%を薄く表示・`ClaudeUsageStaleness.note` のロジック自体）は現行のまま。
> **このファイルの役割**: 鮮度注記テキストを画面から外した理由と、鮮度シグナルの残し方。

## 状況

ADR 0039 は Claude Usage の鮮度を「N分前の値」「未取得」等の**可視注記テキスト**（`ClaudeUsageStaleness.note` の戻り値）＋%の淡色化（dimming）の二本立てで表していた。運用で次の実害が出た:

- ときどき「10日前の値」等の古い鮮度注記が出る。
- ヘッダー（`UsageTopBarView`）やサイドバー（`UsageSidebarView`）で、進捗バー/ゲージの**下に注記テキストが挿入されると縦レイアウトが押し上げられ、グラフの描画が崩れる**。

注記テキストは補助的な情報であり、これのためにグラフ本体の描画を崩すのは割に合わない。

## 決定

- Usage の鮮度注記の**可視 `Text` 描画をすべて撤去**する（サイドバー `UsageCLICard` の進捗バー直下1件、`UsageTopBarView` のゲージ分岐・テキスト縮退分岐の2件、計3件）。
- 鮮度シグナルは**%の dimming（淡色化）だけで表す**。`ClaudeUsageStaleness.note(...)` の戻り値は引き続き `isPercentDimmed`/`isDimmed`（＝`staleNote != nil`）の判定に使い、stale 時に%を薄く見せる。ロジック（`ClaudeUsageStaleness`）は不変。
- Claude Usage 行を `.unavailable` でも常に表示する方針（ADR 0039）は維持。ヘッダーの hover help（`chipHelp`）も現状維持。
- あわせてサイドバー Usage カードのヘッダーを、エージェント名のテキストバッジ（`AgentKindBadge`）から `AgentBrandIcon`（ブランド画像＋SF Symbol フォールバック）へ差し替え、トップバーと表示を統一した。

## 棄却案

- 注記テキストを1行固定・省略表示にしてレイアウト影響を抑える: グラフ崩れの根本（縦積みで押し上がる構造）を残すため不採用。dimming で鮮度は十分伝わると判断。
- stale データが出る原因（データ取得層）の修正: 本 ADR のスコープ外（表示の実害だけを断つ）。

## 結果

- 鮮度は「%が薄いかどうか」で伝わり、グラフ本体はレイアウトが安定する。
- 回帰ガード: `ClaudeUsageVisibilityAcceptanceTests`（`ClaudeUsageStaleness` のシグネチャ凍結・dimming 判定を担保）。DashboardFeature の全テスト green を維持。
