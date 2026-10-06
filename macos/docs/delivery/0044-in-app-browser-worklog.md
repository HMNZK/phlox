---
status: completed
---

# 0044 アプリ内ブラウザの作業記録

## r3 再レビュー対応（2026-10-06・検証完了）

### 指摘と設計の対応

| 指摘 | 実装・検査 | 設計 |
|---|---|---|
| 1 | 明示的に開くファイルの親フォルダを許可。範囲内のリンク・戻る・進むでは範囲を保つ。範囲外の履歴は移動先の親フォルダへ切り替える | 仕様 §2・§3.3、ADR 0182「決定」 |
| 2 | ローカルページの HTTP iframe から window.open／target=_blank で同じ許可範囲の file を開く要求を検査。iframe の実通信とスクリプトの試行も確認 | 仕様 §3.3・§5、ADR 0182「決定」 |
| 3 | 次の許可範囲を表示中の許可と分けて保持し、didCommit で反映。HTTP のリンクと明示的な入力それぞれで、確定前の失敗・中止後にローカルの許可が残ることを検査 | 仕様 §3.3・§5、ADR 0182「決定」 |

今回の変更は次の5ファイル。以前の未コミット変更を保持する。

- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/BrowserTabModel.swift`
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/BrowserTabTests.swift`
- `docs/specs/in-app-browser.md`
- `docs/adr/0182-in-app-browser-tab.md`
- `docs/delivery/0044-in-app-browser-worklog.md`

### 修正前・変異の確認

期待値を弱めず、テスト追加後に開始時の実装を検査した。`subfolderLinkCanReturnToOpenedFolder` は範囲が sub に狭まり、親へのリンクがタイムアウトした。`failedHTTPNavigationKeepsLocalReadAccess` と `stoppedHTTPNavigationKeepsLocalReadAccess` は、リンク／明示的入力の両ケースで readAccess が nil になり失敗。3テスト・5ケース、計8指摘、終了コード1（`red.log`）。

修正後のブラウザ18テストは成功（`browser-green.log`）。その後、外部ページから file への拒否判定4行を一時的に削除して `httpFrameCannotOpenLocalFile` を実行。window.open のケースが other.html へ移動し、URL・タイトル等の検査が失敗した。target=_blank のケースは判定を外しても移動せず、このケース単独の変異検出は確認できていない。1テスト・2ケース、計3指摘、終了コード1（`mutation.log`）。判定は復元し、保存した最終モデルとの一致を cmp で確認した。

既存の別フォルダ履歴テストは、明示的に開いた直後にその親フォルダになる検査を追加した。戻った後の「進む」は移動先が現在の範囲内なので、期待する範囲を仕様どおり root に変更した。期待値を緩めるのではなく、指定された規則の一致を検査する。

### 検証

以下はすべて `~/.agents/scripts/compact-test --full <ラベル>` 経由。Swift コマンドは worktree 直下、Xcode コマンドは `macos/`。ログは `.build/browser-r3/`。

