# シミュレーターの互換性・再接続の検証と実行記録（§7-7）

## 現在の許可リスト

`SimulatorPolicy.verified` は Xcode build `17C52` × `com.apple.CoreSimulator.SimRuntime.iOS-26-2` だけを表示・入力対応にする。
2026-10-03 に `xcodebuild -version` と `xcrun simctl list runtimes` で Xcode 26.2 / iOS 26.2（runtime build 23C54）を確認した。
PM 裁定により、以下の正式な実行記録で表示・入力が合格したこの組だけを採用する。
日本語入力・四方向・実接続の異常・公証済み Release は未検証であり、合格には含めない。

載っていない組では probe の後に attach しない。「未確認でも試す」は押したセッションのタブだけに効き、保存しない。
同じ端末を別セッションのタブで見ても例外は伝わらない。同じセッションの表示は例外を共有する。
例外は SimulatorHub がセッションIDと許可したUDIDの組で照合する。端末を切り替えると解除し、元の端末へ戻しても復活しない。手動再接続中も許可した端末の「未確認で実行中」の表示を保つ。
子タブの切替・分割のしきい値によるビュー再作成・最小化・隠蔽では例外を保つ。解除するのはタブを閉じたとき、端末を切り替えたとき、アプリを終了したときだけ。
入力未確認の組は `supportsInput: false` として登録し、画面・診断だけを有効にする。例外を押しても入力を解放しない。
部品の読み込み失敗と通信仕様の版不一致は例外で解放しない。版不一致では再起動を案内し、自動再接続しない。

## Xcode 17C52 × iOS 26.2 の正式な実行記録

2026-10-03 に既存の関門・入力ハーネス・タブ検査の記録を統合し、§3.3・§3.7 の許可リストの根拠として正式に記録する。
今回、実端末検査を再実行したものではない。PM 裁定は、この組を表示・入力対応のまま維持することとし、未検証項目を合格へ変更しない。
各実端末検査は手元で実行したもので、パッケージテストには未登録。

