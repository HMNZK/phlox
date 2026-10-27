# Phlox 1.14.1

## New

- Agent processes for chats unused for 24 hours can rest to reduce background resource use. Resume a resting chat with its resume button.

## Fixed

- On iPhone, reading QR codes from photos retries with another method if the default detection method encounters an internal error.
- On iPhone, the empty message field keeps its full height when text is enlarged.
- Unanswered asynchronous questions appear in the attention list while the agent continues working.
- Answers resume updating automatically after a temporary read timeout, without sending another message.
- Visible chats stay active in split panes, and resuming a resting chat keeps its runtime connection.
- Completion notifications handle foreground registration and delivery errors more reliably.
- Composer descriptions no longer fade during refreshes.
- On iPhone, changes to the pending-work bar no longer rebuild the conversation screen.

## 新機能

- 24時間使っていないチャットのエージェント処理を休止して、バックグラウンドの資源使用を抑えます。会話画面の「この会話から再開」ボタンで再開できます。

## 修正

- iPhoneでQRコードの写真を読み取る際、標準の検出方法で内部エラーが起きても読み取りを試みます。
- iPhoneで文字を大きくしたとき、空の入力欄が必要な高さを保つようにしました。
- エージェントが作業を続けている間も、未回答の質問を対応待ちに表示します。
- 一時的な読み取りタイムアウトの後も、追加送信なしで回答の自動更新を再開します。
- 分割表示中の会話を休止対象から外し、画面から再開した会話の接続を維持します。
- 完了通知の復帰時の登録処理と、配信エラーの扱いを修正しました。
- 入力候補の説明文が更新時にフェードする問題を修正しました。
- iPhoneの対応待ちバーの変化で会話画面が作り直される問題を修正しました。
