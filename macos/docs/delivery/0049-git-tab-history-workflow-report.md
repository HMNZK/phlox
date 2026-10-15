---
status: completed
last-verified: 2026-10-15
---

# Git タブ後半（GW-7〜15）の実装・検証記録

GW-7〜15 と ⇧⌘R・⌥⌘S のコードを追加した。既存の未コミット変更を維持し、作業リポジトリで commit・stash・reset・checkout・merge・rebase は実行していない。アプリの起動・終了、入力ソースの変更、XCUITest は行わない。

## 変更したファイル

以下は今回編集したファイルだけを示す。作業開始前からの未コミット変更も含むファイルでは、その変更を保持した。

| 区分 | ファイル（macos/ からの相対パス） |
|---|---|
| アプリ | `App/Localizable.xcstrings`、`App/PhloxApp.swift` |
| DashboardFeature / Dashboard | `Sources/DashboardFeature/Dashboard/DashboardView.swift`、`InspectorView.swift` |
| DashboardFeature / Editor | `Sources/DashboardFeature/Editor/EditorPanelView.swift`、`EditorPanelViewModel.swift`、`GitCommitPanel.swift` |
| DashboardFeature / WorkingTree | `Sources/DashboardFeature/WorkingTree/GitHistoryTypes.swift`（追加）、`GitHistoryViews.swift`（追加）、`GitInspectorView.swift`、`GitTabPolicy.swift`、`GitWorkflowService.swift`、`WorkingTreeService.swift`、`WorkingTreeTypes.swift` |
| DesignSystem | `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift` |
| DashboardFeature のテスト | `Tests/DashboardFeatureTests/GitHistoryWorkflowTests.swift`（追加）、`GitHistoryPolicyTests.swift`（追加）、`GitHistoryRenderTests.swift`（追加）、`FocusBorderRenderTests.swift`、`GitWorkflowRenderTests.swift` |
| 資料 | `docs/adr/0169-editor-panel-git-write-operations.md`、`0206-git-history-branches-stashes-and-graph.md`（追加）、`docs/adr/README.md`、`docs/architecture/terminal-editor-panels.md`、`dashboard-pane-layout.md`、`docs/specs/bottom-panel-shell-files-git.md`、本記録 |

DashboardFeature のソース・テストの基準ディレクトリは `Packages/DashboardFeature/`。

## 要件と実装

| 要件 | 実装 |
|---|---|
| GW-7 | 現ブランチの履歴を50件ずつ取得し、続きを読み込む。作者・相対時刻・ID、ファイル展開、IDコピーと起点指定のブランチ作成 |
| GW-8 | ローカルのブランチ一覧・現在の印、作成／切り替え／改名／削除。作成のReturnは切り替えまで行う |
| GW-9 | リモート別一覧、HEAD別名の除外、追跡付きチェックアウト、既存ローカルへの切り替え、全リモートの取得 |
| GW-10 | 未追跡を含むスタッシュ、任意メッセージ、一覧／ファイル／適用／取り出し／削除。IDを保持して番号移動に対応 |
| GW-11 | 全参照の先頭200件から親のレーンを計算。分岐・合流・複数親、白黒の線、ブランチ・タグの札 |
| GW-12・13 | DSDialogで削除・取り出しと実行中セッションの注意を1枚にまとめる。キャンセルが既定。プロジェクトの実フォルダにいるrunning状態だけを対象にし、worktreeを除外 |
| GW-14 | Gitの理由を既存の上部エラーへ表示。自動の退避・強制・衝突解消はしない |
| GW-15 | 操作の成功／失敗後と既存GT-7のrefreshで開いた区画を再取得。閉じた区画は無効化して次回展開時に読む |
| 履歴の差分 | 既存の変更タブにコミットID／スタッシュ名を渡す。履歴の本文は読み取り専用 |
| キー | 既存のGit表示中だけのFocusedValueでメニューへ接続。⇧⌘Rは取得、⌥⌘Sはスタッシュ入力 |

## テストを追加した範囲

- `GitHistoryWorkflowTests`: 一時リポジトリで各読み取りと書き込み、50件の続き、初回／空、改名・削除・バイナリ、切り替え失敗、未マージ削除、スタッシュ衝突、未追跡、番号移動、遅延取得、初回コミット前の新規ブランチ。
- `GitHistoryPolicyTests`: 分岐・合流・3親・表示外の親、札の束ね、確認の条件、実行中とworktreeの区別、表示中の区画／展開行だけの操作。
- `FocusBorderRenderTests`: 実物の画面外ウィンドウに上下・Return・Spaceを送り、履歴行の移動／展開とindex保全を検査。
- `GitHistoryRenderTests`: 通常・空・展開・確認・失敗・グラフ・履歴差分を260/340pt、日英、明暗で144画像に描画する専用経路。

## 実行コマンドと結果

テストはすべて `~/.agents/scripts/compact-test <ラベル> macos/scripts/run-swift-tests.sh <パッケージ>` 経由。途中のテストは `SWIFT_TEST_FILTER` を指定し、実行中にソースを編集していない。

