## New

- Chat is easier to scan. Code names, file names, successes, and failures in answers are highlighted, and code blocks are colored by language (Python, TypeScript, Go, Rust, shell, JSON, SQL, and more).
- The Changes tab colors file contents and diffs by file type.
- Model, effort, and permission chips in the message field now show their full names, and the chat and message field use 80% of the column width.

## Fixed

- Fixed the chat sometimes showing "Session ended (exit 143)" right after sending a message when the model or other settings had changed.
- Fixed the "no response" warning appearing during long-running commands. It now appears only after 30 minutes without a response.
- Fixed the sidebar toggle button sometimes not responding to clicks.
- Fixed the whole window moving when dragging the sidebar edge near the top of the window.
- Fixed the new-session popup from the sidebar "+" button closing when the mouse moved toward it.
- Fixed the subagent drawer being cut off at the right edge, and long approval cards growing past the top of the window.
- Fixed the time and copy button of a message overlapping the next turn's cost on hover.

## 新機能

- 会話が読みやすくなりました。回答の中のコード上の名前・ファイル名・成功と失敗を強調し、コードブロックを言語ごと（Python・TypeScript・Go・Rust・シェル・JSON・SQL など）に色分けします。
- 変更タブで、ファイルの内容と差分をファイルの種類ごとに色分けするようになりました。
- 入力欄のモデル・推論の深さ・権限の表示を省略せず全文で表示し、会話と入力欄の幅を列の 80% にしました。

## 修正

- モデルなどの設定を変えた後に送信すると、「セッションは終了しました (exit 143)」と表示されることがある不具合を修正しました。
- 長いコマンドの実行中にも「無応答」と表示される不具合を修正しました。反応が 30 分ないときだけ表示します。
- サイドバーの開閉ボタンが押せないことがある不具合を修正しました。
- 窓の上端付近でサイドバーの境界をドラッグすると、窓全体が動いてしまう不具合を修正しました。
- サイドバーの「＋」で開く新規セッションの画面が、マウスを動かすと閉じてしまう不具合を修正しました。
- サブエージェントの画面の右端が見切れる不具合と、長い承認カードが窓の上端を越えて伸びる不具合を修正しました。
- 発言にマウスを乗せたとき、時刻とコピーのボタンが次のコスト表示と重なる不具合を修正しました。
