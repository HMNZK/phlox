# Phlox 1.9.1（build 31）リリース記録

## 状態

公開準備中。ユーザーがマージとリリースを承認。配布物と検証ログはリポジトリの `.build/releases/1.9.1/` に保持する。

## 変更

- Codex の親を中断した時に、子・孫の実行中 turn も中断する。親が停止済みでも子の停止を再試行でき、一部の失敗を報告しながら残りを止める。
- 日本語入力の重複した確定通知が、送信後の入力欄へ送信済みの文章を書き戻す問題を修正する。

## 検証

- Codex 専用ゲート：CodexAppServerKit 100件、SessionFeature 1,132件、production reachability 3件、DashboardFeature の Codex 経路2件が成功。
- 入力欄の追加テスト3件成功。初回はテスト補助クラスの MainActor 指定不足でコンパイル失敗し、指定を修正して再実行した。
- 子停止の追加テストでは、初回の実行中親テストがアプリ内部と同じイベントストリームを購読して待機した。テストを中断し、専用の threadEvents に修正して再実行したゲートは成功。
- Debug ビルド成功。AppIntents.framework の依存がないため、メタデータ抽出を省略する既存警告がある。
- パッケージ正本ゲート：AgentDomain 579件、DesignSystem 193件、MessageStore 42件、SessionFeature 1,132件、DashboardFeature 本体1,983件と実git26件、SimulatorBridgeKit Swift Testing20件が成功。実git検査は正本の指定どおり別パスで実行した。
- シミュレーターの許可リスト検査成功。
- 実画面、Release 署名・公証、公開後疎通：確認中。
- lint・独立した静的解析：未設定（1.9.0 時点の検査設定と今回の対象パッケージ設定を確認）。

## Release notes

### Fixed

- Interrupting a Codex session also stops its running subagents.
- Sent text no longer reappears in the message input after a delayed Japanese input confirmation.

### 修正

- Codex セッションを中断した時に、実行中のサブエージェントも停止するようにしました。
- 日本語入力の確定通知が遅れて届くと、送信済みの文章が入力欄へ戻る問題を修正しました。