| ラベル／コマンド | 結果 |
|---|---|
| `git-history-compile` / filter `GitInspectorTests\|GitStagingTests\|GitWorkflowTests` | 終了1。履歴パーサーの型推論時間超過とthrow式の指定漏れ。修正した。テストは未実行 |
| `git-history-focused` / filter `GitHistory\|GitInspectorTests\|GitStagingTests\|GitWorkflowTests`（最初） | 終了1。新しいテストの `completed(exitCode:)` の引数漏れ。修正した。既存テストの非推奨AX API警告と新規テストの不要なtry警告が出た。新規のtry警告は修正 |
| 同ラベル・同filter（修正後） | 終了0、76件／6スイート成功 |
| `git-history-boundaries` / filter `GitHistory\|FocusBorderRenderTests\|EditorPanelGitCommitUITests` | 終了0、31件／5スイート成功 |
| `git-history-preflight` / filter `GitHistory\|FocusBorderRenderTests\|GitStagingTests\|GitWorkflowTests` | 終了0、65件／6スイート成功 |
| `git-history-final-boundaries` / filter `GitHistoryWorkflowTests\|GitHistoryPolicyTests\|GitStagingTests` | 終了0、32件／3スイート成功 |
| 全件 DashboardFeature・DesignSystem（1回） | 終了0。Swift Testing出力: DashboardFeature本体2113件／203スイート、実Git41件／4スイート、DesignSystem199件／38スイート。XCTest出力:4件、うち1件skip、失敗0。Swift Testingにも既存17件skipあり。`.build/git-history-full-tests.log` に記録 |
| `git-history-graph-ref-boundary` / filter `GitHistoryWorkflowTests\|GitHistoryPolicyTests` | 終了0、16件／2スイート成功。全件実行後に見つけたスタッシュ内部のコミットがグラフに混ざる問題を修正し、この対象テストを追加して再検証した。全件コマンドは追加実行していない |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=git-history SWIFT_TEST_FILTER=GitHistoryRenderTests` / `git-history-images` | 終了0、1テスト／1スイート成功、144 PNG生成。画像出力は1回。`.build/git-history-images.log` に記録 |
| `/opt/homebrew/bin/xcodegen generate`（作業ディレクトリmacos） | 終了0、1回。`Phlox.xcodeproj` を生成 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGTWBuild build`（作業ディレクトリmacos） | 終了0、`BUILD SUCCEEDED`。実行1回。警告2件: `Metadata extraction skipped. No AppIntents.framework dependency found.`。エラー0件。`.build/git-history-debug-build.log` に記録 |
| `git diff --check` | 終了0 |

## 要件・見本から変えた判断

- 取得は `fetch --all` とし、`--prune` は付けない。要件は参照の削除を求めていないため（ADR 0206）。「originだけ取得」は追加していない。
- 閉じた区画は初回展開まで取得せず、件数も未取得の間は表示しない。全履歴を常時読む負荷を避けるため（ADR 0206）。
- 最近使ったブランチの順は、既存のGitBranchSwitcherと起点選択と同じ最終コミット時刻の降順。チェックアウト履歴を別に管理しない。
- グラフは要件GW-11の「コミット行と同じ」に従い、作者・相対時刻・短縮IDのある行にした。見本の密な28ptのグラフ行とは高さが異なる。
- ブランチ名の不正／重複はGitの理由を上部に表示し、入力値を残す。見本X8の入力直下への独立したエラー表示は追加していない。
- リモートのグループ単位の折りたたみと「何分前に取得」は追加していない。要件GW-9のリモート別の一覧と、区画単位の開閉を対象にした。

## 画像比較と未解決事項

画像は `.build/git-history-snapshots/` の144 PNG。比較用一覧は同フォルダの `contact-sheet.jpg`。見本 `GS_Sections`、`GS_Graph`、`GS_Dialogs` をブラウザで表示し、通常の各区画、空、展開、確認、失敗、履歴差分の出力を確認した。144画像のPNG形式とファイル存在をテストし、視覚確認は代表画像に限定した。

見本との視覚差分:

- 通常／空／開いたファイル／比較元の札と、白黒の分岐・合流を表示できる。260ptでも短縮IDと起点の札を表示する。
- グラフは見本より行が高い。作者と時刻・IDを含むため。ファイル展開部分の線の途切れは、後続の[再レビュー修正](0050-git-tab-rereview-fixes.md)で解消し、日英の代表画像で連続を確認した。旧画像の翻訳用ファイル再利用と追加生成の状況も同報告を参照。
- 確認は既存DSDialogの規則により短いボタン2個が横並びとなる。見本の縦2段とは異なる。キャンセル既定は要件どおり。実行中セッションはIDで表示しており、見本のセッション名とエージェント名の対象カードは作っていない。
- 画面外のテストホストではアプリアイコンがフォルダの代替画像となる。実アプリのアイコン表示はアプリ未起動のため未検証。
- 入力直下の重複エラー、リモートグループの開閉と最終取得時刻は、上記の判断により見本と異なる。

アプリのビルドは成功。アプリは起動しないため、実アプリのメニューからのキー入力は未検証。lint・独立した静的解析の設定は対象パッケージに見つからず未設定として扱う。Swiftコンパイラーと設定済みテスト／ビルドを実行した。

全件コマンドで既存のスキップが18件（XCTest1件、Swift Testing17件）あった。Release専用のスクロール計測、性能計測、実エージェント／統合環境を必要とする既存の条件付きテストであり、今回テストのスキップ・期待値の緩和・削除は追加していない。これらを実行済みとは扱わない。

確認用のブラウザタブとHTTPサーバーは閉じた。Playwright MCPの起動時刻と親子関係をpsで照合し、今回のCodex（36125）が起動した36351／36664だけを終了した。終了後のpsで消失を確認し、別のClaude／Cursor配下のプロセスは維持した。
