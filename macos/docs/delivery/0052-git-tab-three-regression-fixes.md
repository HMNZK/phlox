---
status: completed
last-verified: 2026-10-15
---

# Git タブ再レビューの残件3件の修正

対象レビュー: `/tmp/phlox-orch/gwAB-rereview-out.md`。対象要件は GW-3・8・11・14・15。

## 変更

1. 一括ステージは削除を追加より先に実行する。一括解除は対象全体を分類し、追加の削除後に HEAD の項目を子から親へ復元する。同じ深さの復元は指定順を保つ。再帰削除と強制置換は追加せず、選択外の子を保護する。失敗時も共有一覧を読み直して Git の理由を表示する。
2. グラフの続きを読むは必要件数を先頭から再取得し、一覧とレーンを置き換える。外部コミット後のページ連結による重複を防ぐ。
3. ローカル参照の reflog の改名記録から、HEAD reflog の切り替え先を現在名へ引き継ぐ。現在のブランチは先頭にする。

## 変更・追加ファイル

以下は今回の作業分。既存の未コミット変更全体を指すものではない。

- `macos/Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/GitWorkflowService.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/WorkingTreeService.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Editor/EditorPanelViewModel.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/GitStagingTests.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/GitHistoryWorkflowTests.swift`
- `macos/docs/architecture/terminal-editor-panels.md`
- `macos/docs/adr/0206-git-history-branches-stashes-and-graph.md`
- `macos/docs/adr/0208-git-history-review-corrections.md`
- `macos/docs/adr/0209-git-batch-order-and-history-continuity.md`（新規）
- `macos/docs/adr/README.md`
- `macos/docs/delivery/0052-git-tab-three-regression-fixes.md`（本書・新規）

資料は実装前に architecture・ADR 0206/0208 を更新し、ADR 0209 を追加した。実装後にテスト範囲と本記録を追記した。

## 追加テスト

Swift Testing の8テスト（引数別11ケース）を追加した。

- `GitStagingTests`: ファイル→同名ディレクトリの一括ステージと解除（各正順／逆順）、ディレクトリ→ファイルの一括操作、途中解除失敗後の一覧更新、ステージ失敗後の外部 index 変更の再取得。
- `GitHistoryWorkflowTests`: 現在／非現在ブランチの改名と現在ブランチの先頭配置、連続改名、205件の履歴を200件取得した後の外部コミットと続きを読む（重複なし・先頭と末尾・更新後件数）。

既存の選択外の子の保護・競合拒否・部分ステージ保護テストも関連スイートに含めて実行した。

## 実行コマンドと結果

作業ディレクトリは指定 worktree。テスト中にソースは変更していない。

| コマンド | 結果 |
|---|---|
| `SWIFT_TEST_FILTER="GTWRegression" ~/.agents/scripts/compact-test git-tab-red macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1。追加途中の7テスト、11件の問題を報告。一括操作、失敗後一覧、グラフ重複、現在ブランチの改名を再現 |
| `SWIFT_TEST_FILTER="GTWRegression" ~/.agents/scripts/compact-test git-tab-red-expanded macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1。8テスト、17件の問題を報告。非現在／連続改名の利用順と逆向きの置換も再現 |
| `SWIFT_TEST_FILTER="GitStagingTests GitHistoryWorkflowTests" ~/.agents/scripts/compact-test git-tab-focused macos/scripts/run-swift-tests.sh DashboardFeature` | 終了1。42テスト中1テスト失敗。履歴17件は成功。同じ深さの復元順を変えたため、途中解除のテストで `b.txt` が解除されない問題を検出。指定順を保つよう実装修正 |
| `SWIFT_TEST_FILTER="GitStagingTests" ~/.agents/scripts/compact-test git-tab-staging macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0。25テスト成功 |
| `~/.agents/scripts/compact-test --full git-tab-all macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0。本体2,132件（203スイート）と実Git41件（4スイート）、計2,173件成功。全件はこの1回のみ |
| `git diff --check` | 終了0 |

## 範囲と未検証

- 依頼3件に未実装項目や要件から外れた判断はない。グラフは依頼で許容された先頭再取得方式を選んだ。
- 見た目・操作部品・文言は変更していない。指示の条件に従い、画像生成・アプリビルドは対象外。アプリ起動・XCUITest は実施していない。
- `Package.swift`・`macos/project.yml`・検証スクリプトとCI設定を確認。対象に適用する独立した lint／静的解析設定は見つからなかった。Swift のコンパイル・型検査は指定テストスクリプトのパッケージビルドで実施。
- 改名の引き継ぎは Git に残る reflog の範囲に限る（ADR 0209）。グラフは追加時に取得済み分も読み直す。
- 未解決の問題は今回の検証範囲では検出していない。
- commit・stash・reset・checkout・merge・rebase は作業リポジトリに実行していない。既存の未コミット変更は保持した。
