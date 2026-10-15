---
status: completed
last-verified: 2026-10-15
---

# Git タブ後半レビューの修正

対象は `/tmp/phlox-orch/gwB-review-out.md` の指摘1〜7と、判断済みの指摘8の資料追記。作業は `feature/git-tab-workflow` の既存ディレクトリ内。既存の未コミット変更を維持し、作業リポジトリのcommit・stash・reset・checkout・merge・rebaseは実行していない。直下にAGENTS.mdは存在せず、依頼文の規約とdocs/README.mdに従った。

## 変更・追加したファイル

以下は今回触れた15ファイル。macos/相対。開始前の差分全体を表すものではない。

| 区分 | ファイル |
|---|---|
| 翻訳 | `App/Localizable.xcstrings` |
| モデル | `Packages/DashboardFeature/Sources/DashboardFeature/Editor/EditorPanelViewModel.swift` |
| Git | `Packages/DashboardFeature/Sources/DashboardFeature/WorkingTree/WorkingTreeService.swift`、`GitHistoryTypes.swift`、`GitInspectorView.swift`、`GitHistoryViews.swift`（同ディレクトリ） |
| テスト | `Packages/DashboardFeature/Tests/DashboardFeatureTests/GitHistoryWorkflowTests.swift`、`GitHistoryPolicyTests.swift`、`GitHistoryRenderTests.swift`（同ディレクトリ） |
| 資料 | `docs/architecture/terminal-editor-panels.md`、`docs/specs/git-tab-workflow-and-worktree-start.md`、`docs/adr/0206-git-history-branches-stashes-and-graph.md`、`docs/adr/0208-git-history-review-corrections.md`（新規）、`docs/adr/README.md`、本書（新規） |

## 指摘ごとの対応

| 指摘 | 対応 |
|---|---|
| 1 | Viewのtaskをモデルの識別子に追従させ、交換後も保存済みの開閉を同期 |
| 2 | コミット／スタッシュの差分をGitのnumstatで判定。本文の文字列を判定に使わない |
| 3 | HEAD reflogのcheckout記録の切り替え先を新しい順に重複なく表示。記録のない現存ブランチを最終コミット時刻順で後置 |
| 4 | グラフは最初200件。末尾の「続きを読む」で次の200件を取得し、取得済み全件のレーンを再計算。更新時は取得済み件数を維持 |
| 5 | 直前の修正の、展開領域を通る継続線を維持。今回コード変更なし |
| 6 | スタッシュ確認の題と操作ボタンを具体化。重複しない対象ファイル数・未追跡件数・作業ツリーをHEADへ戻す説明を表示 |
| 7 | リモート単位の開閉、FETCH_HEAD更新時刻による取得時刻（ファイルがなければ省略）、ローカルupstreamによる追跡中の鎖の印・VoiceOverラベルを追加。originだけ既定で開く。閉じたリモートの行をキーボード選択から除外 |
| 8 | 判断どおりコード変更なし。GW-15に「閉じた区画は開いたときに最新を読む」を追記しADR 0206と一致 |

資料を先に更新し、ADR 0208でADR 0206のブランチ順とグラフ取得上限を置き換えた。取得時刻は依頼で許可されたFETCH_HEADの更新時刻であり、リモート別の通信時刻ではない。その他に要件・見本から外れる判断は追加していない。確認画面は既存DSDialogの配置を維持する。

## 追加したテスト

- `GitHistoryWorkflowTests`: NSHostingViewの同じView内でモデルを交換し、開いた5区画が新モデルに読み込まれること。コミットとスタッシュの追跡済み／未追跡テキストに `Binary files ` が含まれても差分が表示され、本物のバイナリはバイナリになること。最終コミット時刻が明確に古いブランチへ切り替えた直後の先頭表示と、利用記録のないブランチの後置。205件のグラフを200件から追加して初回コミットまで到達し、重複がなく更新後も件数を維持すること。取得前の時刻なし／取得後の時刻あり、upstreamの追跡印。
- `GitHistoryPolicyTests`: 削除・強制削除・スタッシュ削除・取り出し・作成・切り替え・チェックアウトの確認文言。スタッシュの対象9件・未追跡2件とHEADへ戻す説明。リモートの既定の開閉。
- `GitHistoryRenderTests`: 既存144画像の生成データにupstream、originの追跡設定、FETCH_HEAD、スタッシュ確認の対象件数を追加。通常のテスト実行では画像を生成しない。

## 検証

