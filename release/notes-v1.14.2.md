# Phlox 1.14.2

## Fixed

- Reduced repeated work when syncing unchanged chat history and checking unanswered questions, helping keep the interface responsive with many sessions.
- Fixed inconsistent chat status when stopping, closing, or receiving delayed agent notifications.
- Sending immediately after stopping now waits for the previous agent process to finish exiting before sending the new message.

## 修正

- 変更のないチャット履歴の同期と未回答の質問の確認で、繰り返す処理を減らしました。多数のセッションを開いたときの画面の応答性を改善します。
- 停止・終了や遅れて届く通知が重なったとき、会話の状態が食い違う問題を修正しました。
- 停止直後に送信したときは、前のエージェント処理が終了してから新しいメッセージを送るようにしました。
