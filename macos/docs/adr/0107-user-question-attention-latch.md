---
status: active
last-verified: 2026-07-21
---

# ADR 0107: AskUserQuestion 到着は hasUnseenCompletion ラッチで attention 化する（status は拡張しない）

## 文脈

AskUserQuestion（`.userQuestionRequested`）が届いても、従来は transcript に質問カードを足すだけで、
セッショングリッドの赤枠・通知が一切発火せず、ユーザーが質問に気づけなかった。
既存の attention 機構は2系統ある: (a) `SessionStatus.latchesUnseenAttentionOnEntry`（awaitingApproval/
completed/error への遷移でラッチ）、(b) `hasUnseenCompletion` フラグ（SessionGridView の赤枠
`stoppedHighlightGridBorder` の駆動点）。

## 決定

`SessionStatus` に新 case（例: `awaitingUserQuestion`）を**追加しない**。
`.userQuestionRequested` ハンドラで `enterAwaitingApproval` と同型の処理を行う:
`hasUnseenCompletion = true` のラッチ＋`SessionCompletionNotifier.notifyAwaitingInput`＋
`remoteSessionNotifier?.approvalPending`。ラッチ済みなら再通知しない（多重通知防止）。
`.userQuestionResolved` は通知・ラッチとも発火しない。status 状態機械は不変。

## 理由

- AskUserQuestion はターン実行中（running）に届く。status を書き換えると承認フロー・turn 状態機械
  （turnCompleted の遷移元判定）に波及し、AgentDomain の全 switch に影響が及ぶ。
- 赤枠の実駆動点は `hasUnseenCompletion` であり、これだけで「作業停止状態と同様の赤枠」要件を満たせる。

## 結果

- 契約: `AcceptanceUserQuestionAttentionTests`（凍結）。
- 制約: 質問保留中でも status は `.running` のまま。グリッドの状態バッジは running 表示となる
  （赤枠と通知で注意喚起する設計）。
