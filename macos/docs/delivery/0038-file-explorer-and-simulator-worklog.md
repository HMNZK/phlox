---
status: completed
last-verified: 2026-10-03
---

# 0038: ファイルツリー・マークダウン編集・HTML 表示・iOS シミュレーター 実装 worklog

> **このファイルの役割**: 2 つの設計書を実装する作業の記録。段ごとの担当・ブランチ・検証結果・未解決点を残す。
> 要件と設計は `specs/file-explorer-and-markdown-editing.md`（以下「ファイル設計書」）と `specs/embedded-ios-simulator.md`（以下「シミュレーター設計書」）。決定は ADR 0178・0179。

## 進め方

- 実装は Codex（gpt-6.1-sol・推論 medium）にヘッドレスで依頼し、PM（Claude）が設計書との照合と検証ゲートの実走で裏を取る。
- 2 つの機能は独立に進める。ブランチは `dev` から切った feature ブランチを、それぞれ別の worktree で使う。
- 各段で、触ったパッケージのテストを全数実行して green にしてから次の段へ進む。
- `dev` へのマージは、段ごとに検証結果を示してユーザーの承認を得てから行う。

## 段の一覧

| 段 | 内容 | 設計書 | ブランチ | 状態 |
|---|---|---|---|---|
| F1 | ファイルアクセスの基盤修正（symlink 包含・ルート固定・バイト比較と BOM・読み込み状態・`openFileTab` 共通化・終了／ウィンドウを閉じる確認・複数ウィンドウの未保存収集・文書の失効） | ファイル §3.2・§3.6・§5-1 | `feature/file-access-foundation` | dev へマージ済み（03d39b4） |
| F2 | ファイルツリー（Loader・Rows・Model・`InspectorTab.files`・View・⌃⌘B） | ファイル §3.3・§5-2 | `feature/file-tree` | dev へマージ済み（efb230a） |
| F3 | HTML 表示（遮断ルール・スキームハンドラ・遷移判定・`HTMLPreviewView`） | ファイル §3.5・§5-3 | `feature/html-preview` | dev へマージ済み（0e5423a） |
| F4 | マークダウンのブロック編集 | ファイル §3.4・§5-4 | `feature/markdown-blocks` | dev へマージ済み（9946458）。実画面で見つかった不具合の修正も dev へ（b51c50f） |
| F5 | 実画面確認 → `architecture/` へ蒸留 | ファイル §5-5 | — | 実画面確認済み（UI テスト 5 本成功）。`architecture/file-explorer-and-markdown-editing.md` へ蒸留済み |
| S1 | 関門: 最小の XPC サービスで連続表示・タップ・ドラッグ・キー入力・ホームを確認 | シミュレーター §7-1 | `feature/simulator-gate` | 一部通過（公証済み未確認）。試作を dev へマージ済み（fca4f49。途中の試行の画像は除外） |
| S2・S3 | `SimulatorBridgeKit`・`SimulatorCatalog` | シミュレーター §7-2・§7-3 | `feature/simulator-bridge-kit` | dev へマージ済み（90acb98） |
| S4 | 補助プロセス: 画面取得 → `SimulatorScreenView` 表示 | シミュレーター §7-4 | `feature/simulator-helper-display` | dev へマージ済み（7827813） |
| S5 | 入力送信（タップ・スワイプ・スクロール・キー・ホーム・`releaseAll`） | シミュレーター §7-5 | `feature/simulator-input` | dev へマージ済み（c7c35cb） |
| S6 | 子タブ・SimulatorHub・⌃⌘Y | シミュレーター §7-6 | `feature/simulator-tab` | dev へマージ済み（e68a226） |
| S7 | 許可リスト・非対応表示・版確認・再接続・診断・手順書 | シミュレーター §7-7 | `feature/simulator-allowlist` | dev へマージ済み（2a12340） |
| S8 | 実画面確認 | シミュレーター §7-8 | — | 実画面確認済み（UI テスト 3 本成功）。`architecture/embedded-ios-simulator.md` へ蒸留済み |

## 記録

（段が終わるごとに追記する）

### S1 関門（2026-10-02）

