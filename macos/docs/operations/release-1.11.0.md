# Phlox 1.11.0（build 33）リリース記録

## 状態

公開手順中。ユーザーがリリースを指示した（2026-10-16）。`ios/` の未コミットの資料はコミットせずに残す。配布物と検証ログはリポジトリの `.build/releases/1.11.0/` に保持する。

## 変更

1.10.0（`b38709d9`）から `25843165` までの変更。主なもの:

- プロジェクトごとの下部ターミナルのパネル（⌘J・⇧⌘J）と既定のシェルの設定。ユーザー用ターミナルの Ctrl-C・サイズ変更・日本語の修正（ADR 0201）。
- 右サイドバーの Git タブ（ADR 0202〜0210）とファイルツリーのファイル操作。
- 新規チャットの開始ブランチ・コミット・タグの選択、一覧と下部パネルの外枠の廃止。
- ターミナルの Option+←/→ と、大量出力の欠落・誤応答の修正（ADR 0212。出力を捨てずに読み取りを止める流量制御）。Ghostty と Metal 描画は見送り（ADR 0211・0213）。
- Claude 使用量の通知と補完取得（ADR 0214）、長い会話のサイドバー開閉の描画抑制（ADR 0215）。
- 質問カードの数字入力と表示切れの修正。

## 検証

- パッケージ正本ゲート（`macos/scripts/run-swift-tests.sh`）：AgentDomain 570件、DesignSystem 203件、MessageStore 44件、PTYKit 53件、TerminalUI 112件、SessionFeature 1,187件、DashboardFeature 本体（既存の known issue 1件。件数はラッパーの要約に出ない）と実git41件、SimulatorBridgeKit 20件が成功。スクリプトの終了は OK。
- シミュレーターの許可リスト検査成功（Xcode 17C52 × iOS 26.2）。
- Release ビルド成功（署名無しビルド・後段署名）。1 回目はシェルの PATH に xcodegen が無く生成前に停止したため、PATH を補って再実行した。
- 本体・DMG とも公証 Accepted、stapler validate 成功、Gatekeeper accepted（`source=Notarized Developer ID`）。本体の `codesign --verify --deep --strict` も成功。配布物の版は 1.11.0 / build 33。
- 本体公証 ID：`68b3c646-c8a8-40b9-ad4b-5e36eba2ad4b`。DMG 公証 ID：`428c9852-d601-4cc3-a185-b7315922b784`。
- Release 署名検査4件成功（`test_simulator_bridge_signing.sh`、公証後）。
- Sparkle ZIP は staple 後のアプリから作り、Ed25519 署名を本体に埋め込んだ公開鍵で検証して成功（CryptoKit による手元の検証。リポジトリのテストには未登録）。
- 実画面：下部パネル・Git タブ・ターミナル（日本語・Ctrl-C・Option+←/→・大量出力の後の残り文字なし・`yes` のメモリ横ばい）は Debug ビルドで確認済み。エージェント実行中の閉じる確認、⇧⌘J の対応待ちへの移動、変更行の右クリックメニューは未確認。
- lint・独立した静的解析：未設定。

## 配布物

| ファイル | バイト数 | SHA-256 |
|---|---:|---|
| Phlox.dmg | 32509877 | `1ac24d6e460f4c65266887b99d8c60cccf4f615ff1860cbdf5cae6fd11a84ee8` |
| Phlox-1.11.0.zip | 27458446 | `8f119baaa10134e6398097a6d4b1081f549b717461a45daee84651afbead1b50` |

## Release notes

### New

- A terminal panel at the bottom of each project. Toggle it with ⌘J; ⇧⌘J jumps to the next item waiting for you. Settings can choose the default shell.
- A Git tab in the right sidebar. A commit box sits at the top, + stages a file so only staged files are committed, and there are sections for history, branches, stashes, and a graph.
- Create, rename, and delete files and folders in the file tree.
- The new chat screen can choose the starting branch, commit, or tag for a new worktree.
- In terminals, Option+←/→ moves by word.
- Claude usage now updates from notifications during a chat and fills any gap within a minute. An expired value is shown as unknown instead of a stale number.
- A lighter look: the outer borders of the list and the bottom panel, and the thick border of the chat input, are gone.

### Fixed

- Ctrl-C, window resizing, and Japanese text now work correctly in the user terminal.
- Large output in a terminal is no longer cut, and stray text such as `65;4;1;2;6;21;22;17;28c` no longer appears at the prompt afterwards.
- Digits can be typed in the free-text field of question cards, and questions are no longer cut off when the chat area is short.
- Opening and closing the sidebar is smoother in long conversations.

### 新機能

- プロジェクトごとに画面下部へターミナルのパネルを追加しました。⌘J で開閉し、⇧⌘J で次の対応待ちへ移れます。既定のシェルは設定で選べます。
- 右サイドバーに Git タブを追加しました。上部にコミット欄があり、＋で登録したファイルだけをコミットします。履歴・ブランチ・スタッシュ・グラフの区画もあります。
- ファイルツリーでファイルとフォルダの作成・名前の変更・削除ができるようになりました。
- 新規チャットで新しい worktree を作るとき、開始するブランチ・コミット・タグを選べるようになりました。
- ターミナルで Option+←/→ による単語単位の移動ができるようになりました。
- Claude の使用量を、会話中の通知で更新し、足りない分は 1 分以内に補って取得するようにしました。期限切れの値は古い数字のままにせず「不明」と表示します。
- 見た目を軽くしました。一覧と下部パネルの外枠、会話の入力欄の太い枠をなくしました。

### 修正

- ユーザー用ターミナルで Ctrl-C・ウィンドウのサイズ変更・日本語が正しく動くようにしました。
- ターミナルで大量の出力が途中で欠けることと、その後のプロンプトに `65;4;1;2;6;21;22;17;28c` のような文字が残ることを修正しました。
- 質問カードの自由入力欄で数字を打てない問題と、会話欄が低いと質問が切れる問題を修正しました。
- 長い会話でのサイドバーの開閉を軽くしました。
