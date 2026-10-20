---
status: active
last-verified: 2026-10-20
---

# 閲覧中の完了表示と Codex 中断後の状態

## 修正の要件

会話を前面で開いている間は、完了を確認済みにしてチェックを消す。同じ会話の中断でもチェックを残さない。別の会話や背面で完了した場合は、開いて確認するまでチェックを残す。

Codex の停止要求と子の自然完了や失敗が競合しても、実際の終端状態を表示へ反映する。親の停止だけで、まだ実行中の子を停止済みへ書き換えない。

## 調査した原因

`SessionCompletionFocusEvents` は会話とウインドウのフォーカス変更だけを監視し、閲覧中に生じる新しい完了を既読にしていなかった。今日の追加テストも、その完了が残ることを期待していた。

Codex の通知入口は、停止要求済みの子の完了を `interrupted` に限定していた。停止後の状態再取得が実行中を返し、その後に同じ子が自然完了や失敗を通知する条件を回帰テストで再現し、終端通知が落ちることを確認した。ユーザーの発生時ログとの照合は未実施。

## 検証

修正前の `ParentInterruptCascadeTests.deliversChildCompletionAfterInterrupt` は、停止要求後の子の `completed` と `failed` で失敗し、`interrupted` で成功した。実 transport の通知が利用側へ到達するところまで検査している。製品コード修正前のログは作業 worktree の `.verification/session-activity-state/repro-codex/red.log` に保存した。

修正前の実 SwiftUI の閲覧監視テストは、前面で開いている会話の初回・継続完了でチェックが残り、32 個の期待値が失敗した。中断 API と中断イベントの二つの条件も、古い完了チェックが残って失敗した。

修正後は次の対象検査が成功した。いずれも `compact-test` から標準の `run-swift-tests.sh` を呼び、作業別 scratch にビルドしている。

- `SessionCompletionFocusTests` と `FirstChatCompletionTests` の 4 テストが成功。新規・復元、初回・継続、単一・グリッド、背面と別会話での保持を検査する。
- `ChatSessionLocalCompletionTests` と `CodexInterruptDisplayStateTests` の 5 テストが成功。実 Codex クライアントから会話の表示状態まで接続し、子の正常完了・失敗・中断、停止受理だけでは実行中を保つこと、親の完了通知へ混入しないことを検査する。
- `FirstChatCompletionTests` の画面外描画を修正前後で保存。Codex の新規初回と復元後の継続完了で、残っていたチェックが消えることを目視確認した。
- 生成した Xcode プロジェクトの Debug ビルドとリンクが成功。通常の Debug 署名設定でビルドし、アプリは起動していない。

独立した担当による標準の全件検査を実行した。ログと画像は作業 worktree の `.verification/session-activity-state/` に保存する。実 CLI に接続した操作、XCUITest は実施していない。変更対象に適用する独立した lint・静的解析の設定は見つからなかった。Swift の型検査は各テストビルドと Debug ビルドに含まれる。

全件検査の前半は CodexAppServerKit 102 件、AgentDomain 573 件、DesignSystem 205 件、MessageStore 44 件が成功した。後半の SessionFeature では変更範囲外の `AcceptanceFileChangeCodeViewTests` の行番号検査が一つ失敗した。文脈行の旧側番号は 11 だが、そのテストは nil を期待していた。共有側の `ChatRenderKitTests` は文脈行の新旧番号保持を明示して成功しており、実装と失敗テストは修正前の dev と同一だった。ユーザーの「続けて」により、この一箇所の期待値を共有仕様どおり 11 に修正する承認を得た。追加差分の独立レビューも指摘なし。SessionFeature の全件検査を再実行し、1214 テスト・140 スイートが成功、終了コード 0 を確認した。製品コードは初回検査から変更していない。

初回の後半は SessionFeature 1214 件中の通常 issue がその一つ。DashboardFeature 本体 2168 件、実 git 別パス 41 件、SimulatorBridgeKit 20 件の検査は成功した。DashboardFeature の既存 `withKnownIssue` による GitHistoryWorkflowTests の issue が一つあり、標準設定のスキップは後半で 17 件。今回スキップや既知問題指定は追加していない。前半の終了コードは 0、初回後半は行番号期待値の失敗で 1 と記録する。承認された期待値の修正後に失敗パッケージを再検査した結果、関連 7 パッケージの標準検査は成功した。独立レビューでは今回の製品差分と回帰テストへの正しさの指摘はなかった。

再実行の原文は次のとおり。

```text
✔ Test run with 1214 tests in 140 suites passed after 21.414 seconds.
```

## 修正前後の再現記録

Codex の子の正常完了・失敗は、修正前には対象ターンの終端が利用者へ到達しなかった。修正後は対象を配送し、別スレッド・別ターン・重複と親の正規化イベントへの混入を拒否するテストが成功した。

```text
Expectation failed: (completions.map(\.id) → []) == (["turn-child"] → [Optional("turn-child")])
✔ Test run with 102 tests in 4 suites passed after 0.104 seconds.
```

検証中に並行編集による入力ファイル変更エラーが一度発生した。編集終了後に同じ対象検査を再実行し、成功した。追加統合テストの初回は、テスト用サーバーが親の中断完了を送らず次の親ターンを始める不正な順序でタイムアウトした。正当な中断完了通知を送るようハーネスを修正し、待機期限は延長せず成功した。

Debug ビルドでは既存の `TerminalUI/TerminalView.swift` の Sendable 警告、`PTYKit/Posix.swift` の非推奨 API 警告、AppIntents に依存しないターゲットのメタデータ抽出省略警告を観測した。初回の Codex テストビルドには schema fixture 29 ファイルの未処理警告もあった。今回の製品変更とは別の箇所であり、その修正は含めていない。

SimulatorBridgeKit の検査では `SimulatorBridgeAllowedClassesTests.swift` の二箇所に `unsafeBitCast` を `unsafeDowncast` へ置換可能という既存警告を観測した。

## 採用する修正

既存の状態所有を維持する。閲覧監視に選択中の会話の未読変化を追加し、中断の状態更新では以前の完了を確認済みにする。Codex は停止要求済みの同じ子・同じターンについて、正常完了・失敗・中断の終端通知を受理する。

比較した別案は、DashboardViewModel へフォーカスを保持し、Codex の子を繰り返し取得して終端を検出する形だった。フォーカスの二重管理と取得順序への依存が増えるため採用しない。二つの独立した設計検討と第三者の比較でも、既存の所有を維持する案を推奨した。
