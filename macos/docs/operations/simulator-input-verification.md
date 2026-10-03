# シミュレーター入力の実行記録（§7-5）

## 独立レビュー修正後（2026-10-03 09:32）

専用端末 `B05E0E3E-02EC-4DB6-B991-20B838BBFBFB` で15項目成功。
100pt入力でホイール86pt、トラックパッド81ptを観測し、±20%の判定を満たした。
両方式の終了速度は UIKit の `scrollViewWillEndDragging` で X/Y とも0。
ボタン上の1pt入力は両方式ともタップを発火しなかった。
記録は `macos/Tests/SimulatorInputHarness/.build/Records-20261003-093224/`。
`measurements.json` に入力量・移動量・終了速度を保存した。環境は下記初回記録と同じ。
前後の端末一覧を手元で比較し、既存端末が不変で、専用端末が Shutdown であることを確認した
（この一覧比較はテストには未登録）。端末は削除していない。

修正内容と判断:

- 慣性イベントを本体で除外し、開始・継続・終了・取消を XPC で伝える。通信仕様は版2。
- トラックパッドは接触を維持し、ホイールは5pt以下の移動を20ms間隔で送る。
  同一座標の再送だけでは iOS の移動イベントが発生せず、120ms停止しても慣性が残った。
  最後の1ptを120msで終点へ送り、さらに120ms停止して解放すると、終了速度0を観測した。
- 接触開始は端から44pt内側へ寄せる（小画面では各寸法の1/4まで）。
  この端末ではパンの認識まで約20ptの移動が使われたため、その約2倍を安全幅として選んだ。
  44ptはこの実装の工学的な選択であり、iOSが公開するシステムジェスチャーの境界値ではない。
  補助プロセスのテストで端からの開始座標を検査した。他の端末での妥当性は未検証。
- 誤タップを防ぐため、10pt未満は接触を作らず合算する。
  短いトラックパッド操作は終了時に破棄し、ホイールは次の差分と合算する。
  接触開始後は終了まで維持する。画面端に達した移動は画面内に制限する。
- 表示寸法が失われたドラッグを本体から解放し、補助側の重複押下は古い位置で離してから押す。
  接続が失効した古いドラッグからは、新しい接続へ解放を再送しない。
- 本体は送信済みキーのリピートを送らず、補助側も押下中キーのリピートに修飾キーを合成しない。
- フォーカス喪失時の解放は従来どおり `touchesEnded`。押下中のボタンが発火し得る。
  NFR-7を満たすとの裁定に従い、この挙動は変更していない。

本体の再現テストは修正前に3項目で失敗（慣性3ケース、寸法0、リピート2ケース）、位相のテストも失敗。
補助側の6検査も修正前に失敗し、修正後に成功した。
テスト準備中にはヘッダーの参照先誤りと、関数ポインタを KVC で設定できない例外が出たため、
参照先とテスト側の設定方法を直した。修正途中には `flagsChanged` の `isARepeat` 参照で例外が出たため、
本体で `keyDown` の場合だけ参照するように直した。旧接続のドラッグから解放を再送した失敗も修正した。
端末検査の修正前は100ptのホイールで547pt進み、小量入力がタップを発火した。
途中の試行は慣性の残存・移動量不足・後半の入力記録欠落で失敗した。入力記録欠落の原因は確定できていない。
ハーネスは各操作前にフォーカスを確認し、確認できない場合は失敗するようにした。
途中の専用端末も shutdown 済みで保持している:
`9F9AA3EA-CAE2-4CD2-9DAC-3F60FCCC2716`、
`01A2F89A-6D96-4793-8725-117F5252CD43`、
`1AD4B13F-E05D-4484-96F5-300B2E954B46`。

日本語変換・四方向・Simulator.appとの同時操作・実接続の異常と再接続・Debug/Release同時起動・公証は未検証。

### 今回の変更ファイル

- DashboardFeature: `Simulator/SimulatorScreenView.swift`、`Simulator/SimulatorDisplayConnection.swift`。
- DashboardFeatureTests: `SimulatorInputDeliveryTests.swift`、`SimulatorDisplayConnectionTests.swift`。
- SimulatorBridgeKit: `SimulatorBridgeProtocol.swift`。
- SimulatorBridgeKitTests: `SimulatorBridgeAllowedClassesTests.swift`、`SimulatorBridgeContractTests.swift`。
- SimulatorBridgeService: `PrivateSimulatorAPI.h`、`PrivateSimulatorAPI.m`、`main.swift`。
- SimulatorInputHarness: `Host/InputHarness.swift`、`Observer/InputObserver.swift`、`run.py`、`README.md`、
  新規 `PrivateInputTests.m`、新規 `test-private-input.sh`。
- この実行記録。

### 最終検証

指定の `verify-simulator-display.sh` を正本として実行し、XcodeGen・Debugビルド・指定2パッケージ・署名・回帰検査が成功した。
DerivedDataはこのworktreeの `.build/DerivedData`。詳細ログは `.build/s5-quality-final.log`。
署名検査と回帰検査は `compact-test --full` でも実行し、各4件成功した。
補助プロセスの6検査と、専用端末ハーネスの15項目は成功した。
独立したlint・静的解析の設定は対象の品質ゲートにない。Swiftの型検査はビルド時に行われる。
ビルドには AppIntents.framework の依存がなくメタデータ抽出を省略する警告が出た。

