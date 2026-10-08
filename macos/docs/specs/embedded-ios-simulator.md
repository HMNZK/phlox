---
status: completed        # 実装済み。現行構成は architecture/ にある（本書は設計時点の記録）
last-verified: 2026-10-06
---

# iOS シミュレーターのウィンドウ内表示 — 設計書

> **実装済み**: 現行構成は [architecture/embedded-ios-simulator.md](../architecture/embedded-ios-simulator.md)。

> **このドキュメントの役割**: 起動中の iOS シミュレーターの画面を Phlox のウィンドウ内（子タブ）に表示し、
> クリック・キー入力で操作できるようにする機能の、実現方式の調査結果・要件・設計・リスク・テスト計画。
> **書かないもの**: 実装後の現行構成（→ 実装完了時に `architecture/` へ蒸留）、決定の不変記録（→ 着手時に ADR。§8 が下書き）。
>
> **改訂履歴**: 2026-10-02 初版。同日、Codex（gpt-6.1-sol）との 5 ラウンドのレビュー議論を反映して改訂（関門の拡大・許可リストを組単位に・入力成否判定の撤回・XPC の通信契約・所有場所・永続化の正規化・キー入力方式）。
> 同日、Codex（gpt-6.1-sol）の最終レビューの条件を反映（キー解放の規則・凍結済み署名テストの扱い・FR の例外・テスト計画の補完）。
> 同日、Claude Design の UI モック（`specs/ClaudeDesign/7 Simulator Tab.dc.html`）で確定した見せ方と操作の細部を反映（§3.8）。

## 0. 要点（平易な言葉で）

- Xcode のようにシミュレーターを画面内に出す**公開された方法は無い**。Xcode・Expo・Meta の idb などは全て、
  Xcode に同梱された**非公開の部品**（CoreSimulator / SimulatorKit）を使っている。本機能も同じ方式を採る。
- 非公開部品は Xcode の更新で壊れることがある（特に操作の送信）。そのため、
  ①部品を使う処理は**別プロセス（補助プロセス）に隔離**し、壊れても・落ちても Phlox 本体と作業中セッションに影響させない、
  ②**動作確認済みの組み合わせ（Xcode と iOS のバージョン）でだけ有効**にし、それ以外は理由を表示する、の 2 つで守る。
- 表示場所は中央の子タブ「シミュレーター」。⌘\ で右に分割すれば、左で会話・コード、右でシミュレーターという Xcode 風の配置になる。
- シミュレーターの起動・アプリのインストール等は公開ツール `xcrun simctl` で行う。非公開部品は「画面を映す」「操作を送る」の 2 つだけに使う。
- 帯の「エージェントに伝える」で、表示中の端末（名前・iOS の版・UDID）を 1 行の文としてそのセッションの入力欄に入れられる。エージェントはその UDID で `xcodebuild -destination 'id=…'`・`xcrun simctl` を使えばよい（2026-10-06 追加）。

## 1. 調査結果（確度を 3 段階で明記）

### 1.1 手元で確認したこと（2026-10-02、Xcode 26.2 / Build 17C52、macOS 26）

| 確認内容 | 結果 |
|---|---|
| `CoreSimulator.framework` の場所 | `/Library/Developer/PrivateFrameworks/CoreSimulator.framework`（Xcode とは別にシステムへ導入済み） |
| `SimulatorKit.framework` の場所 | `$(xcode-select -p)/Library/PrivateFrameworks/SimulatorKit.framework`（Xcode.app の中。`/Library/Developer/PrivateFrameworks` には無い） |
| `dlopen` での読み込み | 両方とも成功（未署名・ad-hoc＋hardened runtime・**Developer ID 署名＋hardened runtime** の 3 通りの CLI バイナリで成功。公証済みのアプリバンドルでは**未確認**） |
| SimulatorKit の署名 | `TeamIdentifier=59GAB85EFG`（Phlox の Team ID とは別）。それでも上記のとおり hardened runtime 下で読み込めた |
| ObjC クラス（CoreSimulator） | `SimServiceContext`・`SimDeviceSet`・`SimDevice`・`SimDeviceIOClient` が存在 |
| ObjC プロトコル（CoreSimulator） | `SimDisplayIOSurfaceRenderable`・`SimDisplayRenderable`・`SimDeviceIOPortInterface`・`SimDisplayDamageRectangleDelegate` が存在 |
| SimulatorKit（Swift 製） | `SimulatorKit.SimDeviceLegacyHIDClient`（`send(message: IndigoHIDMessageStruct)`）、`SimulatorKit.SimDeviceScreen`（`unmaskedSurface: IOSurface?`・`surfacesChanged` イベント）、`SimDisplayView`・`SimDigitizerInputView` が存在 |
| C 関数（SimulatorKit） | `IndigoHIDMessageForMouseNSEvent`・`IndigoHIDMessageForKeyboardArbitrary`・`IndigoHIDMessageForButton`・`IndigoHIDMessageForScrollEvent` 等が `dlsym` で解決できる |
| 公開ツール | `xcrun simctl` に `boot`/`shutdown`/`install`/`launch`/`openurl`/`io screenshot`/`io recordVideo`/`list -j` があり、**画面の連続取得と操作の送信は無い** |

