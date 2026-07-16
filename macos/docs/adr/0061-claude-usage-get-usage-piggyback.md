---
status: active
last-verified: 2026-07-10
---

# ADR 0061: チャットモードの Claude Usage は常駐プロセスへの `get_usage` 相乗りで供給し、`/usage` プローブを廃止する

> **このファイルの役割**: ADR 0059 のヘッドレスプローブを廃止し、常駐チャットプロセスへの `get_usage` control_request へ一本化した決定理由。
> **書かないもの**: 供給経路の現行構成（→ architecture/claude-usage-supply.md）、実装詳細（→ Packages/ClaudeAgentKit/Sources/ClaudeAgentKit/ClaudeChatClient+Usage.swift）。

## 文脈

ADR 0059 は「チャットモードに供給が無い」前提で `claude -p '/usage'` ヘッドレスプローブ（人間向けテキストの解析）を導入した。その後の徹底調査（2026-07-10）で、claude CLI 2.1.205 の stream-json 双方向制御に**非公開の `get_usage` control_request** が存在することを発見・実測確認した:

- `{"type":"control_request","request_id":...,"request":{"subtype":"get_usage"}}` を常駐 `claude -p --input-format stream-json` の stdin へ書くと、control_response で `rate_limits`（five_hour/seven_day の `utilization`・`resets_at`=ISO8601）が返る。
- **ターンを消費しない・トークン消費ゼロ・ターン実行中でも割り込みで応答する**（実測）。
- Phlox のチャットモードは常駐 `ClaudeChatClient`（stream-json 双方向）を既に持つため、追加プロセスなしで相乗りできる。

プローブとの並存はユーザー裁定で棄却し、**プローブ廃止・相乗り一本化**を決定した（ゲート②）。

## 決定

- `StructuredChatKit` に凍結公開面 `UsageQuerying`（`fetchRateLimits() async throws -> AgentRateLimitsSnapshot`）を置き、`ClaudeChatClient` が適合する（request_id 採番・pending 相関・タイムアウト既定10秒・respawn/close 窓の pending 全 fail で continuation リークを防止）。
- `ClaudeChatUsageSource`（DashboardFeature）が生存チャットセッションを順に試行してスナップショットをバケット（`5h`/`weekly`）へ写像し、**セッション0本・全滅・空バケット時は statusLine キャッシュへフォールバック**する。`UsageMonitor` の既存 5 分周期に乗る。
- ADR 0059 のプローブ（`ClaudeUsageProbe*` 一式・テキスト解析）は**削除**。ADR 0059 は superseded。
- ADR 0039 の表示仕様（行を消さず鮮度注記）と statusLine 供給（ターミナルセッション時）は**変更しない**。チャットも statusLine も無い時はキャッシュ最終値＋鮮度注記のまま（ユーザー了承の割り切り: その状況は Phlox 不使用時）。

## 棄却案

- **プローブとの並存**: 供給源3系統の後勝ち管理は複雑さに見合わない。プローブは 30 分ごとの追加プロセス起動＋機械可読契約のない人間向けテキスト解析で、相乗りの完全下位互換（ユーザー裁定「プローブは廃止して相乗りだけでいい」）。
- **statusLine 相当の常駐注入**: headless `-p` では statusLine が発火しない（ADR 0039 で実測済み）。

## 結果

- チャット運用中は実データ（実測: 5h/7d の utilization・resets_at）が 5 分周期で供給される。プロセス追加ゼロ・JSON 契約（テキスト解析より頑健）。
- **`get_usage` は非公開・実験的 API**であり、CLI 更新で静かに壊れうる。壊れた場合は fetchRateLimits がタイムアウト/失敗し statusLine フォールバックへ自然に縮退する（誤値は出ない）。更新が止まったらまず CLI バージョンと control_response 形式を疑うこと。