| コマンド（ラッパーの後ろ） | 結果 | ログ |
|---|---|---|
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter 'BrowserTabTests/(subfolderLinkCanReturnToOpenedFolder\|failedHTTPNavigationKeepsLocalReadAccess\|stoppedHTTPNavigationKeepsLocalReadAccess)'` | 修正前: 3テスト失敗、終了コード1 | `red.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter BrowserTabTests` | 修正後: 18テスト成功、失敗0 | `browser-green.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter BrowserTabTests/httpFrameCannotOpenLocalFile` | 判定削除時: window.open が失敗、終了コード1 | `mutation.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel` | Swift Testing 終了集計2,069件・211 suite、失敗0。既存条件によるスキップ17件。XCTestは3件成功・1件スキップ | `dashboard-all.log` |
| `env SWIFT_TEST_OUTPUT=full bash macos/scripts/run-swift-tests.sh` | Swift Testing 終了集計4,126件（589 + 193 + 42 + 1,217 + 2,043 + 26 + 16）、失敗0。既存条件スキップ17件。XCTestは6件成功・1件スキップ | `default-all.log` |
| `/opt/homebrew/bin/xcodegen generate` | 成功 | `xcodegen.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/browser-tab/.build/DD build` | BUILD SUCCEEDED | `debug-build.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath /tmp/PhloxUIBatch build-for-testing` | TEST BUILD SUCCEEDED。UI実行なし | `ui-build.log` |

### 判断・未検証・警告

- 本体側の指定仕様／ADRは絶対パスで確認したが存在しなかったため、worktreeの文書と今回のレビュー指示を用いた。本体checkoutへの書き込みはしていない。
- UI build-for-testing は今回の個別指定に従い `/tmp/PhloxUIBatch` に出力した。上のworktree内配置を選んだr1/r2の記述は、その時点の記録として残す。
- XCUITestは未実行。PMの実行対象: `-only-testing:PhloxUITests/BrowserTabInteractionTests/testLocalHTMLRunsJavaScriptInBrowserTab`。
- 今回は画面外の実WebKitとループバックHTTPで処理を検証した。見た目のコードは変更しておらず、画像の再比較は未実施。外部HTTPS／CDN、対話パネル・ファイル選択の実操作は今回未検証。
- 独立したlint／型チェック／静的解析の適用可能なゲートは未設定。worktreeに `.claude/verify.sh` はなく、本体側のものは別作業用で本体のパッケージへ書き込むため実行せず、指定の `run-swift-tests.sh` を正本とした。型診断・リンクはSwiftテストとXcodeビルドで検査した。
- 修正前のコンパイルでは既存テストの accessibilitySetValue 非推奨警告。Debug／UIビルドでは既存DashboardViewの明示returnによるViewBuilder警告、PTYKitのinit(cString:)非推奨警告（UIビルド）、AppIntents.framework非依存によるメタデータ抽出省略警告が出た。
- 全数の既存条件スキップはE2E・性能測定等。XCTestの1件は `PHLOX_SCROLL_PERFORMANCE=1 のRelease実行時だけ計測`。条件・テストは変更していない。これらの検査は今回未実行。
- 凍結一覧・署名テスト・ADR 0178・完了済み0039〜0043に変更がないことを確認した。commit・push・merge、稼働アプリの終了、画面入力・前面化は行っていない。
- 最終コードの全数検証後にもモデルの保存コピーとの一致と `git diff --check` の成功を確認した。テスト・生成・ビルドの終了コードはすべて0（意図した修正前／変異検査を除く）。

## 対応項目

| 項目 | 仕様 | 状況 |
|---|---|---|
| タブ・＋・ショートカット・保存正規化 | §3.1/3.5/3.6 | 実装済み。⌃⌘R、保存用コピーのみ正規化 |
| URL と WebKit・パネル | §3.2/3.3 | 実装済み。失敗 URL・履歴の読み取り範囲は判断どおり修正 |
| HTML の入口 | FR-4/§4 | 実装済み。保存済み内容を開く判断を採用 |
| 見本と画面外撮影 | §3.8 | 12 状態を撮り直して比較済み。アイコン・文字描画等は判断どおり |
| 単体・既定テスト・ビルド・UI ビルド | §5 | 下表の検証に成功。UI 実走は PM に引き継ぐ |

## 判断

- 今回の記録は 0044 のみに書く。完了済み 0039〜0043 と既存 ADR は変更しない。
- HTML の入口は保存済みファイルを開く。下書きを別に配信する機構は最低限の範囲を超えるため追加しない。ボタンの説明で保存済み内容と明示する。
- 短縮表示は新部品を作らず帯の幅を参照し、HTML の入口は既存の ViewThatFits とボタンスタイルを使う。
- URL が長くても広幅ではタイトルを残す。URL 欄の自然幅で判定するとタイトルが消えるため、帯の実幅（480pt 未満）で縮退を決める。
- window.open は WebKit の自動ウィンドウ要求も許可して同じタブに送る。新しい WebView／ウィンドウは作らない。
- HTTP のページも受け付ける要件のため、WebView だけを通信保護の HTTPS 制限から除外する `NSAllowsArbitraryLoadsInWebContent` を Info.plist と生成元に追加する。URLSession の保護は維持する。ファイルプレビューの外部遮断は既存のルールで維持する。entitlements の変更は不要。
- 読み込み失敗時に WKWebView.url が直前の成功ページを返すことを実走で確認。失敗した URL を再読込できるよう、移動中と失敗中はその値で URL 欄を上書きしない。
- 別フォルダを明示的に開いた後の「戻る」が、最後のフォルダの許可で拒否されることをテストで確認。戻る・進むは WebKit の履歴項目の親フォルダへ許可範囲を切り替える。ページ自身の許可外遷移は引き続き拒否する。
- 見本の文字アイコンは SwiftUI では既存の SF Symbols、読み込みの輪は標準 ProgressView にする。WebKit と Chromium の文字描画、フィクスチャの絶対パスは比較の一致条件から除く。色・帯の高さ・操作順・文言・状態・縮退を比較する。
- UI build-for-testing の DerivedData も worktree 内 `.build/PhloxUIBatch` にする。共通の「worktree 内だけ」制約と xcodebuild の配置制約を優先し、PM 指定の `/tmp/PhloxUIBatch` へは書かない。

## 記録

- r2 レビュー対応を開始。仕様 §3.2/3.3/5 と ADR 0182 を先に更新。指定の本体側絶対パスには in-app-browser.md と ADR 0182 が存在せず、今回の worktree の文書と PM 判断を正本にする。本体へは書き込まない。

- 2026-10-06: 仕様と ADR を先に追加。sandbox 無効を両 entitlements で確認したため変更不要。既存の安全なプレビューとブラウザを分離する。
- ブラウザのタブ・HTML の入口・保存正規化を実装。URL 補完と親フォルダ限定の読み込み、非永続データ、同じタブへの window.open／target=_blank、標準の対話・ファイル選択パネルを追加。
- 初回検証で、フォントの直書き 1 箇所と SDK 間で異なる confirm コールバック署名を検出。既存トークンと非同期 delegate に直した。テスト HTML の文字コード指定不足は UTF-8 指定を加えて直し、期待値は変更していない。
- 長い URL でも広幅のタイトルを維持するよう修正。ブラウザを閉じると自身のパネルだけをキャンセルする。
- 読み込み失敗後の再読込と、別フォルダ間の戻る・進むを実際の WebKit で検査。失敗 URL の上書きと履歴の許可範囲を直し、同じテストが成功した。
- 既定テストの途中で既存 HTMLNetworkIsolationTests の meta refresh ケースが一度 `textNotRendered("本文")` で失敗した。単独 4 テストは成功。ブラウザのテストが変更した NSApplication の activationPolicy を復元し、最終の既定全数も成功した。失敗との因果関係は未確定で、既存プレビューの実装・期待値は変更していない。
- 最終検証で既定 4,115 件と DashboardFeature 全数 2,058 件が成功。Debug／UI テスト用ビルドも成功。12 状態を撮影直後に専用フォルダへコピーし、見本と自分で見比べた。色・文言・帯・操作順・タイトル・縮退は一致し、標準アイコンと文字描画等の差は上記判断どおり。

## 検証結果

テストとビルドはすべて `~/.agents/scripts/compact-test --full <ラベル>` を前置して実行。以下はその後のコマンド。ビルドの作業ディレクトリは `macos/`、他は worktree 直下。

| コマンド | 結果 | ログ |
|---|---|---|
| `SWIFT_TEST_OUTPUT=full bash macos/scripts/run-swift-tests.sh` | 4,115 件、失敗 0。589 + 193 + 42 + 1,217 + 2,032 + 26 + 16 | `.build/default-tests-final.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel` | 2,058 件・211 suite、失敗 0 | `.build/dashboard-tests-full.log` |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=browser swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests` | 2 件、失敗 0。12 PNG | `.build/browser-snapshots-final.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter HTMLNetworkIsolationTests` | 4 件、失敗 0 | `.build/html-isolation-tests.log` |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter BrowserTabTests/localJavaScriptRunsWithoutPersistentData` | 1 件、失敗 0（修正後） | `.build/browser-history-tests.log` |
| `/opt/homebrew/bin/xcodegen generate` | 成功 | Xcode プロジェクト生成 |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/browser-tab/.build/DD build` | BUILD SUCCEEDED | `.build/debug-build-final.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/browser-tab/.build/PhloxUIBatch build-for-testing` | TEST BUILD SUCCEEDED、UI 実走なし | `.build/ui-build-final.log` |