手元確認は「部品が存在し読み込める」までで、**実際に 1 フレーム取得する・タップを送る検証はしていない**
（手元で起動中のシミュレーターは別作業で使用中のため、操作は送っていない）。

### 1.2 二次情報（Web 上の資料。未検証）

- **既存ツールの方式**: Expo の serve-sim（Apache-2.0）、Baguette、Meta の idb / FBSimulatorControl（MIT）は、
  `SimDevice.io` から表示ポートを取り `SimDisplayIOSurfaceRenderable` の IOSurface と変更通知で画面を得て、
  Indigo HID メッセージを HID クライアントへ送って操作している。Radon IDE（Software Mansion）も同系統と推定されるが非公開バイナリ。
- **壊れやすさ**: 画面取得は比較的安定、**操作の送信が壊れやすい**。iOS 26 で HID メッセージ形式が変わった、3x 端末でタップ座標の
  倍率がずれる（idb issue #964、2026-09-19）、Xcode 27 では DeviceHub が `dtuhidd` を起動すると従来の Indigo 入力が
  **成功を返したまま無視される**（software-mansion/argent PR #1166）、という報告がある。
- **性能**: serve-sim は 60fps 超、Baguette は遅延 12ms を自己申告。第三者の計測は見つからず。
- **公証**: 公証はマルウェア・署名の自動検査で、非公開フレームワークの使用だけで拒否された記録は見つからなかった
  （App Store 審査とは別）。一次情報での裏付けは無い。

### 1.3 推定（根拠はあるが未確認。§7 の関門で確かめる）

- IOSurface はプロセス間で共有できる（`IOSurface` は `NSSecureCoding` に適合）。補助プロセスが取得した画面を本体へ渡せば、
  **毎フレームの通信なしで**表示できる可能性がある。ただし、最初に渡した surface が更新され続けるのか、複数の surface が交代するのか、
  書き込み完了と表示の同期、`layer.contents` の再設定で更新が表示されるかは**未確認の仮説**。
- `CALayer.contents` に IOSurface を直接設定すれば、Metal を使わずに表示できる可能性がある。

## 2. 要件

### 機能要件（FR）

| ID | 要件 |
|---|---|
| FR-1 | 子タブ「シミュレーター」を開ける（＋メニュー・⌃⌘Y）。タブの帯で端末を選ぶ（`simctl list -j` の iOS 端末。起動中を先頭） |
| FR-2 | 停止中の端末を選ぶと「起動」ボタンを出し、押すと `simctl boot` する。Simulator.app は開かない |
| FR-3 | 起動中の端末の画面を、縦横比を保ってタブ内に表示する（30fps 以上を目標） |
| FR-4 | 画面上のクリック＝タップ、ドラッグ＝スワイプ、スクロール＝スクロールとして端末へ送る |
| FR-5 | 端末の画面が first responder の間（帯にフォーカスがあるときは送らない）、**物理キー（キーコード＋修飾キー）**を端末へ送る。Mac 側の日本語変換は通さず、文字入力・日本語入力は iOS 側のキーボード設定で行う（Simulator.app の「ハードウェアキーボードを接続」と同じ考え方）。貼り付けは ⌘V で `simctl pbcopy` → 成功したときだけ端末へ ⌘V を送る |
| FR-6 | 帯のボタン: エージェントに伝える（FR-10）、ホーム、スクリーンショット（`simctl io screenshot` → Finder で表示）、停止（`simctl shutdown`。確認ダイアログに「この端末を表示中の他のタブ・Phlox の Debug/Release 版・Simulator.app にも影響します」と書く） |
| FR-7 | 同じ端末を複数のタブ・ウィンドウで表示しても、画面取得は 1 本だけにする |
| FR-8 | 動作確認済みでない組み合わせ・補助プロセスの起動失敗・部品の読み込み失敗・通信仕様の版の不一致のときは、理由と「Simulator.app で開く」を表示する。例外: ①許可リストで「表示のみ対応」の組み合わせは表示だけ有効にする ②「未確認でも試す」で無視できるのは許可リストだけで、部品の読み込み失敗・通信仕様の版の不一致は解除しない |
| FR-9 | Simulator.app で同じ端末を開いていても共存する |
| FR-10 | 帯の「エージェントに伝える」を押すと、選択中の端末を表す 1 行の文（`対象の iOS シミュレーター: <端末名>（<iOS の版>、UDID <UDID>）。Phlox で表示中の端末です。`）を、そのセッションの入力欄に入れる（チャット型は下書きの末尾、ターミナル型は CLI のカーソル位置）。送信はしない。入れたあとは会話のタブを前に出す（2026-10-06 追加。§3.8） |

### 非機能要件（NFR）