| 環境・記録 | 値・参照先 |
|---|---|
| Xcode・iOS runtime | Xcode 26.2 / build `17C52`、`com.apple.CoreSimulator.SimRuntime.iOS-26-2` / iOS 26.2 / build `23C54` |
| macOS・端末 | macOS 26.6.2 / build `25G83`、専用 iPhone 17、402×874ポイント、1206×2622ピクセル、倍率3 |
| 関門 | [SimulatorGate README](../../Prototypes/SimulatorGate/README.md) §1・§4。ホスト／サービス／観測アプリは版0.1・build 1、Developer ID 署名と hardened runtime。生データは同ディレクトリの `Records/` |
| 入力ハーネス | [入力記録「初回実装の記録」](simulator-input-verification.md#初回実装の記録独立レビュー修正前)。ソース `7827813b9cd5ebab41cda3703b595f21dd2bf1ce` ＋当時の未コミット変更、専用端末 `D6680B77-8EF7-4A8D-A454-CB796D4C2EAF`。ハーネスの `Records-20261003-085119/device.json` にホスト・補助・観測アプリの SHA256、同記録の `events.json`・`results.json` に観測結果 |
| タブ検査 | [タブ記録「専用端末での確認」](simulator-tab-verification.md#専用端末での確認)。Debug 版、専用端末 `EF889EC1-1276-47C4-B42A-0FD300F23A91`、`.build/simulator-tab-20261003-105254/` に端末・ウィンドウ・イベント・前後一覧・画像 |

| 合格項目 | 観測値・根拠 |
|---|---|
| 連続表示 | 関門で約30秒、1206×2622 BGRA の画面と移動する矩形を観測。FPS・遅延の合格を意味しない |
| タップ・ドラッグ | 入力ハーネスでカウンター 1→2、専用領域のパン終了と移動量を観測。関門でもドラッグ終了時の X 移動約181ポイントを記録 |
| 英字・修飾キー・貼り付け | 入力ハーネスで `a`→`aB`、貼り付け後 `aB貼付` を観測。日本語の貼り付けは日本語変換の検証とは別 |
| ホーム | 関門・入力ハーネスで専用アプリのバックグラウンド移行を観測。関門のホスト画像はホーム画面 |
| スクロール量・新しいタップ | 入力ハーネスで専用 UIScrollView の位置が最大652ポイント、スクロール中の新しいタップでカウンター2、保留した接触の再開なし |
| フォーカス喪失時の入力解放 | 入力ハーネスで `touchesEnded`（120,250）と C（HID 6）の押下・解放を観測 |
| 実タブの表示・タップ、Simulator.app 同時表示 | タブ検査で Phlox の画面を撮影、観測アプリのタップ1・位置（150,160）・押下／解放を確認。Simulator.app 同時表示中も Phlox からのタップが到達 |
| タブの取得停止・非表示部品の表示 | タブ記録のパッケージ検査でビュー取り外し後の detach・接続削除・画面情報解放、320pt・520pt の非表示描画を確認。実接続での非表示→復旧の合格には含めない |
| 検査専用端末の後始末 | 入力ハーネスで前後一覧の既存端末が不変、追加端末は Shutdown。タブ検査でも専用端末を shutdown、既存端末は起動・変更・削除なし |

| 未検証項目 | 範囲・制限 |
|---|---|
| iOS 側の日本語入力・回転 | 日本語変換、縦・逆さ縦・左横・右横での四隅タップは未検証 |
| 実接続の異常・再接続 | 補助プロセス終了、応答期限切れ、再接続、異常中の本体チャット／ターミナル継続、実接続での非表示からの復旧は未検証。fake の単体検査と区別する |
| Release・配布 | 公証済み Release、Release／Debug 同時起動は未検証。関門の Developer ID 署名確認は公証済み配布物の検査ではない |
| 共存・表示性能 | Simulator.app 側からの入力との同時操作、30fps・遅延・同期の完全性、XPC の実通信バイト数は未検証 |

## 画面を奪わず実施する品質検査

リポジトリのルートで実行する。すべての生成物をその worktree 内に置く。

```sh
mkdir -p .build/SimulatorS7Renders
PHLOX_SIMULATOR_RENDER_DIR="$PWD/.build/SimulatorS7Renders" \
  ~/.agents/scripts/compact-test --full simulator-s7-packages bash macos/scripts/run-swift-tests.sh
~/.agents/scripts/compact-test --full simulator-s7-dashboard \
  swift test --package-path macos/Packages/DashboardFeature --no-parallel
~/.agents/scripts/compact-test --full simulator-s7-bridge \
  swift test --package-path macos/Packages/SimulatorBridgeKit
bash macos/scripts/verify-simulator-display.sh
~/.agents/scripts/compact-test --full simulator-s7-signing-variants \
  bash macos/scripts/tests/test_signing_entitlements_variants.sh
xcodebuild -project macos/Phlox.xcodeproj -scheme PhloxUITests -configuration Debug \
  -derivedDataPath "$PWD/.build/DerivedData" build-for-testing
```

署名検査は `verify-simulator-display.sh` 内の `test_simulator_bridge_signing.sh` を正本とする。
既定の全パッケージはパッケージ間を直列実行し、DashboardFeature の本体・実 git の両パスが成功することを確認する。
凍結済みの `test_signing_entitlements_variants.sh` は変更せず実行し、証明書未設定などで実ビルドが省略された場合は、その項目を未検証と記録する。
UI テストはここでは実行しない。PM が画面を使える時間に次を実行する。

```text
-only-testing:PhloxUITests/SimulatorTabUITests/testShortcutOpensSimulatorWithDeviceMenuFocusAndWithoutDuplicate
-only-testing:PhloxUITests/SimulatorTabUITests/testPlusChooserOpensSimulatorAndCanReturnToConversation
-only-testing:PhloxUITests/SimulatorTabUITests/testSimulatorSupportsSplitAndUnsplit
```

## 許可リストに追加するための実端末検査

1. `xcodebuild -version`、`xcrun simctl list runtimes`、`sw_vers` を記録する。アプリと同梱 XPC の build・版・署名、ソースのコミットと未コミット差分も残す。
2. `simctl create` で検査専用端末を作り、UDID・端末種別・寸法・倍率を記録する。使用中の端末は操作しない。
3. [入力ハーネスの手順](../../Tests/SimulatorInputHarness/README.md)で専用観測アプリをインストールし、`events.json`・`measurements.json`・画面の記録で入力結果を判定する。
   未登録の組や表示のみの組の入力確認には Debug の `--compatibility-check` を明示する。空の許可リストで常に `.unverified` として検査し、`results.json` の「実行モード」に残す。版不一致・部品の読み込み失敗は解除しない。
   通常の `run.py` は前面化するので、共有の Mac では実行せず、PM の占有時間にまとめる。画面更新だけを入力成功の証拠にしない。
4. 下表を項目別に記録する。実アプリの異常系では自分のアプリの XPC の PID と親子関係を確認し、その補助プロセスだけを終了させる。
   Phlox 本体、既存の Simulator.app、他セッションの補助プロセスを停止しない。期限切れの実接続検査も PM の占有時間に行う。
5. 公証済み Release と Debug で同じ専用端末を表示する。Simulator.app 共存も専用端末で確認する。
6. 終了時は今回作った端末だけを shutdown し、既存端末の状態が変わっていないことを前後の一覧で確認する。
7. 全項目が合格した組だけを `SimulatorPolicy.verified.entries` に追加する。表示だけ合格した場合は `supportsInput: false` とし、入力未確認を明記する。
   Xcode 27 を追加する場合は、入力が成功を返して無視される問題の回避経路を一次資料と実入力結果で確認する。
8. テスト・ビルド・署名検査を再実行して記録へのリンクとともにレビューする。既存エントリーを範囲指定へ広げない。

## 実行記録の雛形

日付ごとのファイルを `macos/docs/operations/` に置き、結果は「合格」「失敗」「未検証」で記載する。
手元だけの検査は「手元で実行、テストには未登録」とし、fake の検査と実プロセスの検査を区別する。

| 環境 | 値 |
|---|---|
| 日時・担当者・ソース版／差分 | 未記入 |
| 本体 build・補助 build・通信仕様の版 | 未記入 |
| Debug／Release・署名・公証状態 | 未記入 |
| Xcode バージョン・build | 未記入 |
| macOS バージョン・build | 未記入 |
| iOS runtime 識別子・バージョン・build | 未記入 |
| 専用端末名・種別・UDID・ピクセル寸法・倍率 | 未記入 |
| 観測アプリ・実行ファイルの版／ハッシュ | 未記入 |
| 生データ・画面・ログの保存先 | 未記入 |

| 項目 | 結果 | 観測値・証拠 |
|---|---|---|
| 連続表示・surface ID と seed の更新／交代 | 未検証 | |
| タップ・ドラッグ・スクロール | 未検証 | |
| 英字・修飾キー・iOS 側での日本語入力 | 未検証 | |
| 貼り付け・ホーム | 未検証 | |
| 縦・逆さ縦・左横・右横での四隅タップ | 未検証 | |
| タブ非表示で取得停止、再表示で復旧 | 未検証 | |
| 切断ごとの自動再接続1回、画面受信後の回数復帰、60秒に3回の上限と手動再接続 | 未検証 | |
| probe／attach の期限切れと遅延応答の破棄 | 未検証 | |
| 終了・期限切れ中もチャットの入力・出力・状態更新が続く | 未検証 | |
| 終了・期限切れ中もターミナルの入力・出力が続く | 未検証 | |
| 切断で接触・キー解放、復旧後に古い入力を再送しない | 未検証 | |
| 未確認の組とタブ限定の例外、表示のみ対応の入力抑止 | 未検証 | |
| 部品読み込み失敗・通信版不一致で attach せず理由と外部表示 | 未検証 | |
| 5秒間静止した画面の診断とキーボードで選べる ⓘ | 未検証 | |
| Release／Debug 同時起動・各 flavor の補助プロセス | 未検証 | |
| Simulator.app 同時表示と両方からの入力 | 未検証 | |
| 検査前後の既存端末が不変、専用端末は shutdown | 未検証 | |

## §7-7 の初回実装検査記録（2026-10-03、独立レビュー修正前）

この節は専用端末の互換性合格記録とは別の、コード・ビルド・画面部品の検査記録。
worktree `simulator-allowlist` 内で実行し、稼働中のアプリは終了させず、実アプリの起動・画面操作・XCUITest の実行は行っていない。
変更は未コミットで、commit・push・merge は行っていない。

| 検査 | 実行結果 |
|---|---|
| 既定6パッケージ、パッケージ内も直列指定 | AgentDomain 565件、DesignSystem 193件、MessageStore 42件、SessionFeature 1,209件、DashboardFeature 1,832＋26件、SimulatorBridgeKit 16＋XCTest 3件。計3,886件成功、失敗0 |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel` | 範囲指定なしで1,858件成功、失敗0 |
| `swift test --package-path macos/Packages/SimulatorBridgeKit` | Swift Testing 16件＋XCTest 3件成功、失敗0 |
| `verify-simulator-display.sh` | XcodeGen・Debugビルド・対象パッケージ・署名・回帰のゲート成功 |
| `test_simulator_bridge_signing.sh`／`test_simulator_bridge_regressions.py` | 各4件成功、失敗0。成功ログも `compact-test --full` で確認 |
| 凍結済み `test_signing_entitlements_variants.sh` | 構造の7検査成功。チームID未設定によりDPKの実ビルドはスクリプト自身が省略し、未検証 |
| XcodeGen＋`Phlox` Debug build | 成功。DerivedData は worktree の `.build/DerivedData` |
| `PhloxUITests` build-for-testing | 成功。テスト本体は未実行 |
| 非対応・表示のみ・版不一致・読み込み失敗・起動失敗の描画 | 画面に出さず `NSHostingView.cacheDisplay` で画像化し、5状態の画像を目視確認 |
| 凍結ファイル・差分の空白検査 | 凍結ファイルのHEADとの差分なし、`git diff --check` 成功 |

全パッケージの実行には `SWIFT_TEST_SERIAL_PACKAGES="AgentDomain DesignSystem MessageStore SessionFeature DashboardFeature SimulatorBridgeKit"` を指定した。
DashboardFeature は既定スクリプトの本体・実gitの両パスを実行し、検査を除外したままにしていない。
ログは worktree の `.build/s7-all-packages.log`、`.build/s7-quality.log`、`.build/s7-signing.log`、`.build/s7-regressions.log`、
`.build/s7-signing-variants.log`、`.build/s7-build.log`、`.build/s7-build-for-testing.log`。
対象パッケージの単独全数ログは `.build/s7-dashboard-final.log`、`.build/s7-bridge-final.log`。
描画画像は `.build/SimulatorS7Renders/`。これらはGit対象外で、手元の実行結果を保持する。

警告は残っている。全パッケージの検査で既存のMainActor境界、非推奨API、未使用の戻り値、変更されない変数、冗長な `#require` の警告を観測した。
ビルドでは既存の `String(cString:)` 非推奨、明示的returnによるViewBuilder無効化、AppIntents未使用によるメタデータ抽出省略の警告を観測した。
シミュレーター関連のソース・テストについて、全パッケージの検査ログにコンパイラー警告は無かった。
独立したlint・静的解析は対象の品質ゲートに未設定。Swiftの型検査・リンクはビルドで実施した。
異常系のテストでは復元失敗、保存先への権限拒否、未マージの検査用ブランチの削除拒否などのエラーログも出ている。
これらのログを含め、上記のテストランナーが報告した失敗件数は0。

設計書との判断差分は、既存コードを正として次のとおり扱った。

- 非公開APIの実装ファイルは `PrivateSimulatorAPI.h/.m`。Swiftへ移し替えない。
- スクロールの位相を含む既存の通信仕様は版2。設計書の例の引数へ戻さない。
- 再接続の処理はハブが共有する `SimulatorDisplayConnection` に置き、切断ごとに1回だけ自動再接続する。正しい世代の画面を受信した復旧後にだけ回数を戻し、60秒間の自動再接続は3回までにする（2026-10-03 PM裁定）。
- 未確認の例外はセッションIDと許可したUDIDで照合し、別セッションや別端末へ広げない。ビューの破棄では維持し、タブ閉鎖・端末切替・アプリ終了で解除する（§3.8、今回のPM裁定）。
- 診断のしきい値は5秒。表示世代・surface ID・seedの更新を観測し、入力の成否には使わない。

本物の補助プロセスの終了・ハング、診断ボタンの実キーボード操作、Release／Debug同時起動、公証済み配布物の再検査は今回未実施。
終了・期限切れ中の本体セッション／ターミナル継続と再接続・世代破棄は、fakeのXPC配送を使うパッケージテストで検査した。
日本語入力・四方向など既存実行記録で未検証の項目も、今回合格へ書き換えていない。

## 独立レビュー修正後の検査記録（2026-10-03）

指摘7項目を修正し、変更は未コミットで保持する。実アプリ・XCUITest・入力ハーネスの起動と入力操作は行っていない。
設計書は本体チェックアウト側を読むだけとし、PM裁定を実装と運用記録に反映した。

| 指摘・設計書 | 修正 |
|---|---|
| 1・§3.3 | 表示IDから許可したUDIDを引いて照合し、別端末へ例外を引き継がない |
| 2・§3.3・§3.7 | 17C52 × iOS 26.2 の表示・入力対応を維持し、関門・入力・タブの正式記録と未検証項目を上記に統合 |
| 3・§5 | 非対応時のXCUITestを画面に出さない5状態の描画テストで代えるPM裁定をタブ記録に反映 |
| 4・§3.3・§3.8 | 手動再接続中も許可した端末の未確認表示を保つ |
| 5・§7-7 | 許可リスト照合を公開前に移し、選択中のXcode buildを照合するスクリプトと7件のテストを追加 |
| 6・§3.3 | 方針・ランタイム未設定なら非対応。既存テストとハーネスは明示設定し、ハーネス用の公開入口も許可リストを照合 |
| 7・NFR-2・§3.2・§3.4 | 切断ごとに1回、有効な画面受信後だけ回数を戻す。直近60秒の自動再接続は3回まで |

修正前の失敗は、指摘1・4の2テストで3指摘、指摘6の1テスト・2ケースで6指摘、指摘7の2テストで5指摘を確認した。
指摘2・3は文書内容検査2件、指摘5は照合スクリプト未作成による7エラーと公開順序の検査失敗を確認し、修正後に成功した。
文書内容・凍結ファイルの検査は手元で実行し、リポジトリのテストには未登録。照合スクリプトの7件は `macos/scripts/tests/test_simulator_allowlist.py` に登録した。
指摘7の最初の検査はビルド中にテストを編集してコンパイラーが中断した。編集を止めて再実行し、期待するテスト失敗を確認してから実装を修正した。

テストは `~/.agents/scripts/compact-test` 経由で実行した。全パッケージの実行では
`SWIFT_TEST_SERIAL_PACKAGES="AgentDomain DesignSystem MessageStore SessionFeature DashboardFeature SimulatorBridgeKit"` を指定した。
既定スクリプトの本体・実gitの両パスを実行し、テストの削除・追加の除外は行っていない。

| コマンド・検査 | 結果 |
|---|---|
| `bash macos/scripts/run-swift-tests.sh` | 既定6パッケージ計3,892件成功、失敗0。AgentDomain 565、DesignSystem 193、MessageStore 42、SessionFeature 1,209、DashboardFeature 1,838＋26、SimulatorBridgeKit 16＋XCTest 3 |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel` | 範囲指定なし、1,864件成功、失敗0 |
| `swift test --package-path macos/Packages/SimulatorBridgeKit` | Swift Testing 16件＋XCTest 3件成功、失敗0 |
| `bash macos/scripts/verify-simulator-display.sh` | 正本の品質ゲート成功。XcodeGen・Phlox Debug build・対象パッケージ・署名・回帰検査 |
| `bash macos/scripts/tests/test_simulator_bridge_signing.sh` | 生成したDebugアプリで4件成功、失敗0 |
| `python3 macos/scripts/tests/test_simulator_bridge_regressions.py` | 4件成功、失敗0 |
| `python3 macos/scripts/tests/test_simulator_allowlist.py` | 7件成功、失敗0。未記録build、部分一致、コメント、取得失敗、出力形式、公開順序を含む |
| `python3 macos/scripts/verify-simulator-allowlist.py` | 選択中の17C52と許可リストの照合成功。現行正式版かどうかの判定は公開担当が行う |
| `bash macos/scripts/tests/test_signing_entitlements_variants.sh` | 構造7項目成功。チームID未設定によりスクリプト自身がDPK実ビルドを省略（未検証） |
| `xcodebuild -project macos/Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath "$PWD/.build/DerivedData" build-for-testing` | 成功。UIテスト本体は未実行、PM向けの3件の指定は上記参照 |
| `bash macos/Tests/SimulatorInputHarness/build.sh` | ホスト・観測アプリのビルドとホスト署名検査成功。実入力は未検証 |
| 非対応など5状態の画像 | 全パッケージ検査で画面へ出さず描画し、生成画像5枚を目視確認 |
| 凍結・空白 | 凍結対象58ファイルにHEADとの差分なし、`git diff --check` 成功 |

主なログは `.build/s7-review-all.log`、`s7-review-dashboard.log`、`s7-review-bridge.log`、`s7-review-quality.log`、
`s7-review-signing.log`、`s7-review-build-for-testing.log`、`s7-review-harness-build.log`。
画像は `.build/SimulatorS7ReviewRenders/`。DerivedDataはすべてworktree内に置いた。

ビルドでは既存の `DashboardView.swift:597` の明示的returnによるViewBuilder無効化と、AppIntents未使用によるメタデータ抽出省略の警告を観測した。
許可リストの異常系テストが出す照合失敗ログは拒否動作の検査結果であり、テストランナーの失敗は0件。
独立したlint・静的解析は品質ゲートに未設定。型検査・リンクはビルドで実施した。
日本語入力・回転・実接続の異常・公証済みReleaseなど、正式記録の未検証項目は今回も実施していない。

## S7 再レビュー6項目の修正（2026-10-03、13:43検証終了）

この節は前節の7項目修正後に行った再レビューの記録。変更は未コミットのまま保持した。

| 項目 | 設計書 | 実装・検査 |
|---|---|---|
| 1 互換性検査入口 | §3.3・§3.7 | Debug の明示入口は空の許可リストで `.unverified` として検査する。登録済み・未登録・表示のみと、接続中の方針切替を検査。版不一致・部品読み込み失敗は解除しない。ハーネスは `--compatibility-check` と結果の実行モードを追加 |
| 2 表示内容の固定 | §3.8・§5 | 5状態と未登録buildの異常2ケースで、理由の全文・外部アプリを開くボタン・未確認試行・再接続を走査。帯の表示のみ対応とホーム無効化も検査 |
| 3 異常時の帯 | §3.3・§3.8 | Hub は `blocksRetry` を先に照合し、非対応を返す。例外を許可しても異常時に未確認実行中の帯を出さない |
| 4 品質ゲート | §7-7 | 表示品質ゲートから許可リスト検査を `compact-test` 経由で呼ぶ |
| 5 フレーム観測 | NFR-4・§3.8 | 3変数を `@ObservationIgnored` に変更。監視へ通知しないことと、非表示ビューの TimelineView が1秒周期で診断文言を更新することを検査 |
| 6 例外の寿命 | §3.4・§3.8、PM裁定 | 許可はHubがセッションIDとUDIDで保持。同じセッションの表示は共有し、別セッションには伝えない。ビュー再作成では維持し、タブ閉鎖・端末切替・終了で解除。元の端末へ戻しても復活しない |

### 修正前の赤と修正後の緑

| 項目 | 赤 | 緑 |
|---|---|---|
| 1 | 入口未実装によるコンパイル失敗2箇所、同じruntimeの方針切替で1テスト2問題、モード記録の回帰検査失敗 | Connection 19テスト、許可リスト関連10テスト成功 |
| 2 | 帯識別子欠如で1問題。異常時の試行ガード・ホーム無効化を外す一時変更でも9問題を検出 | Presentation 8テスト成功。7状態の理由と操作を検査 |
| 3・6 | Policy 10テストの実装前検査で10問題。異常時の帯、再作成、同じセッション内共有、端末切替後の復活を検出 | Policy 10テスト成功 |
| 4 | ゲートに許可リスト検査がなく1テスト失敗 | Python 10テストと品質ゲート成功 |
| 5 | フレーム更新の監視通知で1問題。診断周期を3600秒にする一時変更でも1問題を検出 | Connection・Presentation成功、周期は1秒に復帰 |

赤緑の原ログ・履歴抜粋は worktree の `.build/s7-new-policy-red.log`、`s7-new-policy-green.log`、
`s7-background-red.log`、`s7-connection-red-green.md`、`s7-presentation-mutation-red.log`、`s7-presentation-final-green.log`。
Connectionの初回赤緑はツール履歴の抜粋で、全生ログは保存していない。
通常の表示分岐は元から正しく、項目2の本体変更は帯の識別子追加だけ。一時変更は復帰済み。

調査中には、未初期化のSwiftUIアクセシビリティ走査が空になり7状態で24問題、参照元Composerの単独検査でも7問題を観測した。
`.prohibited` と `finishLaunching()` で解消した。調査で試した `accessibilityContents()` は未対応セレクタでシグナル6となったため除去し、既存の子要素走査だけを使用した。
ビルド中のソース変更によるコンパイル中断も1回発生した。以後は編集と検査を直列化し、最終検査は成功した。

### 最終検証

テストは `~/.agents/scripts/compact-test` を経由した。下表のテストコマンドはラッパーの後へ渡した部分。生成・ビルドはCLIを直接実行した。
生成物・DerivedData・実行記録はこのworktree内に保存した。アプリを前面化せず、XCUITest本体は実行していない。

| コマンド | 結果 |
|---|---|
| `bash macos/scripts/run-swift-tests.sh` | 既定6パッケージ直列、3,899件成功・失敗0（Swift Testing 3,896件＋XCTest 3件）。Dashboardの本体と実git両パス成功 |
| `swift test --package-path macos/Packages/DashboardFeature --no-parallel` | 全数1,871件成功・失敗0 |
| `swift test --package-path macos/Packages/SimulatorBridgeKit` | 全数19件成功・失敗0（Swift Testing 16件＋XCTest 3件） |
| `bash macos/scripts/tests/test_simulator_bridge_signing.sh` | 4件成功・失敗0 |
| `python3 macos/scripts/tests/test_simulator_allowlist.py` | 10件成功・失敗0 |
| `python3 macos/scripts/tests/test_simulator_bridge_regressions.py` | 4件成功・失敗0 |
| `bash macos/scripts/verify-simulator-display.sh` | Debugビルド、パッケージ、3本のスクリプト成功 |
| `/opt/homebrew/bin/xcodegen generate`（macos内） | 成功 |
| `xcodebuild -project macos/Phlox.xcodeproj -scheme PhloxUITests -configuration Debug -derivedDataPath "$PWD/.build/DerivedData" build-for-testing` | TEST BUILD SUCCEEDED。テスト本体は未実行 |
| `bash macos/Tests/SimulatorInputHarness/build.sh` | ホスト・観測アプリのビルド、ホスト署名検査成功 |
| `python3 .build/s7-background-check.py` | 手元で実行、テストには未登録。互換性モード記録・背景配送完了・iOS側のタップ到達の3検査成功 |

ログは `.build/s7-new-all-packages.log`、`s7-new-dashboard-full.log`、`s7-new-bridge-full.log`、
`s7-new-quality-gate.log`、`s7-new-build-for-testing.log`、`s7-new-harness-build.log`、
`s7-new-signing-final.log`、`s7-new-regressions-final.log`、`s7-new-allowlist.log`、`s7-new-background-check.log`。
9枚の非表示描画画像を `.build/S7FinalRenders/` に保存し、表示のみ・未登録の版不一致・未確認の3枚を目視確認した。
変更禁止対象58ファイルと `.env*` に差分なし。`git diff --check` 成功。

### 専用端末と判断・未検証

専用iPhone 17は `simctl create` で作成した `9C400CF0-6B10-468A-908D-FF21C01A3398`。
Xcode 26.2 / 17C52、iOS 26.2 / 23C54、402×874ポイント、倍率3。
ホストは `open -g -n -W` と `--background-tap --compatibility-check` で起動し、画面操作を伴う通常 `run.py` は実行していない。
背景タップのフォーカス準備にも前面化コードが残っていたため、回帰検査の赤を確認して背景モードで呼ばないよう修正した。
端末はshutdown済みで削除せず保持。検査前後で既存端末の状態差分はなかった。
記録は `.build/s7-background-20261003-134312/` の `device.json`・`events.json`・`results.json`・`host.log`・前後の端末一覧。
未登録・表示のみの組の検査はfakeによるパッケージテスト。実接続は上記の1組で背景タップだけを検証した。
この検査を、許可リストへ追加するための全項目合格とは扱わない。

既存のViewBuilder無効化警告と、AppIntents未使用によるメタデータ抽出省略警告が残る。
Dashboard全数には、削除拒否を検査するテストの未マージ枝の削除失敗ログもあるが、テスト失敗は0件。
独立したlint・静的解析は品質ゲートに未設定。型検査・リンクはビルドで実施した。
日本語入力・回転・実接続の異常・公証済みReleaseは未検証。PM向けのXCUITest指定は本書の既存3件を参照する。
