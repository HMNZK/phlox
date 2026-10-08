# Phlox 1.9.1（build 31）リリース記録

## 状態

公開準備中。本体・DMG の署名と公証は完了。Sparkle 更新 ZIP の署名はキーチェーンの許可待ち。ユーザーがマージとリリースを承認。配布物と検証ログはリポジトリの `.build/releases/1.9.1/` に保持する。

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
- 実画面：検証専用 Debug データで子を起動し、親の中断後に親が待機へ戻り、子の実行中表示が消えることを確認。子の記録にも `turn_aborted` / `interrupted` が残った。送信後の入力欄は空のまま。
- Codex の外部コマンドは turn の中断後も残り得る。検証用 `sleep 180` が残存したが、検証用 Debug の終了後に app-server とともに終了した。常用 Release は終了していない。
- 実際の日本語 IME キー操作は未検証（操作ツールの日本語入力が欠落したため）。遅延した確定通知は AppKit の回帰テスト3件で検証した。描画の変更はなく、画面外描画の対象に入力欄は含まれていない。
- Release ビルド成功。最初の Developer ID 一括指定は resource bundle の自動署名設定と衝突したため、正式手順の署名無しビルド・後段署名に揃えた。再実行時のプロジェクトパス誤りも修正した。
- Release ビルドの既存警告：PTYKit の非推奨文字列 API、TerminalUI の Sendable、DashboardView の ViewBuilder、AppIntents の抽出省略。
- Release 署名検査4件成功（公証後にも再実行）。本体・DMG とも公証 Accepted、stapler validate 成功、Gatekeeper accepted。本体の `codesign --verify --deep --strict` も成功。
- 本体公証 ID：`3216a3f3-efa5-48b3-8b6c-cb7e70386de7`。DMG 公証 ID：`b1305f7a-4bd5-4953-a839-6610f10768a1`。
- 公開後疎通：確認中。
- lint・独立した静的解析：未設定（1.9.0 時点の検査設定と今回の対象パッケージ設定を確認）。

## 配布物

| ファイル | バイト数 | SHA-256 |
|---|---:|---|
| Phlox.dmg | 29087926 | `10beb1dc541f3c514ca7abb5f2c55ae0ba7a699de760e70b7cb6d69bedf69bee` |
| Phlox-1.9.1.zip | 24498311 | `554c076756fce04c9fcf694d8070a0a6ad6fd46b9820cc0d6bee7d167bece2cb` |

## Release notes

### Fixed

- Interrupting a Codex session also stops its running subagents.
- Sent text no longer reappears in the message input after a delayed Japanese input confirmation.

### 修正

- Codex セッションを中断した時に、実行中のサブエージェントも停止するようにしました。
- 日本語入力の確定通知が遅れて届くと、送信済みの文章が入力欄へ戻る問題を修正しました。
