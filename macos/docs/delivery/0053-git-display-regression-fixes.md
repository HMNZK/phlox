---
status: completed
last-verified: 2026-10-15
---

# 実アプリで見つかった Git 表示3件の修正

## 対応範囲

1. 同じコミットを両区画へ置いた修正前の画面外テストで、グラフ行のAX識別子が消える現象を再現した。履歴の区画とコミット行全体に区画を区別するIDを付け、展開ファイルのAX識別子も分けた。
2. 現在ブランチの先行数は正のときだけ表示する。
3. 子タブ列とウィンドウ見出しで共有する名前を「変更」／Changesに固定した。数字の原因はタブの作成順ではなく変更ファイル数だった。日本語では翻訳ヘルパーがキーをそのまま返すため、日本語名を明示し、英語は既存の `tab.changes` を使う。

依頼3件に未実装項目や要件・見本からの逸脱はない。新しい操作部品・文言・設定は追加していない。既存の「Changes 1」の期待値は、今回の明示要件に従い「Changes」へ変更した。

## 今回変更・追加したファイル

既存の未コミット変更全体ではなく、今回触ったファイルだけを記載する。

- `macos/Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/GitInspectorView.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/GitHistoryViews.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Tabs/SessionTabsContainer.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift`（古い件数表示のコメントのみ）
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/GitDisplayRegressionTests.swift`（新規）
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/ProjectTabsPresentationTests.swift`
- `macos/docs/architecture/terminal-editor-panels.md`
- `macos/docs/adr/0210-git-section-row-identity-and-stable-changes-title.md`（新規）
- `macos/docs/adr/README.md`
- `macos/docs/delivery/0053-git-display-regression-fixes.md`（本書・新規）

資料はコード修正前にarchitectureとADRを更新した。既存ADRの決定本文は変更していない。

## 追加したテスト

Swift Testingの2テストを追加し、既存の日英の名前テストを更新した。

- 同一コミットを両区画で4回展開／折りたたみし、コミット行と展開ファイルのAX識別子が重ならないこと、札の内容、グラフ行の高さ、線を置く左余白、先頭の余分な空白の不在を検査する。
- 変更件数0〜3でタブを繰り返し開閉・再選択し、1枚だけを保持して名前が日英で固定されることを検査する。

## 実行コマンドと結果

作業ディレクトリは指定worktree。テスト実行中のソース編集と、全件検査の再実行は行っていない。

| コマンド | 結果 |
|---|---|
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests ProjectTabsPresentationTests" ~/.agents/scripts/compact-test git-display-red macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1、11テスト・8件の問題。タブ名の不一致と、AX有効化が不足したテスト準備の問題を検出 |
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests" ~/.agents/scripts/compact-test git-display-reproduce macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1、1テスト・3件の問題。AX有効化後もグラフ行IDが消え、行が混同される現象を修正前に再現 |
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests ProjectTabsPresentationTests" ~/.agents/scripts/compact-test git-display-focused macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1、11テスト・8件の問題。行IDの分離は成功。AX静的テキストをlabelだけで調べたテスト準備の問題と、日本語名が `tab.changes` になる問題を検出し修正 |
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests ProjectTabsPresentationTests" ~/.agents/scripts/compact-test git-display-focused-2 macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、11テスト成功 |
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests ProjectTabsPresentationTests" ~/.agents/scripts/compact-test git-display-geometry macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、11テスト成功。先頭の空白・ファイル左余白の検査を追加した最終コード |
| `PHLOX_INTEGRATION_FIX_SNAPSHOTS=1 SWIFT_TEST_FILTER="GitDisplayRegressionTests" ~/.agents/scripts/compact-test git-display-snapshot macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、1テスト成功。画面外の画像を1回保存し、実画像で線・札・空白の不在・↑0の不在を確認 |
| `SWIFT_TEST_OUTPUT=full ~/.agents/scripts/compact-test --full git-display-all macos/scripts/run-swift-tests.sh DashboardFeature > .build/git-display-all-tests.log 2>&1` | 終了0。本体2,135件（204スイート）＋実Git41件（4スイート）、計2,176件。既存の既知の問題1件を報告。全件実行はこの1回のみ |
| `/opt/homebrew/bin/xcodegen generate`（`macos`で実行） | 終了0 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGTWBuild build > ../.build/git-display-debug-build.log 2>&1`（`macos`で実行） | 終了0、`BUILD SUCCEEDED`。実行は1回。`Metadata extraction skipped. No AppIntents.framework dependency found.` の警告2件 |
| `git diff --check` | 終了0 |