| ID | 要件 |
|---|---|
| NFR-1 | 非公開部品を本体プロセスへ読み込まない。補助プロセスが落ちても・応答しなくなっても本体・セッション・ターミナルは影響を受けない |
| NFR-2 | 補助プロセスの切断時は自動再接続を 1 回だけ行い、それでも駄目なら「再接続」ボタンを出す（繰り返し落ちる版での暴走を防ぐ）。補助プロセスの復旧で端末は停止しない |
| NFR-3 | 見えている表示が 1 つも無い間（タブが隠れている・ウィンドウが最小化）は画面取得を止める |
| NFR-4 | 画面の更新番号が一定時間変わらないときは「画面更新を観測していません」と**診断として**表示する（静止画面でも正常に止まるため、入力の成否判定には使わない）。入力が効いているかは §7 の関門と実行記録で確かめる |
| NFR-5 | タブの永続化形式（`phlox.sessionTabs.v1`）を、旧バージョンが読めない形にしない（§3.5） |
| NFR-6 | 停止中の端末を勝手に起動しない。ユーザーの操作なしに端末へ入力を送らない（診断のための自動入力もしない） |
| NFR-7 | フォーカスを失う・端末を切り替える・接続が切れるときは、押下中のキーと継続中の接触を必ず離す。再接続後に古い入力を再送しない |

## 3. 設計

### 3.1 全体像

```
Phlox.app（本体。非公開部品を読み込まない）
 ├─ SimulatorTabView（子タブ）── SimulatorScreenView（NSView。layer.contents = IOSurface、displayLink で seed を確認）
 │        │ 入力（正規化座標・キーコード）
 │        ▼
 ├─ SimulatorHub（PhloxApp が所有。アプリで 1 つ。端末ごとの取得セッションを可視表示の数で管理）
 │        │ NSXPCConnection（接続世代つき）
 │        ▼
 └─ Contents/XPCServices/<flavor ごとの ID>.xpc（補助プロセス）
          ├─ CoreSimulator（/Library/Developer/PrivateFrameworks）と SimulatorKit（xcode-select -p 配下）を実行時に dlopen
          ├─ 画面: SimDevice.io → 表示ポート → SimDisplayIOSurfaceRenderable の IOSurface を本体へ
          └─ 操作: Indigo HID メッセージ（C 関数を dlsym）→ HID ポートへ送信

端末の一覧・起動・停止・スクショ・pbcopy: 本体から `xcrun simctl`（公開ツール。Process で実行）
```

### 3.2 補助プロセス（XPC サービス）

- `project.yml` に XPC サービスのターゲットを追加し、アプリに埋め込む（`Contents/XPCServices/`）。寿命は launchd が管理し、
  本体が接続した時だけ起動する。**bundle ID は本体と同じ規則で flavor ごとに分ける**（ADR 0034。Release と Debug の同時起動）。
  本体は `NSXPCConnection(serviceName:)` に自分の flavor の ID を渡す。flavor を分けても**iOS 端末は共有**である点は FR-6 で示す。
- **XPC サービスにした理由**: 非公開 API の呼び出しが例外・クラッシュを起こしても、落ちるのは補助プロセスだけになる。
  作業中のエージェントセッションを抱える本体を落とさないことが最優先。ハング（応答が返らない）は別プロセスでも防げないので、期限で扱う（下記）。
- エンタイトルメントは本体と別ファイル。§1.1 のとおり hardened runtime 下でも読み込めたため
  `com.apple.security.cs.disable-library-validation` は付けない。公証済みビルドで読み込めないと判明した場合に限り、補助プロセスだけに付ける。
  `macos/scripts/tests/test_signing_entitlements_variants.sh` は凍結済み（`tasks/frozen/BASELINES.txt` に登録、`.claude/verify.sh` が無改変を検査）なので**変更しない**。
  XPC サービスの署名・エンタイトルメントの検査は別ファイル（例: `macos/scripts/tests/test_simulator_bridge_signing.sh`）として追加し、検証ゲートに組み込む。

**通信の契約**（プロトコルは新規の L0 パッケージ `SimulatorBridgeKit` に置き、本体と補助プロセスで共有。`NSXPCInterface` は両側で同じ設定）:

```swift
@objc protocol SimulatorBridgeProtocol {
    func probe(reply: @escaping (SimulatorBridgeCapability) -> Void)       // 通信仕様の版・補助 build・Xcode build・部品の読み込み可否
    func attach(udid: String, generation: Int, reply: @escaping (SimulatorDisplayInfo?, NSError?) -> Void)
    func detach(udid: String)
    func sendTouch(udid: String, phase: Int, x: Double, y: Double)         // 0〜1 の正規化座標
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double)
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool)
    func sendButton(udid: String, button: Int)
    func releaseAll(udid: String)                                          // 押下中キー・継続中の接触を離す
}
@objc protocol SimulatorBridgeClientProtocol {                             // 補助 → 本体
    func surfaceChanged(_ info: SimulatorDisplayInfo)
}
// SimulatorDisplayInfo（NSSecureCoding）: udid・接続世代・表示世代・IOSurface・ピクセルサイズ・向き（4 方向）・画素形式
```

