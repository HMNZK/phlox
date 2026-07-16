---
status: active
last-verified: 2026-07-06
---

# ADR 0039: Claude Usage の供給はターミナルセッション限定と認め、行を消さず鮮度を可視化する

> **拡張**: ADR 0059（2026-07-10）が `/usage` ヘッドレスプローブを第2の供給源として追加し、同日 [ADR 0061](0061-claude-usage-get-usage-piggyback.md) がプローブを廃止して常駐チャットプロセスへの `get_usage` 相乗りへ差し替えた。本 ADR の表示仕様（行を消さず鮮度注記）と statusLine 供給は現行のまま。
> **このファイルの役割**: 「API Usage が消えた」回帰の根本原因と、可視化方針の決定理由。
> **書かないもの**: Usage 機能の実装詳細（→ Packages/DashboardFeature/Sources/DashboardFeature/Usage/）。

## 文脈

Claude のレート制限残量%（5h/7d）は statusLine フック payload から取得している。診断（chat-ux-batch task-11）で次が確定した:

1. チャットモード（appServer backend）の起動は `hookIntegration = .none` で `--settings` が渡らない（Codex 用に書かれた分岐に Claude チャットが乗った）。
2. **headless `-p` モードでは statusLine がそもそも発火しない**（PM が settings 注入プローブで実測確認）。つまり配線を直しても チャットモードから供給は復活しない。
3. 実運用が チャットモードのみになった結果、キャッシュ（`claude-usage-rate-limits.json`）が stale 化し、既定の `showUnavailable=false` で行ごと消えて「Usage が消えた」ように見えた。

## 決定（ゲート②でユーザーが「可視化改善」を選択）

- **Claude の Usage 行は `.unavailable` でも常に表示**する（`UsageDisplay.visibleKinds` の Claude 特例）。供給が構造的に止まりうる CLI の行を黙って消さない。
- `CLIUsage.dataAsOf`（データ自体の時刻）を導入し、`ClaudeUsageStaleness.note` が「未取得（ターミナルの Claude セッション実行時に更新されます）」「N分前の値」等の**鮮度注記**を出す（30分閾値）。stale 時は%を薄く表示。
- `.ok` かつ `ts` 欠落時は注記を出さない（実データの上に「未取得」が重なる矛盾の回避・PM 裁定）。

## 棄却案

- チャットモードへの statusLine 配線: CLI 仕様上不可能（実測で棄却）。
- 自動プローブ（不可視 PTY セッションを定期起動して statusLine を収穫）: ハック度が高くユーザーが不採用。
- 現状維持＋ドキュメント化のみ: ユーザーが不採用。

## 結果

- Usage を最新に保つには、ターミナルモードの Claude セッションをときどき動かす必要がある（UI の注記が誘導）。
- 回帰ガード: `ClaudeUsageVisibilityAcceptanceTests` ＋ `expiringPassedResets` の dataAsOf 保持テスト。
