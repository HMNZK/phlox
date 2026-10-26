# Phlox 1.14.1

## Improved

- Agent processes for chats unused for 24 hours can rest until the chat is opened again, reducing background resource use.

## Fixed

- Answers resume updating automatically after a temporary read timeout, without sending another message.
- Visible chats stay connected when using split panes or reopening a resting chat.
- Completion notifications handle foreground registration and delivery errors more reliably.
- Composer descriptions no longer fade during refreshes.
- On iPhone, changes to the pending-work bar no longer rebuild the conversation screen.

## 改善

- 24時間使っていないチャットのエージェント処理を休止し、チャットを開くと再開します。バックグラウンドの資源使用を抑えます。

## 修正

- 一時的な読み取りタイムアウトの後も、追加送信なしで回答の自動更新を再開します。
- 分割表示中や休止から再開したチャットの接続を維持します。
- 完了通知の復帰時の登録処理と、配信エラーの扱いを修正しました。
- 入力候補の説明文が更新時にフェードする問題を修正しました。
- iPhoneの対応待ちバーの変化で会話画面が作り直される問題を修正しました。
