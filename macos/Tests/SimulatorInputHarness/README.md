# §7-5 入力確認用ハーネス

本番の `SimulatorScreenNSView`・`SimulatorDisplayConnection`・補助プロセスを使い、iOS 専用観測アプリの記録で入力を判定する。画面の変化を成功条件にはしない。本体アプリの入口は追加しない。

```sh
bash macos/Tests/SimulatorInputHarness/build.sh
~/.agents/scripts/compact-test simulator-input python3 macos/Tests/SimulatorInputHarness/run.py --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2
```

ランタイムは `xcrun simctl list runtimes` の利用可能な識別子を指定する。端末は毎回新しく作成し、終了時は shutdown して保持する。UDID・Xcode・macOS・ランタイム・倍率・観測値・判定は `.build/Records-*` に残る。既存端末は操作しない。ビルド生成物はこのディレクトリの `.build` に置き、公証は行わない。

自動確認範囲はタップ、ドラッグ、スクロール、英字・Shift、貼り付け、ホーム、フォーカス喪失時の接触・キー解放、スクロール中の新タップによる保留接触取消。解放は iOS 側の `touchesEnded` / `touchesCancelled` と `pressesEnded` を直接記録して判定する。スクロール中断は新タップ成功に加え、その後にスクロール領域の接触が再発しないことを `UIWindow.sendEvent` の記録で判定する。貼り付け時の Mac クリップボードは保存し、確認ホストの正常終了・エラー終了時に復元する。そのほか §3.7 の日本語変換・四方向・Simulator.app 同時操作・補助プロセス異常・再接続・Debug/Release 同時起動は、このハーネスでは未検証。

## 手元の実行記録

レビュー修正後は15項目を判定する。ホイールとトラックパッドの各100pt入力について移動量80〜120ptと終了速度0を検査し、ボタン上の各1pt入力でタップが発火しないことを検査する。入力量・移動量・終了速度は `measurements.json` に残す。

補助プロセス単体の6検査は、`~/.agents/scripts/compact-test --full simulator-private-input bash macos/Tests/SimulatorInputHarness/test-private-input.sh` で実行する。HIDの生成と配送のみを置き換え、本番のObjC実装で重複押下、キーリピート、小量入力、位相による接触維持、終点での停止、端からの開始位置を検査する。

環境は Xcode 26.2（17C52）、macOS 26.6.2（25G83）、iOS 26.2（23C54）、iPhone 17、402×874 ポイント・倍率3。公証は未実施。各回とも新しく作成した専用端末だけを操作し、終了後は shutdown、削除せず保持した。前後の端末一覧を比較する手元の assert で、既存端末が変化していないことを確認した（この一覧検査はテストには未登録）。

| 実行日時（日本時間） | 専用端末 UDID | 結果 | 記録 |
|---|---|---|---|
| 2026-10-03 08:47 | `707A3B80-F182-4296-A5C4-A4714BA789E4` | 8項目成功 | `.build/Records-20261003-084721/` |
| 2026-10-03 08:51 | `D6680B77-8EF7-4A8D-A454-CB796D4C2EAF` | 最終版9項目成功（保留接触取消を追加） | `.build/Records-20261003-085119/` |
| 2026-10-03 09:32 | `B05E0E3E-02EC-4DB6-B991-20B838BBFBFB` | レビュー修正後15項目成功、100pt→86pt/81pt、終了速度0 | `.build/Records-20261003-093224/` |

修正前の初回実装ではタップ1→2、文字 `a`→`aB`→`aB貼付`、スクロール最大652ポイントを観測した。フォーカス喪失時の接触解放は (120,250)、キー解放は C（HIDコード6）の押下・解放を直接確認した。`device.json` に本体・補助プロセス・観測アプリの実行ファイルと dylib の SHA256、Xcode/macOS/runtime、寸法・倍率を保存し、`events.json` に UIKit の実際の入力結果を保存した。記録は手元に保持しているが Git の対象外。

実行コマンドは `bash macos/Tests/SimulatorInputHarness/build.sh` と `~/.agents/scripts/compact-test --full simulator-input-final python3 macos/Tests/SimulatorInputHarness/run.py --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2`。host と観測アプリのビルド、署名検査は成功。AppIntents.framework への依存がないため metadata extraction skipped の警告が出た。
