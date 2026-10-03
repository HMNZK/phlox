---
status: active
last-verified: 2026-10-03
---

# シミュレーター子タブの実行記録（§7-6）

## 独立レビューの修正（2026-10-03）

レビューの5項目を修正し、未コミットで残した。今回の検査は非表示のウィンドウ・偽の端末接続で実行し、実アプリ・実端末・XCUITest は起動していない。以下より後の実端末の記録は前回作業の記録である。

### (1) 項目と設計書の対応

| 項目 | 節 | 今回の変更 |
|---|---|---|
| 1 初期フォーカス | §7-6、§3.8、§5、NFR-6 | 起動済み端末の画面を持つ NSHostingView を非表示の NSWindow に載せ、端末メニューの firstResponder・入力0件・状態変更0件を検査。再フォーカス要求も検査 |
| 2 ホーム | §7-6、§3.6、§5 | 小文字 `h` の合成 NSEvent を performKeyEquivalent に渡し、フォーカスありでホーム1回、なしで0回を検査 |
| 3 取得停止 | §7-6、§3.4、§5、NFR-3 | ビューをウィンドウから取り外して detach・接続削除・画面情報の解放を検査。stop の直前は可視、直後は非可視となり、その後の通知に反応しないことを検査 |
| 4 停止対象 | §7-6、§3.8 | 確認を開く時点の UDID を State に保持し、停止時は Hub にその UDID を渡す。Aの確認後にBを選んでも `shutdown A` だけを送る Hub テストを追加 |
| 5 二重初期化 | §7-6のDebug検証入口（補助実装） | Debugの通常起動・検証入口が同じ初期化Taskを待つ。完了済みも再利用し、失敗時だけ再試行可能にする |

### (2) 今回追加・変更したファイル

- `macos/App/PhloxApp.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorHub.swift`
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorTabView.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/SimulatorHubTests.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/SimulatorTabPresentationTests.swift`
- `macos/scripts/tests/test_simulator_initialization.py`（新規。初期化の共有をソースの配線として検査）
- `macos/docs/operations/simulator-tab-verification.md`（この追記）

### (3) テスト・ビルド

テストコマンドはすべて `~/.agents/scripts/compact-test <ラベル> ...` 経由。全パッケージ実行は結果を残すため `--full` を指定した。

| コマンド（ラッパーの後） | 最終結果 |
|---|---|
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter SimulatorTabPresentationTests --filter SimulatorHubTests` | 13件、失敗0 |
| `python3 macos/scripts/tests/test_simulator_initialization.py` | 2件、失敗0 |
| `env SWIFT_TEST_SERIAL_PACKAGES='AgentDomain DesignSystem MessageStore SessionFeature DashboardFeature SimulatorBridgeKit' bash macos/scripts/run-swift-tests.sh` | 既定6パッケージ3,838件、失敗0 |
| `cd macos` を作業ディレクトリとして `/opt/homebrew/bin/xcodegen generate` | 成功 |
| 同じ作業ディレクトリで `xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath ../.build/DerivedData build` | 成功 |
| 同じ作業ディレクトリで `xcodebuild -project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath ../.build/DerivedData build-for-testing` | 成功。UIテスト実行なし |
| `git diff --check` | 成功 |

全数の内訳は AgentDomain 565件、DesignSystem 193件、MessageStore 42件、SessionFeature 1,209件、DashboardFeature 1,813件（本体1,787件＋実git26件）、SimulatorBridgeKit 16件。正本スクリプトは実gitスイートを別のパスで全件実行し、除外したままにはしていない。

修正前の赤と修正後の緑:

- 項目1〜3は既存動作が正常だったため、追加テストの検出力を確かめた。フォーカス設定を無効化、ホームのフォーカス条件を無効化、非表示時のHub解放を無効化、stopの通知を誤って可視にする変更を一時的に入れ、6テスト中5テストで計12件の失敗を観測した。取り外し後の接続残存では待機期限切れも観測した。一時変更を戻した後は13件が成功した。
- 項目4は選択Bに対して停止が送られ、Aへの停止を要求するアサーションが失敗した。UDIDを渡す修正後は成功した。
- 項目5は初期化を共有する配線がなく、ソース検査2件が失敗した。共有後は2件成功した。実アプリの同時起動を検査した結果ではない。
- テスト作成中に、ホームのボタン番号を1とする誤りと、初期化検査で戻り値の型名まで検索する誤りがあった。ホーム番号は補助プロセスの契約（0がホーム）を確認して訂正し、初期化検査は生成式を検索するよう訂正した。

ビルドの警告は DashboardView.swift:597 の明示的returnによるViewBuilder無効化と、AppIntents.frameworkの依存がないためメタデータ抽出を省略するもの。ビルドログは worktree 内の `.build/s6-review-build.log`・`.build/s6-review-build-for-testing.log` に保存した。

