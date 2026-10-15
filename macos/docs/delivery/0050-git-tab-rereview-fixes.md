---
status: active
last-verified: 2026-10-15
---

# Git タブ再レビュー4件の修正

対象は `/tmp/phlox-orch/gwA-rereview-out.md` の3件と、後半報告のグラフの線の途切れ。作業ブランチは `feature/git-tab-workflow`。既存の未コミット変更を維持し、コミット・ブランチ変更・マージは実行していない。リポジトリ直下にAGENTS.mdは存在せず、依頼文の共通規約とdocs/README.mdに従った。

## 変更したファイル

以下は今回触れたファイルだけ。開始前から存在する差分全体の一覧ではない。パスはmacos/相対。

| 区分 | ファイル |
|---|---|
| 翻訳 | `App/Localizable.xcstrings` |
| モデル・コミット欄 | `Packages/DashboardFeature/Sources/DashboardFeature/Editor/EditorPanelViewModel.swift`、`GitCommitPanel.swift`（同ディレクトリ） |
| Git | `Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/WorkingTreeService.swift`、`GitTabPolicy.swift`、`GitWorkflowService.swift`、`GitInspectorView.swift`、`GitHistoryViews.swift`（同ディレクトリ） |
| テスト | `Packages/DashboardFeature/Tests/DashboardFeatureTests/GitStagingTests.swift`、`EditorPanelGitCommitUITests.swift`、`GitWorkflowRenderTests.swift`、`GitHistoryRenderTests.swift`、`GitHistoryWorkflowTests.swift`（同ディレクトリ） |
| 資料 | `docs/architecture/terminal-editor-panels.md`、`docs/adr/0205-git-status-records-and-visible-row-actions.md`、`docs/adr/0207-git-conflicts-and-exact-index-entry-actions.md`（新規）、`docs/adr/README.md`、`docs/delivery/0049-git-tab-history-workflow-report.md`、本書（新規） |

## 依頼項目

| 項目 | 対応 |
|---|---|
| 1: 未マージの分離 | DD/AU/UD/UA/DU/AA/UUを通常分類より先に除外し、競合のパスと解消案内を別表示。通常の＋／−と一括操作の対象外。競合がある間はコミットを無効にして理由を表示。サービスから直接ステージ／解除／コミットを呼んでも拒否 |
| 2: 操作範囲 | 削除と改名元の補完は非再帰の `git rm --cached --quiet`。解除はHEADの完全一致項目だけを `update-index --add --cacheinfo` で復元。追加は非再帰の `rm --cached` で外す。子のステージが復元と衝突したら、Gitの失敗を出し、子を外さない |
| 3: 入力先 | 行操作完了時にも開閉を確認し、閉じていれば見出しへの入力先を維持 |
| 4: グラフ | ファイル一覧の展開領域へ、outgoingの到着レーンで縦線を継続。読込中と空でも展開領域の高さに追従 |

資料を先に更新し、ADR 0207でADR 0205の分類と操作範囲を置き換えた。その他の後半の機能は変更していない。

## 追加した検査

- `GitStagingTests`: 未マージ7種類の実index、一括ステージで未マージ項目が変わらないこと、メッセージと通常のステージ済みがあってもコミット不可、直接呼出の拒否。
- 同スイート: 削除＋同名ディレクトリの子、改名元＋同名ディレクトリの子についてステージ／解除の範囲を検査。子がステージ済みで復元できない場合も、子を外さず失敗を返すことを検査。
- `EditorPanelGitCommitUITests`: 差分取得を待機させ、その間に折りたたみ、＋と−の完了後のAX入力先が見出しと交わることと高さを検査。非表示の一覧全体を測る検査にはしていない。
- `GitWorkflowRenderTests`: 競合表示の8画像を追加し52画像へ。`GitHistoryRenderTests`の144画像と、同じ `git-rereview` の指定でまとめて生成できるようにした。
- `GitHistoryWorkflowTests`: スタッシュ衝突は通常の変更一覧にあるという旧期待を、競合専用一覧にあり通常の両一覧にはなく、メッセージがあってもコミット不可という要件に更新。スタッシュの保持・Gitの失敗表示・競合マーカーの保持の検査は維持。
- 両画像テストは古い翻訳用バンドルを削除してから最新カタログで作り直し、英語の競合の訳を検査する。初回の画像確認で古い翻訳の再利用を検出して修正した。
- 初回前の部分ステージ解除の既存テストは、実行コマンドの非再帰化とquiet指定に追従。拒否・理由・indexと作業ファイルの保持の期待は維持。

## 作業中の検証

