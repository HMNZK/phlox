---
status: active
last-verified: 2026-07-17
---

# 0091: Codex app-server の error 通知の終端性判定（willRetry 非終端＋EOF 合成終端）

## 文脈

Codex チャット（app-server 経路）で、ターン進行中に停止ボタンが消えて「作業していないように見える」症状があった。根本原因は `CodexAppServerClient` の通知正規化で、app-server の `error` 通知を**一律に終端 `.error`** に写像していたこと。app-server は一時的な失敗（レート制限・ネットワーク断）で `willRetry: true` を付けた error 通知を出し**ターンを継続する**が、旧実装ではこれが終端イベントとして `ChatSessionViewModel` に届き、status が `.error` になって停止ボタン（表示条件は `showsProcessingIndicator` ≒ running。ADR 0064）が消えていた。ワイヤ形式は codex-rs（commit 315195492c80）で確認: camelCase `willRetry`・メッセージは `error.message` にネスト。

## 決定

1. **`willRetry == true` の error 通知は非終端 `.warning(message:)` に正規化する**。ターンは継続中なので status を落とさない（＝停止ボタンは出続ける）。`willRetry` が false/欠落なら従来どおり終端 `.error`。
2. **プロセス EOF 時の終端を合成する**。クライアントが `activeTurns` を追跡し（`turnStart` RPC・`turnStarted` 通知・willRetry error で登録、終端イベントで解除。threadId が取れない willRetry error は追跡を変更しない）、`close()` 要求によらず通知ループが終わった（＝プロセス死）とき active turn が残っていれば、終端 `.error`（"Codex app-server process exited before the turn completed"）を合成して流す。これが無いと「willRetry を非終端化した」ことで逆に、リトライ中にプロセスが死ぬと永遠に running のままになる。
3. `turnStart` **応答待ち中**のプロセス死は Kit の合成に依存しない: RPC の throw を `ChatSessionViewModel.sendText` の catch が受けて status を `.idle` に戻す（A3 契約。`PMTurnStartFailureTerminalizationTests` で固定）。

## 棄却した代替案

- **VM 側（`ChatSessionViewModel`）で error の終端性を推測する** — 終端性はワイヤプロトコルの知識であり、正規化層（Kit）が持つべき。VM に置くと Claude/Cursor 経路と分岐が増える。
- **willRetry error を完全に握りつぶす（イベント非発行）** — リトライ中であることをユーザーに見せられない。`.warning` としてトランスクリプトに残す。

## 結果

- 停止ボタンはリトライを跨いで表示され続け、プロセス死では確実に終端して固着しない。受け入れ `AcceptanceStopButtonPersistenceTests`（4件）＋ `CodexAppServerClientTests`（41件・raw JSON-RPC 経由の統合形）で凍結。
- 残余: 実機での app-server リトライイベント実観測は未実施（MEDIUM として持ち越し）。Cursor 側の同症状はコード上の機序が見つからず未解明（one-shot 実行は中間終端イベントを発しない）。
