---
status: active
last-verified: 2026-07-15
---

# ADR 0008: 新規タスク（spawn）画面を廃止し、セッション一覧からのドラフト compose フローに統合する

> **このファイルの役割**: `Features/Spawn`（独立したモーダル新規タスク画面）を廃止し、セッション一覧の「+ セッションを追加」からセッション詳細画面のドラフト（未 spawn）状態に直接入るフローへ置き換えた判断と、初回送信時の spawn→ready→send 順序制御を記録する。
> **書かないもの**: セッション一覧・セッション詳細の現行 UI 構成そのもの（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

wave-2（ADR-0005 の前提）では、新規タスクは独立したモーダル画面 `Features/Spawn`（`SpawnView`/`SpawnViewModel`、`Route.spawn` への `fullScreenCover`）で作成していた。ユーザーから「新規タスク画面を廃止する」明示要望があり、セッション一覧（→ ADR 0007 と同じ wave-4 で「Projects」へ刷新）の各プロジェクト末尾から直接「未 spawn の詳細画面」に入り、送信操作そのものがセッション作成を兼ねるフローが求められた。

## 決定

`SpawnView.swift`/`SpawnViewModel.swift`・`Route.spawn`・`AppRoot` の `spawnCoverPresented` を削除した（コミット `8383311` task-1、`760b6ae`/`da0104d` task-4）。代わりに:

- `Route.sessionComposeDraft(project: String)` を新設。セッション一覧の各プロジェクトグループ末尾（および project グループが空のときは単独行）に出す「+ セッションを追加」ボタン（`SessionListView.addSessionRow`）から `onAddSession(project:)` 経由で push する。
- 遷移先は **既存の `SessionDetailView` そのもの**（`DraftSessionComposeDestination`）。placeholder の `Session`（id `"draft-compose"`、status `.running`）を渡し、`Environment(\.sessionComposeDraft)` に `SessionComposeDraft(project:)` をセットして「このセッションは未 spawn のドラフトである」ことを View に伝える。専用のドラフト用 View は作らず、セッション詳細の入力バー・チャット面をそのまま再利用する。
- **初回送信時の spawn→ready→send 順序制御**（`SessionDetailViewModel.sendMessage(composeDraft:)` → `prepareDraft` → 本体 `sendMessage()`）: `isAwaitingInitialSpawn`（`draftProject != nil && !hasSpawnedDraft`）の間は `startPolling(composeDraft:)` が実際の polling を起動しない（存在しない `draft-compose` セッションを 3 秒毎に叩く phantom polling を防ぐ。task-1 stage-1 MEDIUM として指摘され task-4 で解消、decision-log.md 参照）。ユーザーが送信を押すと `sendMessage()` 内で
  1. `api.spawn(SpawnRequest(agent:, workspace:, model:))` を呼び、
  2. 応答の `Session` を **`session = spawned` として直渡しで採用**し（`listSessions` の反映を待たない。ポーリング/一覧の非同期反映とのレースを避けるため）、
  3. `api.waitUntilReady(sessionID:)` を待ち、
  4. 通常の `api.send(SendRequest(...))` を呼ぶ、
  という順序を1回のメッセージ送信操作の中で直列実行する。
- **モデル→エージェント種別（kind）解決**: `prepareDraft` が `claudeCode`/`cursor`/`codex` 3種のカタログ（`api.agentModels(kind:)`）を並行ではなく順に取得し、`claudeCode`/`cursor` は各モデルごとに `ModelPickerEntry(kind:, modelID:, displayName:)` を1件ずつ生成する。`codex` は契約上モデルカタログが常に空（[specs/mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md) §7.3）なので、`modelID: nil` の **エージェント専用枠1行**を必ず追加し、他2種と別枠で選択可能にする。`ModelPickerEntry.id` は `"\(kind.rawValue)::\(modelID ?? "__agent_default__")"` とし、同一モデル ID が複数 kind に存在しても行 ID が衝突しないようにする。既定選択は `claudeCode` → `cursor` の順で `defaultModel` を持つ最初のエントリ、無ければ先頭エントリ。

## 結果

- 新規タスクの起点はセッション一覧のみになり、独立モーダル画面・専用 ViewModel が無くなった（実装量の削減）。
- 未 spawn ドラフトは実セッションが存在しないため、`inputEnabled`/`showsModelSelectorChip`/`stopButton` 非表示などの分岐を `SessionDetailViewModel.isAwaitingInitialSpawn` で明示的にガードする必要が生じた。
- spawn 失敗時・`waitUntilReady` タイムアウト時は `DraftComposeError.notReady` を投げて `sendState` をエラー表示に落とす（送信テキスト・添付は `sendMessage()` 冒頭で既にクリアされるため、失敗時の再入力は再度打ち直しになる。UX 上の許容トレードオフとして本 run では未改善）。
- 429（レート制限カウントダウン）は旧 `SpawnViewModel` 依存だったため `ErrorRecoveryTests.testRateLimitedShowsCountdown` ごと削除。compose 側での再導入は task-4 に引き継がれたが、本 run では未実装（decision-log.md task-1 波及テスト処理を参照）。

## 却下した代替案

- **spawn 画面を残し「+」ボタンの遷移先だけ変える**: ユーザー要望は画面そのものの廃止であり、専用モーダルを残すと要望に反するため却下。
- **spawn とメッセージ送信を別操作にする（先に spawn ボタン、後で送信）**: 未 spawn 状態で空のセッションを一覧に残すことになり、ドラフトの破棄・再開といった追加の状態管理が必要になるため、初回送信時に一括で spawn する現行方式を採用した。