実行はすべて `SWIFT_TEST_FILTER="…" ~/.agents/scripts/compact-test <ラベル> macos/scripts/run-swift-tests.sh DashboardFeature`。テスト実行中はソース編集を停止した。

| ラベル／filter | 結果 |
|---|---|
| GW再レビュー関連 / `GitStagingTests EditorPanelGitCommitUITests GitInspectorTests` | 終了1、49テスト／4スイート、2件失敗。翻訳キーの挿入処理がファイル形式に一致せず未登録。折りたたみテストのargumentDomainによる開閉固定と古いAX要素参照を修正。GitStagingは19件成功 |
| GW再レビュー再検証 / `EditorPanelGitCommitUITests GitInspectorTests GitWorkflowTests` | 終了0、56テスト／4スイート成功 |
| GW再レビュー回帰 / `GitStagingTests EditorPanelGitCommitUITests GitHistoryPolicyTests` | 終了1、35テスト／3スイート、＋／−の2ケース失敗。入力先の検査がNSHostingView全体（520pt）を測っていた。GitStaging20件とグラフ規則6件は成功 |
| GW入力先回帰 / `EditorPanelGitCommitUITests/ステージ処理中` | 終了0、1テスト／1スイート（＋／−の2ケース）成功。既存FocusBorderRenderTestsと同じAX focusedUIElementで入力先を検査するよう修正 |
| GWスタッシュ競合回帰 / `GitHistoryWorkflowTests` | 終了0、10テスト／1スイート成功。全件実行で見つかった上記の旧期待を修正後に実行 |

## 最終検証

| コマンド | 結果 |
|---|---|
| `~/.agents/scripts/compact-test --full GW最終全件 macos/scripts/run-swift-tests.sh DashboardFeature` | 1回実行、終了1。Swift Testing本体2118テスト／203スイート中1件失敗（上記スタッシュ衝突の旧期待）。実Gitは41テスト／4スイート成功。XCTestは4件、うち1件skip、失敗0。Swift Testingには既存17件skipあり。`.build/git-rereview-full-tests.log` |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=git-rereview SWIFT_TEST_OUTPUT=full SWIFT_TEST_FILTER='GitWorkflowRenderTests GitHistoryRenderTests' ~/.agents/scripts/compact-test --full GW最終画像 macos/scripts/run-swift-tests.sh DashboardFeature` | 1回実行、終了0。2テスト／2スイート成功、196 PNG（履歴144＋前半52）を書き出した。画像確認で古い翻訳用ファイルの再利用を検出。英語の競合などが日本語のままであり、画像を検証成功とは扱わない。`.build/git-rereview-images.log` |
| `/opt/homebrew/bin/xcodegen generate`（macos/） | 終了0。`Phlox.xcodeproj`を生成 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGTWBuild build`（macos/） | 1回実行、終了0、`BUILD SUCCEEDED`。App Intentsへの依存がないためメタデータ抽出を省略した警告が2件。`.build/git-rereview-debug-build.log` |
| `git diff --check` | 終了0 |

全件実行の失敗を修正後、履歴操作10テストは成功。全件コマンドの再実行は、依頼の「1回」を守って行っていないため、修正後の全件合格は未確認。

初回画像の視覚確認は `graph-expanded-340-dark-ja.png`、`graph-expanded-260-light-en.png`、`git-conflict-260-dark-en.png`。グラフの線は展開したファイル領域を途切れず通ることを確認した。英語の古い翻訳を解消する追加生成1回について確認中。初回生成前に翻訳用ファイルの更新を確認していなかった。

ビルドの警告原文（2箇所で同じ内容）: `warning: Metadata extraction skipped. No AppIntents.framework dependency found.`

画像の追加生成は承認待ち。翻訳用ファイルを作り直す修正と追加した英語のアサーションは、初回画像生成後に追加したため未実行。Debugビルドはアプリのビルドであり、この画像テストの実行確認には読み替えない。追加生成と修正後の全件再検証が終わるまでは、検証完了とは扱わない。

補助操作では、macos/で実行したログ検索にルート相対のパスを渡して1回失敗した。正しい作業場所で同ログを読み直し、画像テストの終了0・2テスト成功を確認した。

## 要件との差と未検証範囲

4件に対する未実装項目はない。`update-index`はpathspecでなく完全一致パスを受け取るコマンドなので、この引数だけ `:(literal)` を付けない（ADR 0207）。競合解消画面は依頼どおり追加していない。

XCUITestとアプリ起動は実行しない。メニューからの実キー操作は未検証。lint・独立した型チェック／静的解析コマンドは対象のPackage.swift・project.yml・scriptsに未設定。Swiftコンパイラーによる検査と設定済みのテスト・ビルドを行う。
