---
status: active
last-verified: 2026-07-12
---

# ADR 0081: 「処理中」判定の単一正本化と interrupt の合流・世代ガード

## 文脈

チャットモードでサブエージェント（Task ツール）がバックグラウンド実行中、3つの症状が併発していた:

1. メイン transcript には Thinking インジケータが出る（`showsProcessingIndicator` はサブエージェント込み）のに、composer は送信ボタン＝「停止中」の見た目になる。
2. esc を押してもサブエージェントが止まらない（`handleEscapeKey` の単発分岐が `status == .running` ガードで、ターン完了後は不発）。
3. サブエージェントビューに Thinking・ツール実行中表示が無い（→ 表示側は ADR 0025 系の別実装欠落。本 ADR の範囲外、worklog 0047 参照）。

根本原因は「実行中」の判定が2系統あること: `status`（ターン状態。`turnCompleted` で無条件に `.idle`）と `showsProcessingIndicator`（status ∨ backgroundTasks ∨ subAgents running）。esc・composer が前者を見ていた。

## 決定

1. **UI とホットキーが参照する「処理中」の単一正本は `showsProcessingIndicator`** とする。
   - `handleEscapeKey` の単発 esc 分岐・composer の停止⇄送信切替（`ChatSessionView` / `GridChatColumn`）を `status.isRunning` から差し替え。
   - **`status` 自体の意味（ターン状態）と遷移は変えない**（完了通知・永続化・グリッド表示への波及を避けるため。status を「サブエージェント込み」に再定義する案は却下）。
2. **`turnInterrupt()` はターン間（status == .idle・サブエージェントのみ running）でも `client.interrupt()` を送り**、ローカルの running サブエージェントを `failRunningSubAgents()` で failed へ収束させる（`turnInterrupted` イベントが来ない経路でも UI が収束する）。
3. **interrupt は in-flight 合流＋論理ターン世代ガード**で多重発火と遅延上書きを防ぐ:
   - 実行中の interrupt があれば新規送信せず同じ Task へ合流（esc 連打・停止ボタン・`confirmRevert` の同時流入で SIGINT を1回に保つ）。
   - `turnGeneration` は**論理ターンにつき1回**進める（ローカル送信時に先行 bump し、対応する `.turnStarted` では pending フラグを消費して二重 bump しない。ローカル送信を経ない `.turnStarted`＝resume 等では従来どおり bump）。interrupt 完了時に世代が進んでいたら状態収束をスキップ＝古い interrupt が新ターンの `status` を `.idle` に潰さない。

## 結果

- 受け入れテスト `AcceptanceSubAgentStopParityTests`（5件・凍結）と白箱 `SubAgentStopWhiteboxTests`（4件）が契約を固定。
- 独立レビュー（persona-reviewer / Codex 二段）で多重発火・世代境界の2欠陥を検出し修正（経緯は delivery/0047）。
- 既知の限界: ターン間の `client.interrupt()`（クロード系は CLI プロセスへの SIGINT）がバックグラウンドのサブエージェントを実際に止めるかは**実 CLI では未検証**（フェイク CLI 契約と実機 runtime 検証は worklog 0047 の残項目参照）。
