---
status: active
last-verified: 2026-07-21
---

# ADR 0109: サブエージェントへのフォローアップはメインセッション経由の通常ターンで送る

## 文脈

サブエージェントタブ（SubAgentDrawerView）に入力欄を設け「サブエージェントと会話」できるように
したい。しかし Claude Code CLI のプロトコルには、実行中・完了済みサブエージェントへ外部から
対話入力を渡す control_request 経路が存在しない（Task ツール起動のサブエージェントは自律実行）。

## 決定

フォローアップは **メインセッションへの通常ターン（client.turnStart）** として送信する。
`ChatSessionViewModel.sendSubAgentFollowUp(subAgent:text:)` が
`composeSubAgentFollowUpPrompt` で対象の `toolUseId`・`description`・ユーザー本文を明示した
構造化プロンプトを合成し、メインの Claude に SendMessage 相当の継続・回答を依頼する。
transcript には合成プロンプトではなく**ユーザー本文のみ**を記録する（sendText と同じ
表示/CLI 入力の分離）。状態遷移・turnStart 失敗時の巻き戻しも sendText と同型。

## 理由

- CLI 側改修（プロトコル拡張）はスコープ外で、Phlox 単体で成立する唯一の経路。
- メインの Claude は Agent ツールの SendMessage で完了済みサブエージェントを文脈付きで再開できる
  ため、実用上「サブエージェントとの会話」を近似できる。

## 結果

- 契約: `AcceptanceSubAgentFollowUpTests`（凍結）。
- 制約: 応答はメインセッションの transcript に流れる（サブエージェントペイン内には閉じない）。
  入力可否は `isReadyForInput`（メイン Composer と同一規則。running 中も送信可）。