- 判定: **一部通過**。Developer ID 署名＋hardened runtime の試作（`macos/Prototypes/SimulatorGate/`）で、連続表示（約 30 秒）・タップ・ドラッグ（約 180pt）・キー（A・Shift+B で「aB」）・ホームを確認した。証拠は試作の `Records/`（画像・イベント記録）と `README.md`。
- §1.3 の仮説: surface は交代せず ID 239 のまま seed が 2317→3309 と更新され続けた。描画通知 993 回に対し surface の受け渡しは 1 回。`layer.contents` は初回設定のみ・同じ surface の再設定・nil 後の再設定のいずれでも表示が更新された。
- 未確認: 公証済みのアプリでの動作（外部送信のため未実施）・XPC の実通信バイト数（`NSXPCCoder` 以外で符号化できず測れなかった）・表示 FPS・回転・Simulator.app との共存・異常系。
- PM 確認: 試作の観測テスト `test_observations.py` を再実行して成功。ホスト側の画像でホーム画面とテストアプリ（ドラッグ 180・入力「aB」）が描画されていることを目視した。
- 作成した専用端末 4 台は shutdown 済み・未削除（名前 `Phlox-SimulatorGate-20261002-*`）。

### F1 基盤修正（2026-10-02）

- Codex が実装 → 独立レビュー（needs_changes: 回帰 2 件ほか）→ Codex が 10 項目を修正。PM 裁定: 外部削除後の「上書き」は親がルート内なら作り直す／受け付け済みの保存は失効の前に完了させる。
- PM 確認: `run-swift-tests.sh DashboardFeature` を実行。失敗は既存の 1 件だけ（下記）。Debug 版を別インスタンスで起動し、ウィンドウを閉じる確認シートとアプリ終了のアラートが出てキャンセルで残ることをスクリーンショットで確認。シートで「キャンセル」が下・既定でなかったため修正中。
- 未確認: 5 件を超える一覧・複数ウィンドウの見出し・⌘Q の連打・UI テスト（`Timed out while enabling automation mode.` で停止）。

### S2・S3（2026-10-02）

- Codex が実装 → 独立レビュー（HIGH 2 件: 大きな貼り付けで SIGPIPE によりプロセスが落ちる／XPC の許可クラスが広すぎて型偽装で落ちる）→ Codex が修正。PM 裁定: ⌘V は貼り付け成功時に押下と解放を 1 組で送る／余白に出たドラッグは端へ寄せる／物理キー番号での判定は維持。
- PM 確認: `swift test --package-path macos/Packages/SimulatorBridgeKit` で 19 件（swift-testing 16・XCTest 3）成功、`SimulatorCatalogTests` 10 件成功、`run-swift-tests.sh SimulatorBridgeKit DashboardFeature` で失敗は既存の 1 件だけ。

### 既存の失敗（dev でも再現）

- `ChatSessionViewModelTests.swift:1527` `chatSessionViewModel_codexDefaultsToFullAccessWhenNoPersistedOrServerProfile`: 期待 `:danger-full-access`・実際 `:workspace`。変更前の dev のコードで単独実行しても失敗する。テスト用の固定応答に sandbox の指定が残っているのが原因（Codex の分析）。別ブランチ `fix/codex-permission-test-fixture`（6b72605）で固定応答だけを直し、期待値は変えていない。そのブランチで `run-swift-tests.sh`（既定の全パッケージ）が全数成功。

### 決定（2026-10-02 ユーザー）

- 未保存確認の破棄ボタンは macOS 標準の破棄表示を使う（ファイル設計書 §3.8 に追記）。F1 でシートの「キャンセル」を既定・最上段に修正済み。

### F2・S4（2026-10-03）

- Codex がモデル混雑と利用上限で途中終了したため、ユーザー指示に従い Sonnet 5.5 が続きを仕上げた。上限のリセット後、修正は Codex に戻した。
- F2 の PM 確認: `xcodebuild`（Debug）成功、`run-swift-tests.sh DashboardFeature` 全数成功（1729＋実 git 25）。実画面で ⌃⌘B・並び・展開・開く・強調・キー操作を確認。独立レビューは needs_changes（壊れた symlink 1 本でフォルダ全体が読めない／未オープンのファイルを分割で開けない ほか）。
- S4 の独立レビューは needs_changes（本体に hardened runtime を付けたため ad-hoc の Debug 版が起動直後に落ちる／署名検査が Debug の実体を調べていない／接続を閉じずに手放すと画面取得が残る ほか）。本物の経路（XPC → 画面取得 → 表示）は、入口となる子タブが §7-6 で入るまで未実行。
- 後始末: dev へマージ済みの `feature/file-access-foundation`・`feature/simulator-bridge-kit`・`feature/simulator-gate`・`fix/codex-permission-test-fixture` の worktree とブランチを削除した。