- IOSurface は `NSSecureCoding` で渡す（`setXPCType` は使わない）。
- **期限**: 応答を待つ `probe`・`attach` だけに期限（5 秒）を設ける。タッチの移動等には設けない。期限切れは「相手の処理の取り消し」ではないので、
  期限切れ時は接続を invalidate し、遅れて届いた応答は**接続世代**で捨てる。補助側は接続が切れたらその接続の資源（取得・HID ポート）を解放する。
- **版の確認**: `probe` の通信仕様の版が本体と違えば attach しない（Sparkle 更新直後に旧版の補助プロセスへつながる場合など）。
  「アプリを再起動してください」を出し、自動再接続はしない。旧版プロセスの一括停止はしない（正常終了時に自分の接続を invalidate するだけ）。
- **非公開 API の閉じ込め**: 呼び出しは補助プロセス内の 1 ファイル（`PrivateSimulatorAPI.swift`）に閉じ込め、シンボルは実行時に
  `NSClassFromString` / `NSProtocolFromString` / `responds(to:)` / `dlsym` で解決する。欠けていれば `probe` が「非対応」を返す。
  これは**シンボルの有無だけの確認で、引数の構造や意味の互換性は確認できない**。互換性は §3.3 の許可リストと実行記録で担保する。
- **呼び出し経路は実装前に一次資料で確定させる**: idb の `FBSimulatorControl/HID/`・`FBFramebuffer`、serve-sim のキャプチャ部を読み、
  ObjC / C で呼べる面だけを使う（SimulatorKit の Swift クラスはモジュール外から安定して呼べない）。
  コードを流用する場合は MIT / Apache-2.0 の表記を `THIRD_PARTY_NOTICES.md` に追加する。

### 3.3 対応の許可リスト

- 許可リストは「**Xcode build × iOS runtime**」の組で持ち、**§3.7 の実行記録で合格した組だけ**を載せる（「Xcode 26.x」のような範囲指定はしない）。
  表示と入力の対応可否は分けて持つ（例: 表示は可・入力は未確認 → 表示だけ有効にし、帯にその旨を出す）。
- 載っていない組では「未確認の組み合わせ」を表示し、帯の「未確認でも試す」を押したタブに限り無視する（永続化しない）。
- Xcode 27 は §1.2 の「入力が黙って無視される」報告があるため、一次資料で回避策を確かめ、実行記録で合格してから載せる。
- **例外（2026-10-03 PM 裁定）**: 初回の組 Xcode 17C52 × iOS 26.2 は、§3.7 の項目のうち日本語入力・4 方向の向き・実接続での異常系・Release 版を**未検証のまま**、表示・入力とも対応として載せる。
  未検証項目は `macos/docs/operations/simulator-compatibility-verification.md` の記録表に明記し、確かめた時点で記録を更新する。2 組目以降はこの例外を使わず、上の原則（合格した組だけ）に従う。

### 3.4 本体側

| 型 | 置き場所 | 役割 |
|---|---|---|
| `SimulatorBridgeKit`（新規 L0 パッケージ） | `macos/Packages/SimulatorBridgeKit` | XPC プロトコル・能力値と表示情報の型・**座標変換の純関数** `SimulatorInputMapper` |
| `SimulatorCatalog` | DashboardFeature/Simulator/ | `simctl list -j devices` を読んで端末一覧。起動・停止・スクショ・pbcopy も `simctl`。stdout/stderr を並行排出する（`WorkingTreeService.runGit` と同じ） |
| `SimulatorHub` | 同上。**所有は `PhloxApp` の `@State`**（`TerminalPanelSession` と同じ。ウィンドウごとの `@State` にするとウィンドウ数だけ取得が増え FR-7 が崩れる） | XPC 接続（接続世代）の所有者。UDID ごとの取得セッションを、**開いているタブの数ではなく見えている表示の数**で管理し、0 になったら detach（NFR-3）。切断時の 1 回だけの再接続（NFR-2）。タブを閉じる・セッション削除は端末の停止と切り離す |
| `SimulatorScreenView` | 同上 | `NSViewRepresentable`。`layer.contents = IOSurface`。`NSView.displayLink`（macOS 14+）で seed を確認し、変わったときだけ再設定。古い接続世代・表示世代の通知は捨てる |
| `SimulatorTabView` | 同上 | 帯（端末選択・起動・ホーム・スクショ・停止・状態・診断）＋画面。空状態・非対応表示（FR-8） |

- **セッションとの関係**: 端末はアプリ全体の資源で、セッションは「その端末を見る・操作する窓」。子タブはセッションごとにあり、
  各タブがどの端末を見ているかは `SimulatorHub` がセッション別に記憶する（UDID はタブに持たせない）。