Swift Package のテスト設定・既定スクリプト・project.yml を確認し、指定の検証を正本として実行。独立した lint／型チェック／静的解析のゲートは未設定。Swift の型診断は上記コンパイルの範囲で確認。生成元とビルド済み Info.plist の WebView 限定 HTTP 設定を確認し、`git diff --check` は成功。

写真は worktree の `.build/design-snapshots/` に出力し、直後に `cp -R` で `.build/browser-comparison/actual-final/` に保存した。見本は `.build/browser-comparison/mock/`。比較画像は同フォルダの `comparison-dark.png`／`comparison-light.png`。空・読み込み中・ローカル表示・失敗・狭幅・HTML 入口 × ダーク／ライトの 12 状態を目視比較した。

## 変更ファイル

追加:
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/BrowserTabModel.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/BrowserTabView.swift`
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/BrowserTabTests.swift`
- `UITests/BrowserTabInteractionTests.swift`
- `docs/specs/in-app-browser.md`
- `docs/specs/ClaudeDesign/9 Browser Tab.dc.html`
- `docs/adr/0182-in-app-browser-tab.md`
- `docs/delivery/0044-in-app-browser-worklog.md`

変更:
- `App/PhloxApp.swift`
- `project.yml`
- `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Router/AppRouter.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/SessionTabs.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/SessionTabsContainer.swift`
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/DesignSnapshotRenderTests.swift`
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/SessionTabsPersistenceTests.swift`
- `docs/adr/README.md`