- F2・S4 の PM 確認（修正後）: 両方とも `run-swift-tests.sh` 全数成功・Debug ビルド成功。F2 は壊れたリンク・ルート外・FIFO の行、空行の除去、開いた行からのキー選択、未オープンのファイルの右分割を実画面で確認（ルート外のツールチップは未確認）。S4 は ad-hoc の Debug 版が起動することを確認。
- **運用の決定（2026-10-03 ユーザー）**: 以後の段は、テスト・ビルド・実画面確認・独立レビューが通れば確認なしでコミットし dev へマージしてよい（verify・main には入れない）。

### 画面を奪わない検証の運用（2026-10-03 ユーザー指示）

- 実装・レビュー・検証は、ユーザーの画面を奪わない方法で行う: 処理は `swift test`、見た目は画面に出さない描画、実アプリは `open -g` で起動し、撮影は `screencapture -l`。
- 本物の入力が要る UI テスト（XCUITest など）は各段では実行せず `build-for-testing` までにとどめ、PM が段をまたいでまとめ、ビルド済みの成果物で一度に短時間で実行する（画面を奪う時間を最短にする）。
- S6 は Codex が Debug 版を前面で操作していたため途中で止め、この運用で再開した。

### F3・S5・S6・F4・S7（2026-10-03）

- F3: 独立レビュー（外部遮断・ページ JS 無効・ルート外を読まないことは実測で確認。iframe 内リンクのホバーとクリックの食い違い・リソースの上限なし読み込み等）を修正。PM 裁定: ホバーは公開 API（専用 WKContentWorld のユーザースクリプト）で実装、リソース上限 32 MB。テスト全数・ビルド成功で dev へ。
- S5: スクロールの過剰（100pt の入力で 537pt）を修正し、ハーネスで 81〜86pt を確認。テスト 2 回連続全数成功で dev へ。
- S6: レビュー（テスト不足・停止対象の取り違え等）を修正。既定の全パッケージ成功で dev へ。
- F4: レビューで致命 2 件（文字の行の直後に表がある文書を開くと落ちる／ソース表示の打鍵が例外）とデータ変化 1 件（先頭の U+FEFF が消える）を検出。修正中。
- S7: レビューで「未確認でも試す」が別端末に引き継がれる問題等を検出。修正中。PM 裁定: 許可リストの組は入力も対応のまま、§3.7 の実行記録を正式に書く／非対応表示の XCUITest は画面外描画の単体テストで代える（シミュレーター設計書 §5 を更新）／自動再接続は切断ごとに 1 回・60 秒に 3 回まで。
- 画面を奪う UI テストは各段で実行せず、PM がまとめて実行する（`HTMLPreviewInteractionTests` 3 本・`SimulatorTabUITests` 3 本・`MarkdownBlockInteractionTests` 2 本が待ち）。

### F4・S7 の完了と実画面確認（2026-10-03）

- S7: 再レビュー 2 回（入力ハーネスが未登録の組を検査できない退行・非対応表示のテストが文言とボタンを見ていない等）を修正し、dev へ（2a12340）。PM 裁定: 「未確認でも試す」の例外はセッション単位で Hub が保持（タブを閉じる・端末切替・アプリ終了で解除）。初回の組 17C52 × iOS 26.2 は未検証項目を残したまま登録（シミュレーター設計書 §3.3 に例外として追記）。
- F4: 再レビュー 5 回。主な修正は ⌘Z/⇧⌘Z がブロック編集・文書の取り消し履歴に届かない退行、ブロック単位の描画が文書全体の描画と食い違う問題（独自の Markdown 出力に置き換え、手元の実文書 10,629 件で不一致 0）、非同期解析の競合、大きな文書での同期解析の退行。dev へ（9946458）。
- F4 の既知の制限（表示だけ・ファイルの中身は変わらない）: `*` と `_` を意図して混ぜた入れ子の強調の一部（例 `*x(_[a](u)_)*`、`*_a_**b***`）は、ブロック単位の表示が文書全体の表示と異なる。実文書では未検出。
- 実画面の UI テスト（PM がまとめて実行。macOS の自動操作の認証はユーザーが画面で許可）: `HTMLPreviewInteractionTests` 3 本・`SimulatorTabUITests` 3 本は成功。`MarkdownBlockInteractionTests` は段落の余白クリックで編集が始まらない・Esc 後に編集欄が残る・入力先が切り替わらない、の 3 件を順に検出して修正し（b51c50f）、2 本を 2 回ずつ成功。
- 修正の往復中に UI テストを流さなかったため、退行がまとめ実行まで露見しなかった（`.claude/lessons.md` L-118）。
- 未検証: 公証済みビルドでの動作、端末内の日本語入力・4 方向の向き・実接続での異常系、VoiceOver の実操作。
- ADR 0179 を accepted にした（2026-10-03 ユーザー判断。公証済みビルドは未確認のまま）。