**座標変換 `SimulatorInputMapper`（純関数）**: ビュー上の点（AppKit は左下原点。上下を明示的に反転）→ 縦横比を保った表示矩形（余白を除く）→
0〜1 の正規化座標。向きは `SimulatorDisplayInfo` の 4 方向（縦・逆さ縦・左横・右横）を使い、surface が回転済みかどうかも補助側が返す。
2026-10-08にXcode26.2／iOS26.2で横画面が縦枠内に表示される不具合を確認した。表示ポートの `screenProperties.uiOrientation` は0で、実画面が回転しても向き通知が届かないため、自動取得案は採用しない。ユーザー承認により、Phloxの「表示を回転」ボタンで表示方向を90度ずつ指定する。これはPhlox内の表示操作であり、端末の姿勢やSimulator.app側の回転操作には自動追従しない。端末を回転させるにはSimulator.appを使い、Phloxの表示方向を合わせる。
補助側のportraitは未回転surfaceの座標軸を表し、ゲストUIの向きを検出した値ではない。指定方向はタブの接続が所有し、端末変更・再接続で縦向きに戻る。本体は未回転surfaceを指定方向に回転し、横向きでは表示寸法を入れ替える。描画と入力は同じ表示寸法を使い、スクロール差分も縦向き端末座標へ変換する。接触中の向き変更では古い接触・キーを解放する。
非公開APIの参考実装は [deviceterm の検証記録](https://github.com/sethdeckard/deviceterm/blob/main/Sources/CoreSimulatorBridge/as-tested.md)（SimScreen / SimScreenProperties）。採用対象のXcode 17C52での実検証は本リポジトリの配布記録に残す。
XPCのエラー・切断・応答のコールバックは配送キューで受ける `@Sendable` クロージャーとし、UIの状態変更だけをMainActorへ送る。MainActor内で作成した通常クロージャーは、内部にTaskを書いても入口の実行時検査でクラッシュするため使わない。存在しないXPCサービスへの実接続でエラー通知の回帰を検査する。
正規化座標からデバイスの座標（ポイント・倍率）への変換は補助プロセス側の 1 か所だけで行う（idb #964 の倍率ずれを繰り返さないため）。
余白部分のクリックは送らない。

**キー入力**: `SimulatorScreenView` が first responder のときだけ、`keyDown`/`keyUp`/`flagsChanged` のキーコードと修飾キーを送る。
`NSTextInputClient` は実装しない（Mac 側の変換を通さない）。⌘ 付きのキーは Phlox のショートカットとして扱い送らない。
例外は ⌘V（FR-5 の貼り付け）。**除外の規則は新しい押下にだけ適用する**: 送信済みの押下に対応する解放は、その後に修飾キーが変わっても必ず送る
（例: A を押す → ⌘ を押す → A を離す、で A の解放を送らないと端末側でキーが押されたままになる）。**⌃Tab / ⌃⇧Tab（子タブの巡回）も端末へ送らず Phlox で扱う**（⌘ を含まないため、規則を明示しないと端末へ流れる）。
**⌘Esc でキー入力を解除**し、フォーカスを帯へ戻す（Esc・Tab は端末へ送るので、これが無いとキーボードだけでは画面から抜けられない）。`resignFirstResponder`・端末切替・切断時は `releaseAll`（NFR-7）。

**アクセシビリティ**: 帯のボタンは操作可能。端末画面は画素（IOSurface）なので iOS 内の UI 要素を VoiceOver に公開できない。
第 1 版は「端末内 UI の VoiceOver 操作は非対応」と明記し、画面は「iPhone 17 の画面」のようなラベルの単一要素とする（対応済みとは扱わない）。

### 3.5 子タブと永続化

- `ChildTab` に `case simulator` を足す。
- **`.simulator` は永続化しない**。理由: 保存形式は `try? JSONDecoder().decode(SessionTabsSnapshot.self, ...)`（`Tabs/SessionTabs.swift:231`）で読まれ、
  旧バージョンは未知の case を含むデータの読み込みに失敗して**全セッションのタブ配置を失う**。
- **実行中の配置は書き換えず、保存用のコピーだけを正規化する**（`SessionTabStore` の保存処理）:
  - `tabs` から `.simulator` を除く。
  - `left == .simulator` なら、`right` が残っていれば `right` を `left` に昇格して `right = nil`、無ければ `.conversation`。
  - `right == .simulator` なら `right = nil`。`right == nil` になったら `focusesRight = false`。
- 既存の case の符号化結果は変わらない（合成 Codable は case ごとにキーを持つ）。再起動後にシミュレーターのタブは復元されない。

### 3.6 ショートカット

| 操作 | キー | 備考 |
|---|---|---|
| シミュレーターのタブを開く | ⌃⌘Y | ⌃⌘T（ターミナル）・⌃⌘E（変更）と同じ並び。2026-10-02 時点で `App/`・`Packages/*/Sources` に割り当てなし |
| ホーム | ⇧⌘H（タブにフォーカスがあるときのみ） | Simulator.app と同じキー。2026-10-02 時点で割り当てなし |

### 3.7 実行記録（互換性の証拠）

端末を使う結合テストは CI で実行できないため手動で行い、毎回次を記録する（`macos/docs/operations/` に手順と記録表を置く）:
アプリ／補助プロセスの build・Xcode build・macOS・iOS runtime・端末と倍率・項目別の合否。
項目: 連続表示・タップ・ドラッグ・スクロール・キー（英字・修飾キー）・iOS 側での日本語入力・貼り付け・ホーム・4 方向の向きでの四隅タップ、
異常系として補助プロセスの終了・応答期限切れ・タブ非表示・再接続・Release/Debug の同時起動。
Simulator.app で同じ端末を開いた状態で、両方に表示され両方から操作できること（FR-9）。補助プロセスの終了・期限切れの間も、本体のチャットセッションとターミナルが操作できること（NFR-1）。
入力の成否は、**入力結果を観測できる専用テストアプリ**（カウンター・文字欄）で確かめる。端末は専用に作成したもの（`simctl create`）を使い、
ユーザーが使用中の端末は使わない。§3.3 の許可リストへの追加条件はこの記録の合格とする（初回の組の例外は §3.3）。

### 3.8 UI の細部（Claude Design のモックで確定。2026-10-02）

> 見た目と文言は見本を正とする。この節は見本では表せない挙動だけを書く。見本との食い違いの判断・記録は `delivery/0039-design-alignment-worklog.md` に残す。端末名の省略は帯の最終的な縮退に限る。

見た目の正本は `specs/ClaudeDesign/7 Simulator Tab.dc.html`（同じフォルダの `support.js` と一緒にブラウザで開く）。挙動に関わるものだけを書く。

- ⌃⌘Y で開いた直後のフォーカスは帯の端末メニューに置く（画面にフォーカスを置かない。ユーザーの操作なしに端末へキーを送らないため。NFR-6）。
- 画面の下に操作の手がかりを 1 行出す。キー入力を送っていない間は「キー入力はまだ送っていません」、送っている間は帯に accent の枠付きの印「キー入力を端末に送信中」を出し、下の 1 行に「⌘ 付きのキーは Phlox が受けます · ⌘Esc で解除」を出す（見本 7b。2026-10-03 見本に合わせて改訂）。画面が無い状態（停止中・起動中・非対応）では下の 1 行を出さない。iPad でも同じ文言（「iPhone」と書かない）。
- 端末画面の読み上げ: 役割は画像ではなくキー入力を受け取る要素（`application` 相当）、ラベルは「<端末名> の画面。端末内の UI は VoiceOver で操作できません」。VoiceOver が有効なときは手がかりの文言をそれ向けに差し替える。
- 「未確認でも試す」を押したタブには、帯に「未確認の組み合わせで実行中（このタブのみ）」を出し続ける。
- 診断（NFR-4）の文言は「しばらく画面の更新を観測していません」。色を付けない控えめな表示で、補足説明はキーボードで選べる ⓘ ボタンから開く（ホバーだけに頼らない）。しきい値は 5 秒（補足説明にも時間の長さは出さない。見本 7i）。帯の中に出す。
- Xcode が見つからないときは「再確認」ボタンを置く（Xcode を導入した後にアプリを再起動せず確かめ直すため）。
- 通信仕様の版が合わないとき（アプリの再起動が必要）は、表示で案内するだけで「再起動」ボタンは置かない（終了時の未保存確認を飛ばさないため、終了はユーザーに任せる）。
- 停止の確認ダイアログ: キャンセルが既定。題は「<端末名> を停止しますか？」、「停止」は破壊的な操作の見た目で ⌘⌫ を割り当てる。Phlox が自分で分かる「Phlox で表示中のタブ」（例: この Phlox の 2 タブ）と「停止したあとは、帯の『起動』で起動し直せます。」を添える（見本 7e。2026-10-03 改訂）。本文は「この端末を表示中の他のタブ・Phlox の別の版・Simulator.app にも影響します」とし、他の版が表示中かどうかや、データが消えないことは断定しない（Phlox からは分からないため）。アイコンは Phlox のアプリアイコン（注意の色は使わない）。確認を表示している間は帯の停止ボタンを押された見た目にする。
- 停止とスクリーンショットは、メッセージ表示中も端末が起動していれば押せる（`simctl` で実行するため補助プロセスの状態に依存しない）。
- 端末が無いときの帯は「端末なし」（OS の表示を残さない）。
- 「エージェントに伝える」（FR-10）: 帯の右側のボタンの先頭（ホームの左）に吹き出しの印のボタンを置く（見本 7s）。端末が無いときは押せない。端末を選んでいれば、停止中でも押せる（起動はエージェントに任せられるため）。入れ先はセッションの種類で分ける。チャット型は入力欄の下書きの末尾に足し（空でなければ改行して足す）、入力欄にフォーカスとキャレットを移す（単一表示で入力欄がまだ作られていなくても、作られたときに移す）。送信の受付待ちの間は入れない（入力欄と同じく、失敗時に戻す本文とぶつけないため）。ターミナル型は、CLI の入力のカーソル位置に文字だけを書き込み、Enter は送らない（文は 1 行で、端末名の改行などの制御文字は除くので送信されない）。待機中・実行中のときだけ入れる（許可や質問の回答待ちでは、文の数字や英字が選択肢のキーとして効いてしまうため。未起動も入れない）。入れられないときは警告音を鳴らし、タブも切り替えない。入れたら会話のタブを前に出す。分割で会話が出ていればその区画へ移り、出ていなければシミュレーターでない方の区画に出す（端末の画面を残す）。状態（起動済み等）は文に入れない（送るまでに変わりうるため）。
- 帯の右側の操作ボタン（エージェントに伝える・ホーム・スクリーンショット・停止）は、ホバーで角丸の面を出し、0.4 秒とどまると何をするボタンかの説明をボタンの下に吹き出しで出す（見本 7s。2026-10-06 追加）。OS 標準のツールチップより早く出すため、見本の吹き出しを自前で描く（読み上げには同じ文言をヒントとして渡す）。説明の文言は「表示中の端末をエージェントの入力欄に入れる」「ホーム画面に戻る ⇧⌘H」「スクリーンショットを撮って Finder で表示」「端末を停止」。押せない状態でも説明は出す。
- 帯の縮退は状態ではなく必要幅で決める。まず状態・入力中・未確認・診断の文言を短くし、次に iOS の版を隠す。それでも収まらなければ状態の文言を印だけにする。端末名は、他の文言・版・状態をすべて縮めても収まらないときだけ、末尾を省略する。全文は読み上げとツールチップに残す。状態の印・メニュー・起動・操作ボタンは残す。

## 4. 既存機能との互換性

| 既存機能 | 影響 |
|---|---|
| 子タブ（会話・ターミナル・変更・ファイル）・分割・⌃Tab 巡回 | 不変。`.simulator` が 1 種増えるだけ |
| タブの永続化 `phlox.sessionTabs.v1` | 形式不変（`.simulator` は保存用コピーから除く）。旧バージョンへ戻しても読める |
| 本体の署名・エンタイトルメント・公証手順 | 本体のエンタイトルメントは不変。XPC サービスの署名が増える（リリース手順 `operations/site-deploy-and-release.md` に追記が必要） |
| Release／Debug の同時起動（ADR 0034） | 補助プロセスも flavor ごとに分かれる。ただし iOS 端末は共有（一方の停止は他方にも及ぶ） |
| アプリ終了処理 | 本体終了時に接続を invalidate する。起動した端末は停止しない |
| Xcode 未導入の Mac | 「Xcode が見つかりません」を表示。他機能は影響なし |
| Simulator.app・Xcode・他ツールでの同端末利用 | 共存（FR-9）。Xcode 27 の構成は未確認（§3.3） |

## 5. テスト計画

| テスト（新規） | 固定する性質 |
|---|---|
| `SimulatorInputMapperTests` | 余白を除いた正規化／余白クリックは送らない／上下反転／4 方向それぞれの四隅／境界（0・1） |
| `SimulatorCatalogTests` | `simctl list -j` の出力（実データを fixture 化）から端末一覧・起動状態・並び順／壊れた JSON で空一覧＋理由 |
| `SimulatorPolicyTests` | 許可リストの「表示のみ対応」で入力を送らない／「未確認でも試す」はそのタブだけに効き、部品の読み込み失敗・版の不一致は解除しない／⌃⌘Y で開いても端末を起動せず、画面にフォーカスを置かない（NFR-6） |
| `SimulatorHubTests`（XPC は自前プロトコルの fake で置換） | 補助プロセスの終了・期限切れの後も本体のセッション・ターミナルが操作を続けられる（NFR-1）／可視表示 0 で detach／複数ウィンドウ・タブで取得 1 本／切断時に 1 回だけ再接続／期限切れ後の遅延応答を接続世代で捨てる／版の不一致で attach しない |
| `SimulatorKeyRoutingTests`（純関数に切り出す） | `A を押す→⌘ を押す→A を離す` で A の解放を送る／⌘ 付きの新しい押下は送らない・⌘V は pbcopy 成功時だけ送る・⌃Tab/⌃⇧Tab は送らない・⌘Esc で解除・修飾キーなしの Esc/Tab は送る |
| `SimulatorInputReleaseTests` | フォーカス喪失・端末切替・切断で `releaseAll`／再接続後に古い入力を再送しない |
| `SessionTabsTests` への追加（凍結ファイルでなければ） | 保存用コピーの正規化 4 パターン（left/right × simulator）／実行中の配置は変わらない／保存データを `.simulator` を知らない旧型でデコードできる |
| 実行記録（§3.7、手動） | 互換性の証拠 |
| `SimulatorAgentHintTests`（DashboardFeature）・`AppendToDraftTests`（SessionFeature）・`SessionTabLayoutTests` への追加 | 端末から作る文（名前・iOS の版・UDID。状態と制御文字は入れない）／下書きへの足し方（空・改行で終わる・それ以外）・送信の受付待ちは入れない・作られる前に出た未処理のフォーカス要求だけを入力欄が作られたときに適用する／会話を前に出すときに分割中は端末の画面を残す |
| XCUITest | ⌃⌘Y でタブが出る（非対応時の表示は、画面に出さない描画の単体テスト `SimulatorTabPresentationTests` の 5 状態で代える。補助プロセスの応答を差し替える仕組みを Release に持ち込まないため。2026-10-03 PM 判断） |

検証コマンド: `swift test --package-path macos/Packages/SimulatorBridgeKit`・`.../DashboardFeature`（全数）、`xcodebuild build`、
`test_signing_entitlements_variants.sh`（無改変のまま）と XPC 用の署名検査（新規）、§7 の関門。

## 6. スコープ外（第 1 版でやらないこと）

| 項目 | 理由・足すときの道筋 |
|---|---|
| 公開 API だけの方式（ScreenCaptureKit で Simulator.app のウィンドウを撮影＋CGEvent で操作） | 画面収録とアクセシビリティの 2 つの許可が要り、Simulator.app のウィンドウを画面上に出したままにする必要があり、操作の位置合わせも不安定。2 方式を並行保守しない。非公開方式が恒久的に使えなくなった場合の代替として ADR に残す |
| `simctl io recordVideo` の配信 | 操作の経路が無く、エンコード遅延がある |
| Mac 側の日本語変換を通した文字入力 | 物理キー方式に絞る（FR-5）。必要なら `NSTextInputClient` で確定文字列を受け、`simctl pbcopy` 経由で貼り付ける方式を検討 |
| マルチタッチ・端末の回転操作・音量/サイドボタン | Indigo の該当関数は存在を確認済み（§1.1） |
| 端末内 UI の VoiceOver 操作 | 画面が画素のため（§3.4） |
| ビルド＆実行・アプリの自動インストール | 依頼外。`simctl install`/`launch` で後から足せる |
| エージェントからのシミュレーター操作（Control API） | 依頼外。エージェントへ端末を伝えるのは、帯のボタンで入力欄に文を入れる方式（FR-10）に限る。エージェントが Phlox に表示中の端末を問い合わせる仕組みは、必要になったら足す |
| 実機（USB 接続の iPhone）・iOS 版 Phlox からの表示 | 対象外 |

## 7. 実装順と関門（各段で既存テスト全数 green）

ファイルツリー側の設計書（`file-explorer-and-markdown-editing.md`）とは独立に進め、関門で不成立ならこちらだけ中止する。

1. **関門**: 公証済みのアプリに最小の XPC サービスを入れ、専用端末と専用テストアプリに対して
   **連続表示・タップ・ドラッグ・キー入力・ホーム**が §3.7 の方法で確認できること。あわせて §1.3 の仮説
   （surface が更新され続けるか・交代するか・XPC の通信量・`layer.contents` の再設定で表示が更新されるか）を、
   連続アニメーション中の surface ID・seed・表示結果で観測する。
   読み込めなければ補助プロセスへの `disable-library-validation` 付与を検討し、それでも駄目なら本機能を中止して報告する。
2. `SimulatorBridgeKit`（プロトコル・表示情報・`SimulatorInputMapper`）＋テスト
3. `SimulatorCatalog`（`simctl`）＋テスト
4. 補助プロセス: 画面取得 → 本体 `SimulatorScreenView` 表示（操作なし）
5. 補助プロセス: タップ・スワイプ・スクロール・キー・ホーム・`releaseAll`
6. `SimulatorHub`（PhloxApp 所有）・`SimulatorTabView`・`ChildTab.simulator`（保存用コピーの正規化）・⌃⌘Y ＋テスト・XCUITest
7. 許可リスト・非対応表示・版確認・再接続・診断。署名検査スクリプトとリリース手順・実行記録の手順書
8. 実画面確認（Debug 版を別インスタンスで起動。稼働中のリリース版は終了させない）→ ADR 起票 → `architecture/` へ蒸留

## 8. 設計判断（着手時に ADR 化する）

1. **非公開部品（CoreSimulator / SimulatorKit）を使う**: 画面内表示の公開手段が無く、既存ツールも全てこの方式。代償は Xcode 更新での破損リスクで、
   組単位の許可リスト・実行記録・欠落シンボルの検出で扱う。
2. **XPC サービスに隔離する**（本体への直接読み込みは棄却）: 本体は作業中のエージェントセッションを抱えており、非公開 API の不具合で落としてはならない。
3. **SimulatorKit の `SimDisplayView` 等を本体に埋め込む方式は棄却**: Swift 製で外部から安定して構成できず、本体への読み込みも必要になる。
4. **子タブに置く**（インスペクタは棄却）: インスペクタは最大 340pt で端末画面には狭い。子タブなら分割で Xcode のプレビュー配置を再現できる。
5. **`.simulator` タブは永続化しない**: 旧バージョンが未知の case で全タブ配置を失うのを避ける。
6. **入力の成否を画面更新で判定しない**: 入力が無視されてもアニメーションで画面は変わり、正常なタップでも変わらないことがあるため（レビューで判明）。
7. **キー入力は物理キー方式**: Mac 側の変換を通すには確定文字列を送る別経路が要り、第 1 版の範囲を超える。
