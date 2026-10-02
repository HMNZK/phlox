# シミュレーター関門の実行記録

関門の判定は **一部通過**。手元の Developer ID 署名と hardened runtime で、連続表示・タップ・ドラッグ・キー・ホームを確認した。公証済みでの確認は未実施。XPC の実際の通信バイト数も未確認のため、正式な関門通過や許可リストへの登録は行わない。

## 1. 実装項目と設計書の対応

正本は `/Users/ryosuke/Projects/Phlox-oss/macos/docs/specs/embedded-ios-simulator.md`。本体への組み込みは行っていない。

| 節 | 項目 | 観測結果と根拠 |
|---|---|---|
| §7-1、§3.2 | 独立ホスト＋XPC サービス | SwiftUI を載せる最小の macOS ウィンドウと埋め込み XPC サービスを構成。非公開 API の呼び出しは `Service/PrivateSimulatorAPI.m` 内のみ。ホストのリンク一覧に CoreSimulator / SimulatorKit はない（`Records/signing.log`）。 |
| §7-1、§3.2 | 非公開フレームワークの読み込み | サービスで両方の `dlopen` に成功（`Records/service.jsonl` 冒頭）。両バンドルの署名検査成功、runtime フラグあり、`disable-library-validation` なし（`Records/signing.log`）。 |
| §7-1、§3.7 | 連続表示 | 約30秒の接続中に画面を表示。1206×2622、画素形式 1111970369（BGRA）、端末は402×874ポイント・3倍。ホスト画像のアニメーション矩形が移動（`Records/render.json`、`host-02/03/06/07/10/11.png`）。表示 FPS・遅延・同期の完全性は未確認。 |
| §7-1、§3.7 | タップ | 専用アプリでカウンターが1になった（`Records/events.json` の「タップ」）。配送の戻り値だけでは判定していない。 |
| §7-1、§3.7 | ドラッグ | 専用アプリで開始→移動→終了を観測。終了時の X 移動は約181ポイント（`Records/events.json`）。ホスト画像にも「ドラッグ: 180」（`Records/host-23.png`）。 |
| §7-1、§3.7 | キー・修飾キー | HID usage 4（A）、225（左Shift）、5（B）の押下・解放を送り、専用アプリの文字が `a` → `aB` となった（`Records/events.json`、`host-23.png`）。対話操作のキー実装は A・B・左Shift のみ。Mac 側のキーイベント経由の操作は未確認で、自動実行は同じ XPC 入力関数に直接送る。 |
| §7-1、§3.7 | ホーム | ホームの押下・解放後、専用アプリがバックグラウンドへ移行し、ホスト表示がホーム画面になった（`Records/events.json`、`host-27.png`）。 |
| §1.3 | 初回 surface が更新され続けるか | サービスとホスト双方で ID **239** を継続保持。サービスの seed は **2317→3309**。保持した初回 surface の seed も同じように変化（両 `jsonl`）。この実行環境と約30秒の観測範囲では更新され続けた。 |
| §1.3 | surface が交代するか | この実行では交代を観測しなかった。サービス546サンプル、ホスト299サンプルの ID は239のみ。異なる端末・回転・長時間での交代は未確認。交代時だけ新しい surface を送る処理はあるが、その分岐の実動作は未確認。 |
| §1.3 | XPC の通信量 | サービス側の描画通知993回に対し、ホストへの surface 送信・受信は **1回**。画素領域は12,763,136バイトだが、これは通信量ではない。NSXPCConnection の制御情報・返信・Mach ポートを含む実通信バイト数は未確認。 |
| §1.3 | `layer.contents` の再設定 | 初回設定のみ（0〜4秒）、同じ surface 再設定（4〜8秒）、nilを挟んだ再設定（8秒以降）の3方式で更新を観測。矩形左端の実画素座標はそれぞれ **120→548、88→192、452→580**（`Records/render.json`）。初回設定のみでも更新したが、この環境以外には一般化しない。 |

通信量の追加計測として、最初の surface を `NSKeyedArchiver` で符号化しようとしたが失敗した。原文は `NSCocoaErrorDomain Code=4866`、`This object may only be encoded by an NSXPCCoder.`（スタックを含む原文は `Records/service.jsonl` の「符号化結果」）。記録の「surface符号化バイト: 0」はこの失敗時の nil データの長さであり、XPC が0バイトだったという意味ではない。NSXPCInterface の許可クラスを両側で設定した実際の XPC 送信・受信は成功している。

## 2. 追加・変更ファイル

- `Host/GateApp.swift`、`Host/GateHost.h`、`Host/GateHost.m`：試作ホスト、表示・入力・観測。
- `Service/PrivateSimulatorAPI.m`：動的読み込み、表示ポート、HID、サービスの入口。
- `Shared/Bridge.h`、`Shared/Bridge.m`：XPC プロトコルと両側共通のインターフェース設定。
- `TestApp/GateTest.swift`：アニメーション、タップカウンター、ドラッグ、文字欄、バックグラウンド移行の記録。
- `project.yml`、`build.sh`、`run.py`、`check-render.swift`、`test_observations.py`、`.gitignore`、本書。
- `Records/`：最終実行のログ・画像・署名検査・端末状態。
- `Records-attempt1/`、`Records-attempt2/`、`Records-attempt3/`：途中の失敗記録。
- `Licenses/`：参照した一次資料のライセンスと NOTICE 原文。
- リポジトリ直下の `THIRD_PARTY_NOTICES.md`：参照元とライセンスの追記。

`.build/` と生成した `.xcodeproj` は Git 対象外。既存パッケージ、Phlox のターゲット、凍結ファイル、署名テスト、`.env*` は変更していない。commit・push・merge は未実施。