件数記録のための追加の全数実行では、既存の `AcceptancePaneDefaultsIsolationTests` が1件失敗した。
検査中に標準保存先の `phlox.grid.paneLayout` が153バイトから19バイトに変わった記録がある。
該当の製品コード・テストは今回変更していない。別のSwiftテストプロセスの稼働も観測したが、干渉の有無は未確定。
該当テストの単独実行は成功した。失敗ログは `.build/s5-package-counts.log`、単独実行は `.build/s5-defaults-investigation.log`。
テストの除外、期待値の変更、稼働アプリの停止はしていない。
その後、条件を変更せず指定の全数コマンドを再実行し、DashboardFeatureは1787件（本体1761＋実git26）、
SimulatorBridgeKitは16件が成功した。最終の全数ログは `.build/s5-packages-final.log`。

実行コマンド（テストはいずれも `~/.agents/scripts/compact-test` 経由）:

| コマンド | 最終結果 |
|---|---|
| `bash macos/scripts/run-swift-tests.sh DashboardFeature SimulatorBridgeKit` | 1787件＋16件成功、失敗0 |
| `bash macos/scripts/tests/test_simulator_bridge_signing.sh` | 4件成功、失敗0 |
| `python3 macos/scripts/tests/test_simulator_bridge_regressions.py` | 4件成功、失敗0 |
| `bash macos/Tests/SimulatorInputHarness/test-private-input.sh` | 6検査成功、失敗0 |
| `python3 macos/Tests/SimulatorInputHarness/run.py --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2` | 15項目成功、失敗0 |
| `bash macos/scripts/verify-simulator-display.sh` | 指定の品質ゲート成功、Debugビルド成功 |
| `bash macos/Tests/SimulatorInputHarness/build.sh` | 本体・補助・観測アプリのビルド成功 |

Debugビルドの実コマンドは品質ゲート内の `xcodegen generate --spec macos/project.yml` と、
`xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath .build/DerivedData build`
（スクリプトではworktree内の絶対パスを指定）。凍結ファイル、`.env*`、本体チェックアウトへ書き込みなし。
commit・push・mergeは実行せず、既存変更と今回の変更を未コミットのまま残した。

## 初回実装の記録（独立レビュー修正前）

2026-10-03、本番の画面部品・接続・補助プロセスを確認用ハーネスで実行した。
入力の成否は専用 iOS アプリのイベント記録で判定し、画面更新は使っていない。
この端末検査は手元で実行したもので、Swift パッケージのテストには未登録。

| 環境 | 値 |
|---|---|
| ソース | `7827813b9cd5ebab41cda3703b595f21dd2bf1ce` ＋この worktree の未コミット変更 |
| Xcode | 26.2 / 17C52 |
| macOS | 26.6.2 / 25G83 |
| iOS | 26.2 / 23C54 |
| 端末 | 専用 iPhone 17、402 × 874 ポイント、倍率 3 |
| 最終確認 UDID | `D6680B77-8EF7-4A8D-A454-CB796D4C2EAF`（shutdown 済み、削除せず保持） |
| 初回確認 UDID | `707A3B80-F182-4296-A5C4-A4714BA789E4`（shutdown 済み、削除せず保持） |

| 検査 | 最終確認の観測 |
|---|---|
| タップ | カウンター 1 → 2 |
| ドラッグ | 専用領域のパン終了と移動量 |
| スクロール | 専用 UIScrollView の位置、最大 652 ポイント |
| 英字・修飾キー | `a` → `aB` |
| 貼り付け | `aB貼付` |
| フォーカス喪失時の接触解放 | `touchesEnded`、位置 (120, 250) |
| フォーカス喪失時のキー解放 | C（HID 6）の押下・解放を `pressesBegan` / `pressesEnded` で観測 |
| ホーム | 専用アプリのバックグラウンド移行 |
| スクロール中の新しいタップ | カウンター 2、保留した接触の再開なし |

9 項目成功。前後の端末一覧の比較で既存端末の項目が不変であり、追加した端末が Shutdown であることを確認した。

再現手順と確認アプリは [ハーネスの README](../../Tests/SimulatorInputHarness/README.md)。
詳細は `macos/Tests/SimulatorInputHarness/.build/Records-20261003-085119/` の
`device.json`（ホスト・補助・観測アプリのバイナリ SHA256 を含む）、`events.json`、`results.json`、
`commands.log`、`host.log`、端末一覧の前後記録に残した。生成記録は Git 管理対象外。

§3.7 の日本語変換、四方向、Simulator.app との同時操作、実端末接続での補助プロセス異常・期限切れ・再接続、
Debug/Release 同時起動は未検証。公証は実施していない。Xcode build `17C52` × iOS 26.2 の表示・入力対応は、PM 裁定により [正式な互換性実行記録](simulator-compatibility-verification.md#xcode-17c52--ios-262-の正式な実行記録) を根拠として許可リストに登録する。未検証項目の合格や ADR の accepted 化は行っていない。
