---
status: active
last-verified: 2026-07-21
---

# Claude Usage の供給経路（現行）

> **このファイルの役割**: ヘッダー/サイドバーの Claude 5h/7d 残量が「今どう更新されるか」の構成図。
> **書かないもの**: 供給経路の決定理由（→ ADR 0039・ADR 0061）、表示側の仕様（→ ADR 0039）。

## 供給源（2系統・チャット相乗り優先）

| 経路 | 動くとき | 実装 |
|---|---|---|
| `get_usage` 相乗り | 生存チャットセッション（常駐 `ClaudeChatClient`）が1本以上あるとき | `ClaudeChatUsageSource`（DashboardFeature/Usage/ClaudeChatUsageSource.swift） |
| statusLine フック | ターミナルセッションで claude CLI が動作中 | `claude-statusline-wrapper.sh` → キャッシュ `claude-usage-rate-limits.json`（従来どおり） |

どちらも無いとき（＝Phlox 不使用時）はキャッシュ最終値＋鮮度注記のまま（ADR 0039 の表示仕様）。旧 `/usage` ヘッドレスプローブ（ADR 0059）は廃止・削除済み。

## 相乗りの流れ

`UsageMonitor`（既存 5 分周期の slowRefresh）
→ `ClaudeChatUsageSource.fetch()`
→ 注入された `sessions: () async -> [any UsageQuerying]`（`ChatSessionViewModel.usageQuerying` 経由で生存 `ClaudeChatClient` を列挙。CompositionRoot で結線）を順に試行
→ `ClaudeChatClient.fetchRateLimits()` が stream-json stdin へ `{"type":"control_request","request_id":"get_usage-N","request":{"subtype":"get_usage"}}` を送信し、control_response を request_id で相関（タイムアウト既定10秒。ターン消費・トークン消費なし・ターン中割り込み可）
→ `AgentRateLimitsSnapshot`（five_hour/seven_day の `usedPercentage`・`resetsAt`）をバケット `5h`/`weekly` へ写像
→ セッション0本・全滅・空バケットは statusLine キャッシュ（`ClaudeUsageProvider`）へフォールバック。

## 頑健性（契約・受け入れテスト凍結）

- 公開面 `UsageQuerying`/`AgentRateLimitsSnapshot` は `StructuredChatKit` の凍結契約。
- pending リクエストは respawn/close の suspension 窓でも全 fail され continuation リークしない（`ClaudeChatClient+Respawn.swift`。二重 resume は removeValue で冪等）。
- `get_usage` は claude CLI（2.1.205 で実測）の非公開 API。壊れた場合はタイムアウト→フォールバックに縮退し、誤値を書く経路はない（→ ADR 0061 の結果節）。
- ヘッダー表示は `TrailingTopBarLayout.usageAvailableWidth`（ウィンドウ幅−サイドバー実占有−コントロール実測幅）で幅を拘束し、ゲージ付き→直列テキスト→非表示の順に縮退する（各候補行は `fixedSize()` で真の単一行幅で判定）。
- **表示可否と対象 CLI の決定（ヘッダー・サイドバー共通の正本は `Usage/UsageDisplay.swift`）**: ヘッダーを出すかは `UsageDisplay.showsTopBarUsage(showInHeader:inspectorVisible:)`（設定 `phlox.usage.showInHeader`・既定 true かつインスペクター非表示のときだけ表示。呼び出しは `DashboardTopBarControls`）。どの CLI を出すかはヘッダー・サイドバーとも `UsageDisplay.visibleKinds(usages:showUnavailable:)` に設定 `phlox.usage.showUnavailable`（既定 false）を渡して決める。ヘッダーのチップ列は純関数 `UsageDisplay.topBarChips(usages:showUnavailable:now:)` が組み立て、`UsageTopBarView` は描画専用（`TimelineView` が毎分 `context.date` で呼び直して鮮度を更新する）。→ ADR 0112
- **表示の視覚仕様（2026-07-17 統一・全エージェント共通）**: エージェント種別はテキスト名でなくブランドアイコン（`AgentBrandIcon(kind:size:)`・`UsageDisplay.topBarBrandIconSize` = 12）で示す。バー/ゲージ色はエージェント別固定色でなく消費率グラデーション `UsageDisplay.usageColor(for: usedPercent)`（claude-statusline の rate_color 移植: 緑→黄→赤。ゲージは残量分を塗る）。Cursor のバケットラベルは「Auto+Composer」を「Auto」へ統一（`CursorUsageProvider`）。凍結 `AcceptanceUsageBarUnificationTests`。