## 3. 実行コマンドと結果

作業ディレクトリは `/Users/ryosuke/Projects/Phlox-oss-worktrees/simulator-gate`。テストは指定のラッパー経由で実行した。

| コマンド | 結果 |
|---|---|
| `~/.agents/scripts/compact-test simulator-build bash macos/Prototypes/SimulatorGate/build.sh` | macOS ホスト＋XPC、iOS 専用アプリの clean build 成功、両 macOS バンドルの署名検査成功。テスト件数ではない。 |
| `~/.agents/scripts/compact-test simulator-gate-retry4 python3 macos/Prototypes/SimulatorGate/run.py` | 専用端末での自動実行・8組のホスト画像と端末画像・結果保存・shutdown に成功。ラッパー出力は「OK（要約未対応）」。 |
| `~/.agents/scripts/compact-test --full simulator-render-final swift macos/Prototypes/SimulatorGate/check-render.swift macos/Prototypes/SimulatorGate/Records` | 6枚のアニメーション矩形を画素から計測。終了コード0。これは計測コマンドで、単体テストの件数ではない。 |
| `~/.agents/scripts/compact-test --full simulator-observations-final python3 macos/Prototypes/SimulatorGate/test_observations.py` | **10件、失敗0・エラー0**。読み込み、共有surface更新、3表示方式、表示画素の移動、タップ、ドラッグ、英字とShift、ホーム、署名と隔離、既存端末の状態と専用端末のshutdownを検査。 |
| `xcodebuild -project macos/Prototypes/SimulatorGate/SimulatorGate.xcodeproj -scheme SimulatorGate -configuration Release -derivedDataPath macos/Prototypes/SimulatorGate/.build/AnalysisData analyze` | macOS側の静的解析成功。ログ `.build/analyze.log`。 |
| `xcodebuild -project macos/Prototypes/SimulatorGate/SimulatorGate.xcodeproj -scheme GateTest -configuration Release -sdk iphonesimulator -derivedDataPath macos/Prototypes/SimulatorGate/.build/TestAnalysisData analyze` | iOS側の解析アクション成功。ログ `.build/test-analyze.log`。Swiftの追加解析範囲を保証するものではない。 |
| `git diff --check` | 成功。 |

ビルド・解析に共通する警告原文：`Metadata extraction skipped. No AppIntents.framework dependency found.` 本試作に AppIntents の依存はない。

途中の失敗を隠さず残している。初回の macOS 14 可用性警告は IOSurface の C API に変更して解消した。その編集時のコンパイルエラーも訂正した。初回の観測テストは8件中2件失敗（ドラッグ、英字）。2回目はドラッグが移動量0で失敗し、shutdown の記録保存前に検査したことによる `devices-after.json` 不在エラーも出た。3回目はホスト観測が始まらず40秒で失敗した。最終版では移動を接触維持として送り、短い間隔で順次配送し、surfaceを変更通知から保持し、ホストのウィンドウを明示生成して再検証した。

調査途中には一次資料URLの404と探索パス不在があり、取得したGitリポジトリで読み直した。終了済みホストへの `sample` は「no longer appears to be running」で失敗し、スタックは採取できなかった。予備の画像集計には Pillow の `Image.Image.getdata is deprecated` 警告が出た。最終の画像計測には上記の AppKit スクリプトを使用した。

## 4. 判断・未検証・端末管理

- **公証済みでの確認は未実施**。署名は手元の Developer ID Application、Team ID `9JGGMW6UW6`、hardened runtime。公証・タイムスタンプサーバーへの送信は実施していない。ad-hoc 署名へのフォールバック経路は未確認。
- Xcode **26.2 / 17C52**、macOS **26.6.2 / 25G83**、iOS **26.2 / 23C54**、iPhone 17・3倍。ホスト／サービス／専用アプリの build は **1**、版は **0.1**。
- §3.7の関門対象を超える項目（スクロール、専用の日本語入力手順、貼り付け、4方向の四隅、Simulator.appとの共存、サービス異常終了・期限切れからの再接続、非表示時の停止、Release/Debug同時起動、本体チャット／ターミナルへの影響）は未確認。初回の「あB」は保存したが、日本語入力の専用試験の合格とは扱わない。
- 既存 Swift パッケージには触れておらず、`swift test --package-path ...` は対象外。既存パッケージの回帰テストと本体の凍結済み署名テストは未実行。試作の lint・独立した型チェック用コマンドは未設定。Swift のコンパイルはビルドで実施した。
- 作成した端末は下表の4台。いずれもshutdown済み、deleteは未実施。既存端末へ boot・install・launch・入力・shutdown は送っていない。作成前後の既存端末の起動状態一致は保存した一覧で確認した。稼働中の `/Applications/*.app` は終了していない。

| 実行 | UDID | 記録 |
|---|---|---|
| 初回 | `7373B5A5-F02E-4C9F-AC2B-498B6691317E` | `Records-attempt1/` |
| 2回目 | `552457B7-9585-4645-A0FC-F1C5705B276C` | `Records-attempt2/` |
| 3回目 | `AAB34682-B2C5-4F1C-984F-D3ABE22149BD` | `Records-attempt3/` |
| 最終 | `801D9AD3-B072-4E8B-87C3-95D2C0A9AF94` | `Records/` |

再実行するときは `Records/` を別名で保存してから上記 build・run・画素計測・観測テストの順に実行する。run は固定の iPhone 17 / iOS 26.2 で毎回新しい専用端末を作る。既存の記録がある場合は上書きせず停止する。テスト用アプリの結果保存先へのアクセスは作成した端末のコンテナに限る。
