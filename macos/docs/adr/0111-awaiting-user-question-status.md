---
status: active
last-verified: 2026-07-21
---

# ADR 0111: AskUserQuestion 保留中は SessionStatus.awaitingUserQuestion（入力待ち）にする（ADR 0107 を supersede）

## 文脈

ADR 0107 は「status 状態機械への波及を避け、AskUserQuestion は hasUnseenCompletion ラッチのみで
attention 化する（status は .running のまま）」と決めた。実機検証で2つの問題が出た:
(1) シングルビューではステータスが「実行中」のままで停止が伝わらない（ユーザー要望:
停止状態にしてほしい）。(2) シングルビューでは表示中セッションが DashboardView の
onChange により即 `markCompletionSeen` されるため、hasUnseenCompletion ベースの赤表示が
一度も定着しない。

## 決定

1. `SessionStatus` に **`.awaitingUserQuestion`** を新設する（wire 文字列 `"awaitingUserQuestion"`。
   iOS の `init(wire:)` にも追加。未知文字列→idle の後方互換は維持）。バッジ語彙は
   ラベル「入力待ち」/ "input"、色は承認待ちと同系、アイコン `questionmark.bubble.fill`。
2. `.userQuestionRequested` で `status = .awaitingUserQuestion`（`latchesUnseenAttentionOnEntry
   = true` により hasUnseenCompletion も自動ラッチ）。`.userQuestionResolved(.answered)` で
   `.running` へ復帰。失効は既存の turnInterrupted/error 経路が idle/error へ落とす。
3. 赤表示は `SessionAttentionPolicy.requiresAttention(status:hasUnseenCompletion:)` の導出に
   一本化する: **hasUnseenCompletion または「入力を待つ状態」（awaitingApproval /
   awaitingUserQuestion）なら赤**。保留が続く間は既読化（markCompletionSeen）に関係なく
   サイドバーのプロジェクト欄・セッション行・グリッドタイルが赤を維持する。
   `unseenCompletionCount`（Dock バッジ・通知）の意味は変えない。
4. 質問カードは「選択で即送信」をやめ、純粋なフォーム状態 `UserQuestionFormModel` と
   カード最下部の単一送信ボタン（全問回答で有効・多重押下防止）による明示送信にする。

## 結果

- ADR 0107 は superseded（ラッチ・通知経路の記述は本 ADR に引き継ぎ）。
- 契約: `AcceptanceUserQuestionStatusTests`・`AcceptanceSessionAttentionPolicyTests`・
  `AcceptanceUserQuestionFormTests`（凍結）。旧 `AcceptanceUserQuestionAttentionTests` も
  通知1回・ラッチ解除の回帰として green を維持。
- 制約: `.awaitingUserQuestion` は escape/interrupt 判定（`isRunning`）・入力可否・
  ライブセッション判定（CompositionRoot.isLiveChatSession）で running 系として扱う。
