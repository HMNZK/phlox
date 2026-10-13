---
status: active
last-verified: 2026-10-12
---

# Claude Usage の供給経路（現行）

> **このファイルの役割**: 下部バー・サイドバーの Claude 5h/7d 残量が「今どう更新されるか」の構成図。
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
- 使用量はヘッダーではなく、ウィンドウ最下部の全幅バー（`Dashboard/UsageBottomBarView.swift`。`DashboardView` の `safeAreaInset(edge: .bottom)`、高さ 24pt）に出す（2026-10-12、ADR 0186。旧ヘッダーのチップ `UsageTopBarView`・`TrailingTopBarLayout` は廃止）。幅が足りないときは `ViewThatFits` で「ラベルとリセット時刻あり → ラベルのみ → ラベルなし」の順に縮める。押しても何も開かない（インスペクタの使用量タブは 2026-10-13 に廃止。ADR 0192）。
- **表示可否と対象 CLI の決定（正本は `Usage/UsageDisplay.swift`）**: 下部バーを出すかは設定 `phlox.usage.showInHeader`（設定画面の「画面下部に使用量を表示する」。既定 true。キー名はヘッダー時代のまま。`UsageBottomBarView` が読む）。バーには `UsageDisplay.bottomBarGroups(usages:showUnavailable:)` が `AgentKind.allCases` の順で全バケットを並べる。取得できないハーネスは、設定 `phlox.usage.showUnavailable`（既定 false）がオンのときだけ「取得できません」として並べる。残量が `lowRemainingThreshold`（20%）以下のバケットは文字を注意色にする。→ ADR 0112（ヘッダー時代の決定）・ADR 0186
- **表示の視覚仕様（2026-07-17 統一・全エージェント共通）**: エージェント種別はテキスト名でなくブランドアイコン（`AgentBrandIcon(kind:size:)`）で示す。下部バーは文字だけで示し、ゲージは持たない。消費率の色分け（旧 `UsageDisplay.usageColor`）はどの画面からも使われなくなったので 2026-10-12 に消した。Cursor のバケットラベルは「Auto+Composer」を「Auto」へ統一（`CursorUsageProvider`）。回帰保護 `UsageDisplayTests`（ブランドアイコンほか）・`CursorUsageResponseTests`（Auto 表記）。