### (4) 判断・未検証

今回の5項目で設計書どおりにできなかった点はない。テスト追加の項目1〜3では、本体の正常な処理を変更せず検査を強化した。項目5は設計書に明記されていないDebug検証入口の修正であり、完成済みの本体だけでなく初期化中のTaskも共有する方式にした。

Dockクリックと検証入口の同時動作、実端末の入力、実ウィンドウの表示は未検証。初期化はソースの配線検査とDebugビルドで検証した。専用のlint・独立した型チェック・静的解析コマンドは未設定。Swiftのコンパイルはパッケージテストとアプリビルドで実行した。

PMが実行する既存UIテストは `PhloxUITests` スキームで次を指定する（今回も実行していない）。

```text
-only-testing:PhloxUITests/SimulatorTabUITests/testShortcutOpensSimulatorWithDeviceMenuFocusAndWithoutDuplicate
-only-testing:PhloxUITests/SimulatorTabUITests/testPlusChooserOpensSimulatorAndCanReturnToConversation
-only-testing:PhloxUITests/SimulatorTabUITests/testSimulatorSupportsSplitAndUnsplit
```

---

## 前回作業の記録

前回の未コミット変更を引き継ぎ、共有ハブ・子タブ・保存互換性・フォーカス・非表示時の取得停止を実装した。§7-7 の許可リスト・非対応表示・再接続・診断は対象外。

## 実装と設計書の対応

| 節・要件 | 実装・検査 |
|---|---|
| §3.4、FR-7、NFR-3 | PhloxApp の共有 SimulatorHub。端末別の接続とセッション別の選択。可視表示が0なら切断。タブ非表示・最小化・隠蔽通知を検査 |
| §3.5、NFR-5 | ChildTab.simulator、＋の選択肢、分割・巡回・閉じる操作。保存用コピーだけから除去し、旧型・新型の往復を検査 |
| §3.6、NFR-6 | ⌃⌘Y は端末メニューへフォーカスを要求。端末は自動起動しない。⇧⌘H はフォーカス中のシミュレータータブでホームを送る |
| §3.8、FR-1〜6 | 30pt の帯、選択・起動・ホーム・スクリーンショット・停止確認。狭い幅では版・状態の文字を縮め、端末名を保持。入力の手がかりと単一の読み上げ要素 |
| §5、NFR-1 | fake の終了・期限切れ後も、SessionViewModel の状態遷移・入力・出力とターミナルの入力・出力が続くことを検査 |
| FR-9 | 同じ専用端末の Simulator.app と Phlox の画面を撮影。同時表示中のタップ到達を観測アプリで確認 |
| §5、XCUITest | ショートカット・重複防止・初期フォーカス、＋から開く・会話へ戻る、分割解除を作成。実行せず build-for-testing まで |

## 実行した検査

テストは `~/.agents/scripts/compact-test` 経由。全パッケージの正本は `bash macos/scripts/run-swift-tests.sh`。

| コマンド | 結果 |
|---|---|
| `bash macos/scripts/run-swift-tests.sh` | AgentDomain 565、DesignSystem 193、MessageStore 42、SessionFeature 1209、DashboardFeature 1783＋実git 26、SimulatorBridgeKit 16。合計3834件、失敗0 |
| `bash macos/scripts/tests/test_simulator_bridge_signing.sh` | 4件、失敗0 |
| `python3 macos/scripts/tests/test_simulator_bridge_regressions.py` | 4件、失敗0 |
| `bash macos/scripts/verify-simulator-display.sh` | 本体ビルド、対象パッケージ、回帰検査、署名検査のゲート成功。その後の最終差分は上記の全パッケージ・本体ビルド・署名検査で確認 |
| `/opt/homebrew/bin/xcodegen generate --spec macos/project.yml` | 成功 |
| `xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath .build/DerivedData build` | 成功 |
| `xcodebuild -project macos/Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath .build/DerivedData build-for-testing` | 成功。XCUITest は未実行 |
| `bash macos/Tests/SimulatorInputHarness/build.sh` | ホスト・観測アプリのビルドと署名確認に成功 |
| `git diff --check` | 成功 |

`SimulatorTabPresentationTests` の NSHostingView を非表示ウィンドウで描画し、320pt・520pt の PNG を `.build/simulator-render/` に保存した。部品破棄中の State 書き換え競合をこの検査で検出し、可視性通知の配送を次のイベント処理へ移して修正した。端末メニューの末尾省略設定も修正し、テストを再実行して成功した。