パスは `macos/` からの相対。生成した Info.plist・Xcode プロジェクトと検証成果物は Git 管理対象外。凍結ファイル・既存 ADR・完了済み記録・entitlements に変更はない。

## 未検証・PM への引き継ぎ

- XCUITest は実行しない。PM の実行対象は `-only-testing:PhloxUITests/BrowserTabInteractionTests/testLocalHTMLRunsJavaScriptInBrowserTab`。DerivedData は worktree の `.build/PhloxUIBatch`。
- JavaScript の本文変更、window.open、target=_blank、履歴、読み込み失敗からの再読込は画面外の WebKit で実走。対話パネル・ファイル選択の実操作、ダウンロード拒否の実通信、HTTP／CDN への実通信は未検証。対話 delegate の呼び出し可能性と WebView に限定した HTTP 設定は単体テストで検査した。
- 読み込み中の写真は帯の状態を固定する描画用状態。通信速度には依存しない。ローカル表示と狭幅は実際の WKWebView、HTML 入口は JavaScript 無効の実際のプレビューで撮影する。
- ビルドには既存 DashboardView の明示 return による ViewBuilder 警告と、AppIntents.framework 非依存によるメタデータ抽出省略の警告がある。初回の全数コンパイルにも既存の非推奨 API・並行処理等の警告が出た。今回追加した delegate の SDK 差異の警告は修正済み。
- commit・push・merge は行わない。稼働アプリの起動／終了、UI 入力、前面化は行っていない。見本の撮影に使った headless Chrome は自身のブラウザと Playwright ドライバーを閉じ、他セッションの MCP プロセスは停止していない。

## r2 独立レビュー対応（2026-10-06）

以下は今回の最終結果。上の検証・未検証欄は r1 時点の記録として残す。

### 指摘と設計の対応

| 指摘 | 対応 | 設計 |
|---|---|---|
| 1 | 主フレーム以外の about:・data:・blob: を許可。srcdoc・blob の本文、blank の本文、data のメッセージを実 WebKit で検査 | 仕様 §3.3 |
| 2a | 表示できない子フレーム応答を拒否しても主ページのエラーを設定しない | 仕様 §3.3 |
| 2b | WebKitErrorDomain 102 で既存の理由を上書きしない。MIME 応答と download 属性の両方で 500ms 後の理由を検査 | 仕様 §3.3 |
| 2c | mailto 等は移動を取り消すだけ。ページを残し、外部アプリへ渡すコードは追加しない | 仕様 §3.3 |
| 3 | 主フレームを許可する時に readAccess を再計算。HTTP では nil。外部ページから file への移動を、同じタブへの読み込み直しより先に共通判定で拒否 | 仕様 §3.3・ADR 0182 |
| 4 | fragment 移動の URL 観測と、読み込み失敗で移動待ち状態を解除。pushState／replaceState の追従を検査 | 仕様 §3.3 |
| 5 | App のカタログにブラウザ関連の英訳17キーを追加。モデルの文言を String(localized:)、エラー本文と動的な操作ラベルを翻訳可能な Text／LocalizedStringKey に変更 | localization.md「新規 UI 文言を追加するとき」・仕様 §5 |
| 6 | 絶対パスの # 以降を fragment とし、~/ をホームへ展開 | 仕様 §3.2 |
| 7 | 保存済み HTML を開く判断を維持。既存テストで下書きがディスクへ書かれないことを再確認 | 仕様 §6 |
| 8 | 既存 UI テストに ⌃⌘R の入力と browser-address 出現の確認を追加。build-for-testing でコンパイル | 仕様 §3.6/5 |
| 9 | ATS 設定はアプリ内のすべての WebView に適用されるが、プレビューは content rule list で外部通信を止める旨を追記 | ADR 0182 |

