# ADR 0222: 停止・終了と遅れて届く通知でチャットの状態を矛盾させない

日付: 2026-10-29。状態: 採用。

## 文脈

チャット（Claude 経路）の送信・停止・閉じる・休止と、CLI から遅れて届く通知の全順序をモデル検査した（ローカルスキル `verify-session-state-model`）。次の 4 件が見つかった。1 と 2 は実コードとゲート付きのフェイクで再現した。

1. 送信と CLI の予期しない終了が重なると、`processExited` を処理した後に `turnStart` が CLI を起動し直して `turnStarted` を出し、終了表示のまま `.running` に戻る。
2. `turnStart` が `transport.send` を待つ間に停止すると、`currentTurnOpen` がまだ false なので後始末エラーの吸収が準備されない。さらに送信完了時に `currentTurnOpen = true` を書き直すので、停止で閉じたターンが開き直る。停止したのに `.error` が残る。
3. 停止の `turnInterrupted` が、その後に送ったターンの `turnStarted` より後に届くと、`handle(.turnInterrupted)` が新しいターンを `.idle` にする。ADR 0081 の世代確認は `turnInterrupt` の末尾にしか無い。
4. `stopProcess` が受信ループを止めても溜まった通知は処理される。`turnInterrupt` の末尾と `sendText` の送信失敗は `isTerminating` を見ない。`terminate()` の `.completed(0)` の後に状態が書き換わりうる。

## 決定

1. **終了を知らせた世代では起動し直さない。** `ClaudeChatClient` は `processExited` を出した世代を覚え、その世代のまま `turnStart` が来たら起動し直さず `notStarted` で失敗させる。中断で止めた世代（`processExited` を出さない）は従来どおり次の送信で起動し直す（ADR 0083）。`sendText` の送信失敗は、`processExit` が立っていれば `status` を書き換えない（終了コードの `.error` を残す）。
2. **ターンは送信を書き込む前に開く。** `turnStart` は `turnStarted` を出すのと同時に `currentTurnOpen`・`currentTurnLine` を立て、書き込み完了後には書き直さない。書き込み中の停止でも後始末エラーの吸収が準備される。書き込み中に始まった停止でプロセスが終わって書き込みが失敗した場合は、停止の結果として扱い `.error` を出さない。書き込み中に自己修復が新しいプロセスへ送り直した場合も、元の書き込みの失敗でそのターンを壊さない。停止が始まった後に送った指示の失敗は、従来どおり `.error` にする（黙って消さない）。
3. **新しいターンが始まった後に、古い停止の `turnInterrupted` を出さない。** `interrupt()` は開いているターンを閉じる時点で `turnStarted` の回数を控え、SIGINT の後に変わっていたら `turnInterrupted` を出さない。許可の否認を書き込む待ちの間に始まったターンは、この停止が閉じるので `turnInterrupted` を出す。停止したターンの収束は VM の `turnInterrupt` 末尾（世代確認つき）が行う。Claude の通知はターンを識別できないので、出す側で止める。
4. **終了・休止を始めたら、ターンの状態は動かさない。** `handle` は `isTerminating` の間、`turnStarted`・`turnCompleted`・`turnInterrupted`・`error`・`processExited` で status を動かさない（await の後も確かめ直す）。会話 ID の採用とターン費用の記録は残す。`turnInterrupt` の末尾と `sendText` の送信失敗も `isTerminating` を見る。差分や会話の項目は従来どおり処理する。

## 見送ったこと

- **停止の直後に送った指示が、終わりかけの CLI に届く件。** 停止後、受信終了を処理する前に送ると、SIGINT で終わる途中の CLI へ書き込み、`send-failed` か結果の無い終了の `.error` になる。送信時に起動し直せば直るが、`AcceptanceInterruptAndInUseHealTests` の 2b〜2d（編集禁止の受け入れテスト、2026-07-03）は「中断後も同じ CLI で次のターンを続ける」前提で、`claude -p` が SIGINT で終わるという後の観測（2026-07-13、ADR 0083）と食い違う。どちらを正とするかは別に決める。

## 影響

- 終了したチャットへ送信が競合したときは、送信失敗（下書きの復元つき）になる。続けるには「この会話から再開」を使う。
- 閉じる・休止の途中に届いた完了・エラーは画面に反映されない。会話 ID と費用の記録は残る。
- 書き込み中の停止で書き込みが失敗したとき、VM は送信成功として扱うので、巻き戻し後の文脈の前置き（`pendingReplayContext`）はその送信で使い切ったことになる。巻き戻し直後の送信をその書き込みの一瞬に止めた場合だけ、次のターンは前置きなしで走る。エラー表示を出さないことを優先した。
