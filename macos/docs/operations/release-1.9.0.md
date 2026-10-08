# Phlox 1.9.0（build 30）リリース記録

## 状態

準備中・未公開。対象は `dev` の開発変更と Haiku 5.5 対応。
2026-10-08 の公証認証確認で Apple が HTTP 403（必要な契約が未署名または失効）を返した。契約更新後に公証を再確認する。

## 検証

- Haiku の設定・切替：対象5テスト成功。
- モデル一覧・API：ControlServer 152テスト成功。
- AgentDomain：579テスト成功。
- パッケージ検査：正本 `macos/scripts/run-swift-tests.sh` の初回実行では SessionFeature の旧 Haiku 前提の1テストが3問題で失敗。入力を Haiku 4.5 の明示 ID に変更し、Haiku 5.5 の切替検査を追加した後、SessionFeature 全数1,127件が成功。他は AgentDomain 579件、DesignSystem 193件、MessageStore 42件、DashboardFeature 本体1,981件＋実git26件、SimulatorBridgeKit Swift Testing 16件が成功。初回ゲート自体の終了コードは1であり、修正後は SessionFeature を個別に再検証した。
- Release：1.9.0 / build 30 のビルド成功。Developer ID による内側からの署名と `codesign --verify --deep --strict` 成功。本体とXPCの署名・権限・混入検査4件成功。
- シミュレーター：専用品質ゲート `verify-simulator-display.sh` 成功。前提のDebugビルドを作る前の補助検査は4失敗・4エラーとなったが、ゲートで所定のビルドを作成した後、補助検査・許可リスト・署名検査が成功。
- 画面外の画像：`PHLOX_DESIGN_SNAPSHOTS=1` の DesignSnapshotRenderTests 2件成功。ブラウザのURLポリシーがローカル見本HTML（file URL）の表示を拒否し、見本との画像比較は未確認。
- GUI：初回16件中14成功・2失敗。日本語合成入力を貼り付けに変更し、保存後のUndoをアプリへキー送信する形に修正。修正後の MarkdownBlockInteractionTests は6件成功・失敗0・スキップ0。初回16件の一括再実行はしていない。
- 公証・DMG・公開後確認：未実施。公証提出用の署名済みZIPを `.build/release-artifacts-1.9.0/Phlox-1.9.0.zip` に保持。
- lint・独立した静的解析：未設定。

旧 `.claude/verify.sh` での DashboardFeature 並列実行は画像配信テストの差分計算で停滞し、中断（終了コード1）。その画像テスト単独は0.175秒で成功。正本の直列実行の結果とは分けて記録する。

GUI 初回検査は16件中14件成功・2件失敗（Markdown 編集・大きいHTMLのUndo）。失敗時のAX記録では `typeText` の日本語入力が「編集した本文」ではなく「編汣ճ׶狆」となり、別の失敗には XCUITest の `InputSource` 選択処理のエラーが残った。日本語のテスト入力はクリップボードを保存・復元した貼り付けに変更し、閲覧専用のキー入力拒否検査はASCII入力で検査した。期待する保存バイト列・Undo・表示・入力拒否のアサーションは維持した。実際のIME操作の検証とは区別する。

## 公開前に残る確認

- Apple Developer の必要な契約への同意後、公証・ステープル・DMG・Sparkle署名・公開後確認。
- デザイン見本との比較。ローカルHTML表示の拒否を別手段で迂回しない。
- シミュレーターの実際のIME入力・回転・異常接続の配布前確認。
- ビルドには既存の非推奨API・Sendable・ViewBuilder・AppIntentsメタデータに関する警告がある。

上記の確認を終えるまで main への統合・公開は保留する。

## Release notes

### New

- Select Haiku 5.5 in Claude sessions and adjust its reasoning effort.
- Browse your working folder in the side panel. Open Markdown, source code, and HTML in tabs, and edit Markdown directly.
- Open web pages in an in-app browser with page search, zoom, and a shortcut to share the current page with an agent.
- Open an iOS Simulator in a session tab and interact with supported simulator configurations.
- GPT-6.1 Sol is available in the built-in Codex model list.

### Fixed

- Codex sessions show their current permission setting correctly.
- Copying messages and reading model and reasoning settings in the composer are easier.
- Page search focuses the search field and clears outdated results.

### 新機能

- Claude セッションで Haiku 5.5 を選択し、思考強度を変更できるようにしました。
- 作業フォルダのファイルをサイドパネルで参照し、Markdown・ソースコード・HTML をタブで開けます。Markdown は直接編集できます。
- アプリ内ブラウザにページ内検索・表示倍率・表示中のページをエージェントに伝える操作を追加しました。
- セッションのタブで iOS シミュレーターを開き、対応する構成で操作できるようにしました。
- Codex の内蔵モデル一覧に GPT-6.1 Sol を追加しました。

### 修正

- Codex セッションの現在の権限設定を正しく表示するようにしました。
- メッセージのコピーと、入力欄のモデル・思考強度の表示を使いやすくしました。
- ページ内検索を開いた際の入力先と、古い検索結果の扱いを修正しました。