### 修正前の失敗確認

回帰テストを先に追加し、今回開始時の BrowserTabModel を保存して、その実装で実行した。最終確認でも旧モデルへ一時的に差し替え、終了後に修正済みモデルを戻した。期待値を弱めていない。

- `pageOwnedFramesLoad`、`subframeDownloadDoesNotCoverPage`、`mainFrameDownloadKeepsMessage`、`addressFollowsPushStateAfterFragment`、`bareAbsolutePathAndTilde`、`unsupportedLinkLeavesPage`、`httpNavigationClearsReadAccessAndRejectsFiles` の7テストがすべて失敗。主フレームのダウンロードは通常リンクと download 属性の2ケースが失敗した（`.build/browser-r2/red-final.log`）。
- 外部移動はケースごとに「ローカル → HTTP」を作り直した。旧モデルでは readAccess が残り、window.open でローカルファイルへ移動した（`.build/browser-r2/external-red.log`）。通常リンク・window.open・target=_blank の拒否と、URL 欄から明示的に開く操作の成功は、最終の全数テストで確認した。
- 最終コードでは上記7テストと既存ブラウザテストが DashboardFeature 全数に含まれて成功。修正済みモデルと全数検証時の保存コピーの一致を `cmp` で確認した。

修正前のコマンド（同じラッパー経由）:

```sh
swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter 'BrowserTabTests/(bareAbsolutePathAndTilde|pageOwnedFramesLoad|subframeDownloadDoesNotCoverPage|mainFrameDownloadKeepsMessage|addressFollowsPushStateAfterFragment|unsupportedLinkLeavesPage|httpNavigationClearsReadAccessAndRejectsFiles)'
swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter BrowserTabTests/httpNavigationClearsReadAccessAndRejectsFiles
```

途中の修正後検証は `--filter BrowserTabTests`（初回は通信タイムアウト、後の実行では data の文字コード不一致で失敗）、`--filter BrowserTabTests/subframeDownloadDoesNotCoverPage`（1件成功）、`--filter BrowserTabTests/pageOwnedFramesLoad`（文字コード修正後1件成功）。いずれも `swift test --package-path macos/Packages/DashboardFeature --no-parallel` とラッパーに上記 filter を加えて実行した。

### 最終の検証

テスト・生成・ビルドは `~/.agents/scripts/compact-test --full <ラベル>` 経由。Swift コマンドは worktree 直下、Xcode コマンドは `macos/` で実行した。ログは worktree の `.build/browser-r2/` に保存。