品質設定としてDashboardFeatureのPackage.swift、macos/project.yml、run-swift-tests.shとcompact-command.shを確認。対象に独立したlint・型チェック・静的解析の設定は見つからず未設定。Swiftコンパイラの検査とリンクはテストビルドおよび指定Debugビルドに含まれる。

| コマンド | 結果 |
|---|---|
| `SWIFT_TEST_FILTER='GitHistoryWorkflowTests GitHistoryPolicyTests' ~/.agents/scripts/compact-test --full GW後半関連 macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、22テスト／2スイート成功 |
| `SWIFT_TEST_FILTER='GitHistoryWorkflowTests/古い先端' ~/.agents/scripts/compact-test --full GW利用順回帰 macos/scripts/run-swift-tests.sh DashboardFeature` | 終了0、1テスト／1スイート成功。時刻と後置順序を補強した後の再確認 |
| `SWIFT_TEST_OUTPUT=full ~/.agents/scripts/compact-test --full GW後半最終全件 macos/scripts/run-swift-tests.sh DashboardFeature` | 1回実行、終了0。Swift Testing本体2124テスト／203スイート（既存skip17）、実Git41テスト／4スイート。XCTest4件（既存skip1、失敗0）。ログ: `.build/git-history-review-full.log`（リポジトリ直下） |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=git-rereview SWIFT_TEST_OUTPUT=full SWIFT_TEST_FILTER='GitWorkflowRenderTests GitHistoryRenderTests' ~/.agents/scripts/compact-test --full GW後半最終画像 macos/scripts/run-swift-tests.sh DashboardFeature` | 1回実行、終了0。2テスト／2スイート成功。`.build/git-history-snapshots`に144枚（日英72枚ずつ）、`.build/git-workflow-snapshots`に52枚（日英26枚ずつ）、計196枚。ログ: `.build/git-history-review-images.log` |
| `/opt/homebrew/bin/xcodegen generate`（macos/） | 1回実行、終了0 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxGTWBuild build`（macos/） | 1回実行、終了0、`BUILD SUCCEEDED`。ログ: `.build/git-history-review-debug-build.log`（リポジトリ直下） |
| `git diff --check` | 終了0、出力なし |

全件テストの内訳はSwift Testing本体2107成功／17skip、実Git41成功、XCTest3成功／1skip、計2151成功／18skip／失敗0。既存skipを今回追加・解除したものはない。独立したUI/E2Eの全件実行は行っていない。今回のモデル交換はSwift TestingからNSHostingViewで検査し、アプリ本体を起動しての確認ではない。

Debugビルドの警告は同文2件: `Metadata extraction skipped. No AppIntents.framework dependency found.`。noteとしてad-hoc署名によりhardened runtimeが無効（2ターゲット）、LaunchServices再登録スクリプトが毎回実行される表示があった。ビルド失敗はない。

全件ログの `warning:` は0行。復元失敗の2件は失敗経路を検査するテスト、Code513のworkspace cleanup失敗とdirty／未マージのworktree cleanup失敗は保持と理由表示を検査するテストの想定内だった。一方、既存の `DashboardRestoreAndSpawnCleanupTests` と `DashboardSessionLookupTests` では、共用の `ScriptedAppServerTransport` がresumeへ常に `thread-1` を返すため、要求ID `thread-white-1`／`thread-white-restore-ok` と異なる `threadIDMismatch` のログが2件残る。両テストは成功したが、復元の成功経路検査としては不備がある。今回変更したテストではなく、修正対象外として残した。

日英画像の目視では、`graph-expanded-260-dark-{ja,en}.png` の `side.txt` 展開領域で2本の線が続くこと、`remotes-normal-260-dark-{ja,en}.png` と英語340ptでoriginが開きupstreamが閉じ、取得時刻と鎖の印が出ること、`confirm-4-dark-{ja,en}.png` でスタッシュの操作名・9件・未追跡2件・HEADへ戻す説明を確認した。英語の `git-conflict-260-dark-en.png` と `changes-unselected-dark-en.png` も確認し、競合・ステージ案内・未選択案内が最新の英訳になっていることを確認した。コミット内容とセッション名はテストデータなので日本語を含む。画像全196枚の全数目視を主張するものではない。

検証中のソース編集は停止した。アプリ起動・XCUITest・入力ソース設定変更は行っていない。

## 未実装・未解決

指摘1〜7の未実装はない。5は既存修正を維持して画像で確認、8は指定どおり要件追記のみ。今回の対象に未解決の失敗はない。上記の既存テスト2件の復元ID不一致と成功経路検査の不備は未修正。実アプリ操作とXCUITestは依頼に従って未実施。
