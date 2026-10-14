# Phlox 1.10.0（build 32）リリース記録

## 状態

公開済み：[GitHub Release v1.10.0](https://github.com/HMNZK/phlox/releases/tag/v1.10.0)。リリースタグは `62efec90`。ユーザーが dev・main へのマージとリリースを指示した（2026-10-14）。`ios/` の未コミットの資料は、指示によりコミットせずに残す。配布物と検証ログはリポジトリの `.build/releases/1.10.0/` に保持する。

## 変更

1.9.1（`43432765`）から `7d7dd9b5` までの変更。主なもの:

- 新規チャットの画面（ADR 0183・0188）と、プロジェクト単位のタブ（ADR 0187）。
- 画面下部の使用量のバー（ADR 0186。既定は横棒、設定で数値）。インスペクタはファイルだけにした（ADR 0192）。
- 白黒のアクセント（ADR 0189）、共通のポップアップの見た目（ADR 0190）、新規チャットの見出しのドット書体（ADR 0191）。
- ターミナルでエージェントを始めるメニューとカスタムエージェントの廃止（ADR 0185）、共通ターミナルの廃止（ADR 0187）、セッションの総コストの表示の廃止（ADR 0192）。
- 画像の添付の上限を 20MB にし、解像度を保つ。コマンドの長い説明を選択行で横送りする。
- Codex と Claude の権限の適用と復元、画像の準備中の入力の消失、起動中の削除・終了の競合を修正。

## 検証

- パッケージ正本ゲート（`macos/scripts/run-swift-tests.sh`）：AgentDomain 570件、DesignSystem 193件、MessageStore 44件、SessionFeature 1,181件、DashboardFeature 本体1,990件と実git35件、SimulatorBridgeKit 20件が成功。
- 初回のゲートで `UsageBottomBarLayoutTests` が 8 件失敗した。SwiftPM は xcassets をコンパイルせず、テストの中で Assets.car を作ると、先に走った別のテストが画像を引いた後になってロゴが描かれないため。Assets.car を消すと同じ失敗が再現した。正本のスクリプトがテストの前に Assets.car を作るよう直し（`9e63c9aa`）、Assets.car を消した状態から全数が成功した。
- シミュレーターの許可リスト検査成功（Xcode 17C52 × iOS 26.2）。
- Release ビルド成功（署名無しビルド・後段署名）。
- 本体・DMG とも公証 Accepted、stapler validate 成功、Gatekeeper accepted（`source=Notarized Developer ID`）。本体の `codesign --verify --deep --strict` も成功。配布物の版は 1.10.0 / build 32。
- 本体公証 ID：`5fdce47b-048b-4f12-8083-580306c8a0f0`。DMG 公証 ID：`b5d0bb4f-aaf7-48c2-924c-b499e9ab1eb2`。
- Release 署名検査4件成功（`test_simulator_bridge_signing.sh`、公証後）。
- Sparkle ZIP は staple 後のアプリから作り、Ed25519 署名を本体に埋め込んだ公開鍵で検証して成功（CryptoKit による手元の検証。リポジトリのテストには未登録）。
- 実画面：新規チャットの見出し・右サイドバー・下部の使用量の表示と設定の切り替えは、Debug ビルドでユーザーが確認済み。「履歴から再開」のチップは、プロジェクト未選択のため画面での確認は未実施。
- lint・独立した静的解析：未設定。
- 公開後疎通：`https://phlox.cc/appcast.xml` の先頭は 1.10.0 / build 32。最新 DMG（`releases/latest` は v1.10.0 へ転送）と更新 ZIP のダウンロード先は HTTP 200。GitHub 上のサイズと SHA-256 は手元の配布物と一致。
- Pages run [38496788577](https://github.com/HMNZK/phlox/actions/runs/38496788577) は `62efec90` のデプロイに成功。

## 配布物

| ファイル | バイト数 | SHA-256 |
|---|---:|---|
| Phlox.dmg | 30034058 | `3820827d46773d508228aca014c5899563efc5e2c0171733bbcd3fb7dbdefeb2` |
| Phlox-1.10.0.zip | 25321892 | `7cabf9cf1f38d0ac4c80ce611a8a76ab0329d1cfd636b36f5ba0d695c0b606eb` |

## Release notes

### New

- A new chat screen. Press ⌘N or a project's + to type your first message, then pick the project, model, effort, permissions, and whether to use the existing directory or a new worktree before sending. Suggestion chips and "Resume from history…" (including past worktree conversations) sit under the input.
- Tabs are now per project. The top row shows projects; the row below shows that project's chats, terminals, changes, files, browser, and simulator.
- Usage for all harnesses now appears in a bar at the bottom of the window, shown as meters by default. Settings can switch it to percentages.
- A refreshed look: black-and-white accents, a lighter header, smoother sidebar opening, and a dot-font greeting on the new chat screen.
- Image attachments up to 20 MB, sent without lowering their resolution.
- Long command descriptions scroll sideways in the selected row of the command list.
- Simplified: the inspector shows only files (the Usage and Session tabs are gone), the session total cost is no longer shown, and the shared home terminal, terminal-based session launching, and custom agents were removed.

### Fixed

- Codex and Claude permission settings are applied and restored correctly.
- Text typed while an image is being prepared is no longer lost.
- Fixed problems when a session was deleted or the app quit while a session was still starting.

### 新機能

- 新規チャットの画面を追加しました。⌘N やプロジェクトの ＋ で開き、最初のメッセージを書いてから、送信先のプロジェクト・モデル・effort・権限・既存ディレクトリか新しい worktree かを選んで送れます。入力欄の下に提案のチップと「履歴から再開…」（過去に worktree で進めた会話も含む）を並べました。
- タブをプロジェクトごとにまとめました。上段がプロジェクト、下段がそのプロジェクトのチャット・ターミナル・変更・ファイル・ブラウザ・シミュレーターです。
- 全ハーネスの使用量をウィンドウ下部のバーに出すようにしました。既定は横棒で、設定で数値（%）に切り替えられます。
- 見た目を整えました。白黒のアクセント、軽くしたヘッダー、なめらかなサイドバーの開閉、新規チャットのドット書体の見出しです。
- 画像の添付を 20MB まで受け付け、解像度を落とさずに送るようにしました。
- コマンド一覧で、長い説明を選択中の行で横に流して全文を読めるようにしました。
- 機能を整理しました。右サイドバーはファイルだけになり（「使用量」「セッション」のタブを廃止）、セッションの総コストの表示、ホームで開く共通ターミナル、ターミナルでエージェントを始めるメニュー、カスタムエージェントを廃止しました。

### 修正

- Codex と Claude の権限の設定が正しく適用・復元されるようにしました。
- 画像の準備中に入力した文章が消える問題を修正しました。
- セッションの起動中に削除やアプリの終了が重なったときの不具合を修正しました。