| コマンド（ラッパーの後ろ） | 結果 | ログ |
|---|---|---|
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel` | Swift Testing 2,065件・211 suite 成功。XCTest 3件成功・既存条件による1件スキップ。失敗0 | `dashboard-all.log` |
| `SWIFT_TEST_OUTPUT=full bash macos/scripts/run-swift-tests.sh` | Swift Testing 4,122件成功（589 + 193 + 42 + 1,217 + 2,039 + 26 + 16）。XCTest 6件成功・既存条件による1件スキップ。失敗0 | `default-all.log` |
| `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=browser swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests` | 2件成功。12状態の PNG を画面外で生成 | `snapshots.log` |
| `/opt/homebrew/bin/xcodegen generate` | 成功 | `xcodegen.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/browser-tab/.build/DD build` | BUILD SUCCEEDED | `debug-build.log` |
| `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/browser-tab/.build/PhloxUIBatch build-for-testing` | TEST BUILD SUCCEEDED。UI 実走なし | `ui-build.log` |

ビルド済み `en.lproj/Localizable.strings` に追加した17キーの英訳を確認。Info.plist の `NSAllowsArbitraryLoadsInWebContent = true` も確認した。`git diff --check` は成功。対象の独立した lint・型チェック・静的解析コマンドは未設定。Swift のコンパイル診断とリンクは上記テスト／ビルドで検査した。

前回の `.build/browser-comparison/actual-final/` と、今回の `.build/browser-r2/snapshots/` の12枚を画素比較し、ダーク／ライトの比較画像を自分で見比べた。10枚は画素一致。エラー2枚の差は本文の字間に限られ、文言・配置・帯・色は維持されている。本文の差は翻訳可能な Text への変更に伴う描画差と判断した。結果は `image-comparison.txt`、比較画像は `comparison-dark.png`／`comparison-light.png`、本文の拡大比較は `error-detail.png`。

### 途中の失敗・警告

- 初回の修正後検査で子フレームの通信が一度タイムアウト。単独再実行では成功したが、発生原因は確定していない。検査用サーバーを、接続開始後すぐ受信し、先行接続の正常 EOF と通信失敗を分け、終了時に自身の接続を閉じる構成へ変更した。最終の DashboardFeature 全数と既定テストでは同じ検査が成功した（初回ログ `green.log`）。
- テスト用サーバーから internal な `HTTPMessageParser.isComplete` を呼んでコンパイルに失敗。公開の parser／serializer とヘッダ終端の検出を使うよう修正した。LocalHTTPServer 本体は変更していない。
- テスト HTML の修正をビルド中に保存し、`input file ... was modified during the build` で中断した。編集とビルドを分けて再検証した。
- data iframe のテスト用 URL に文字コード指定がなく、日本語の一致検査が失敗。`charset=utf-8` を追加して直した。本文の期待値は変更していない（`browser-intermediate.log`、修正後 `frames.log`）。
- ビルドでは既存 DashboardView の明示 return による ViewBuilder 警告と、AppIntents.framework 非依存によるメタデータ抽出省略の警告が出た。
- XCTest のスキップは既存 `MarkdownScrollPerformanceTests/testScrollFrames`。理由は「PHLOX_SCROLL_PERFORMANCE=1 のRelease実行時だけ計測」。この性能測定は今回未実行で、スキップ条件も変更していない。
- 全数テストには、未保存 worktree／未マージ branch を削除しない検査から意図した cleanup 失敗ログが出る。該当する既存テストは成功している。
- 画像比較の補助処理で Pillow の `Image.getdata` の非推奨警告が出た。画像比較の結果・製品コードには影響しない。

### 今回変更したファイル

既存の r1 変更は保持し、今回の変更は次の9ファイル。

- `App/Localizable.xcstrings`
- `Packages/DashboardFeature/Package.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/BrowserTabModel.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/BrowserTabView.swift`
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/BrowserTabTests.swift`
- `UITests/BrowserTabInteractionTests.swift`
- `docs/specs/in-app-browser.md`
- `docs/adr/0182-in-app-browser-tab.md`
- `docs/delivery/0044-in-app-browser-worklog.md`

### 判断・未検証

- 指定された本体側の仕様／ADR の絶対パスにはファイルがなかったため、worktree にある今回の文書と PM のレビュー判断を用いた。本体 checkout は書き換えていない。
- `/tmp/PhloxUIBatch` は共通制約と競合するため、worktree 内の `.build/PhloxUIBatch` を使用した。
- XCUITest の実行対象は `-only-testing:PhloxUITests/BrowserTabInteractionTests/testLocalHTMLRunsJavaScriptInBrowserTab`。この1メソッドで ⌃⌘R と HTML の入口を確認する。実行は PM へ引き継ぐ。
- ローカル HTTP とファイル、ページ所有 iframe、ダウンロード拒否、URL の履歴更新は実 WebKit で検査した。外部 HTTPS／CDN、AppKit パネルの実操作、言語切替の実操作は未検証。英訳はビルド済みリソースで確認した。
- 凍結一覧のファイル・署名テスト・完了済み0039〜0043・既存 ADR を変更していない。リポジトリの commit・push・merge、実アプリの起動／終了、画面操作・前面化は行っていない。変更は未コミットで残す。