ビルド中に既存の `init(cString:)` 非推奨、ViewBuilder 内の明示的 return、AppIntents.framework がないためのメタデータ抽出省略を観測した。テストコンパイルでは既存テストの actor 分離・未使用戻り値・不要な try の警告を観測した。実git検査の失敗を再現するケースでは未マージブランチの削除拒否がログへ出るが、その検査自体は成功した。独立した SwiftLint・静的解析ゲートは未設定。Swift 6 の型検査はビルドとテストのコンパイルで実行される。

## 専用端末での確認

- 専用端末: `EF889EC1-1276-47C4-B42A-0FD300F23A91`（`Phlox-S6-103657`）。今回 `simctl create` で作成し、失敗時も成功時も shutdown。削除していない。
- Xcode 26.2（17C52）、macOS 26.6.2（25G83）、iOS 26.2（23C54）、iPhone 17、402×874pt、倍率3。
- 最終記録: `.build/simulator-tab-20261003-105254/`。`device.json`、`windows.json`、`simulator-windows.json`、前後の端末一覧、コマンドログ、`events.json`、ウィンドウ指定の PNG を保存した。
- `open -g -n --env PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` に、専用の `PHLOX_DATA_DIR`・`PHLOX_DEFAULTS_SUITE`・`PHLOX_AGENTS_JSON` と `--args --simulator-test-udid <UDID>` を加えて Debug 版を起動した。作業用チェックアウト・通常のセッション保存先は使用していない。
- `open -g` では通常の SwiftUI 初期ウィンドウが生成されなかった。Debug の専用検証条件に限り、PhloxApp が所有するハブと実物の DashboardView を背面の NSWindow でホストする入口を設けた。端末を自動起動せず、マウス・キー・前面化を使わずに子タブを開く。
- `screencapture -l <windowID>` で Phlox の端末画面を撮影し、画像を確認した。ハーネスの `--background-tap` を実行し、観測アプリの「タップ: 1」、接触位置（150,160）、押下・解放の記録を確認した。
- Simulator.app は `open -g -n ... --args -CurrentDeviceUDID <UDID>` が既存インスタンスへ転送された。既存の PID は終了せず、専用端末名のウィンドウだけを撮影した。Phlox と同時表示中にも上記のタップ到達を確認した。Simulator.app 側のマウス・キー操作は未検証。
- 起動した Debug の PID だけに SIGTERM を送り、終了を確認した。追加の Simulator 起動プロセスは転送後に自然終了。専用端末を shutdown し、既存端末は起動・変更・削除していない。

実端末での確認は手元の一回の検査で、パッケージテストには未登録。画像・ログは Git 対象外。

## PM が実行する XCUITest

`PhloxUITests` スキームで以下を個別指定する。このセッションでは実行していない。

```text
-only-testing:PhloxUITests/SimulatorTabUITests/testShortcutOpensSimulatorWithDeviceMenuFocusAndWithoutDuplicate
-only-testing:PhloxUITests/SimulatorTabUITests/testPlusChooserOpensSimulatorAndCanReturnToConversation
-only-testing:PhloxUITests/SimulatorTabUITests/testSimulatorSupportsSplitAndUnsplit
```

非対応応答の差し替えテストは、その表示を作る §7-7 で追加する。実端末での全キー操作・ドラッグ・スクロール・貼り付け・向き・30fps 計測・公証は、この §7-6 の検査では未検証。入力の配送規則と解放は既存の SimulatorInputDeliveryTests・SimulatorBridgeKit のパッケージテストで確認した。

設計書との差は、補助プロセスのファイルが Swift 1ファイルではなく既存の `PrivateSimulatorAPI.m/.h` と Swift のサービスからなる点、既存のスクロール契約に位相がある点、SimulatorDisplayConnection に版の確認が実装済みだった点。現行コードを使い、版の確認は今回追加していない。§7-7 の自動再接続・許可リスト・診断は実装していない。

## 追加・変更したファイル

すべて `macos/` 配下。

- `App/PhloxApp.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorHub.swift`（追加）
- `Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorTabView.swift`（追加）
- `Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorScreenView.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/SessionTabs.swift`
- `Packages/DashboardFeature/Sources/DashboardFeature/Tabs/SessionTabsContainer.swift`
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/SessionTabsPersistenceTests.swift`（追加）
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/SimulatorHubTests.swift`（追加）
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/SimulatorPolicyTests.swift`（追加）
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/SimulatorTabPresentationTests.swift`（追加）
- `Packages/DashboardFeature/Tests/DashboardFeatureTests/SimulatorInputDeliveryTests.swift`
- `PhloxUITests/SimulatorTabUITests.swift`（追加）
- `Tests/SimulatorInputHarness/Host/InputHarness.swift`
- `Tests/SimulatorInputHarness/README.md`
- `docs/operations/simulator-tab-verification.md`（本書、追加）