画像: `.build/integration-fix-snapshots/git-display-all-sections-expanded.png`。

## 検証範囲と制限

`Package.swift`・`macos/project.yml`・`macos/scripts/run-swift-tests.sh`とCI設定を確認した。対象に独立して適用するlint／静的解析設定は見つからなかった（未設定）。Swiftのコンパイル・型検査は指定のパッケージテストとアプリビルドで確認した。

実アプリの起動とXCUITestは実施していない。UIは画面外のAppKit／SwiftUI描画とAXで検証した。入力ソース・`.env*`・既存アプリのプロセスは操作していない。作業リポジトリでcommit・stash・reset・checkout・merge・rebaseは実行していない。

既存の `GitHistoryWorkflowTests.GTWRegression_改名前の名前を再利用しても利用順を混同しない` は、ブランチ旧名の再利用後の並び順について `withKnownIssue` で登録済みの失敗を1件報告している。今回そのテストや処理は変更していない（ADR 0209の既知の制限）。

全件ログには、未コミットのworktree削除の拒否（`contains modified or untracked files`）と未マージブランチの削除の拒否（`is not fully merged`）も出た。いずれも `WorktreeIsolationSpawnTests` が一時リポジトリで意図して失敗を起こし、警告と保護を検査した出力で、その2テストは成功した。

今回の3件について、上記の検証範囲で未解決の問題は検出していない。リポジトリ直下の `AGENTS.md` と `karpathy-CLAUDE.md` は存在しなかったため、会話で与えられた規約と `macos/docs/README.md` に従った。

## 「↑0」の再発テストの修正（2026-10-15）

レビュー `/tmp/phlox-orch/gtw-ui-review-out.md` の指摘に対応した。先のAX値による「↑0」不在検査は、ブランチ行のAX値が空文字で上書きされるため表示を保証していなかった。その検査を削除し、`GitDisplayRegressionTests` に画素比較のSwift Testingテストを1件追加した。

既存の `GitHistoryFixture` で先行数0件／1件を作り、製品の `branchRow` を `ImageRenderer` で幅340pt・暗色・2倍の画面外描画にする。右端48ptの画素が、0件では文字なし、1件では `Text("↑1")` の参照描画と一致することを検査する。参照描画どうしが異なることも検査する。関連architectureをテスト変更前に更新した。既存の製品判断を置き換えないため、新しいADRは追加しない。

| コマンド | 結果 |
|---|---|
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests" ~/.agents/scripts/compact-test gtw-display-render macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、2テスト成功 |
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests" ~/.agents/scripts/compact-test gtw-display-mutation macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1、2テスト中1件失敗。表示条件だけを旧 `if branch.current` に一時変更すると、0件の行が文字なしの参照描画と一致せず失敗。1件の検査は失敗しなかった |
| `SWIFT_TEST_FILTER="GitDisplayRegressionTests" ~/.agents/scripts/compact-test gtw-display-restored macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、2テスト成功。失敗時に画素配列全体を出力しないよう、比較結果をBoolに束縛した後の最終テストコード |
| `SWIFT_TEST_OUTPUT=full ~/.agents/scripts/compact-test --full gtw-display-dashboard-all macos/scripts/run-swift-tests.sh DashboardFeature > macos/Packages/DashboardFeature/.build/gtw-display-dashboard-all.log 2>&1` | 終了0。全件はこの1回のみ。本体Swift Testingは2,136件・204スイート、実Git系は41件・4スイート。XCTestは4件中3件成功・1件既定スキップ |
| `git diff --check` | 終了0 |

全件のSwift Testingには既定スキップ17件があり、全件中の各テストをすべて実行したという意味ではない。既存のブランチ名再利用後の並び順の既知問題1件も報告された。これらのテストや条件は変更していない。実Git系の削除拒否の警告2件（未コミットworktree／未マージブランチ）は、保護を検査するテストで意図した出力であり、その2テストは成功した。

`GitHistoryViews.swift` は一時変更の前後でSHA-256が `42bbc7236c02eec526d98defed8dbb58316218c5bd19c9ef92f0ce1439acb5c4` と一致した。製品コードの変更は残していない。今回の変更ファイルはこの報告、`architecture/terminal-editor-panels.md`、`GitDisplayRegressionTests.swift` の3つ。今回の依頼の未実装項目・モックからの逸脱はない。画像保存・アプリビルド・アプリ起動は指定どおり実施していない。独立したlint／静的解析は対象に適用する設定が見つからず未設定。今回追加した描画検査について未解決の問題は検出していない。
