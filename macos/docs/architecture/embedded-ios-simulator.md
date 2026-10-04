---
status: active
last-verified: 2026-10-04
---

# ウィンドウ内 iOS シミュレーターの現行構成

> **このファイルの役割**: 子タブ「シミュレーター」の構成要素・データの流れ・補助プロセス（XPC サービス）との通信・状態・制約の**現行構造**。
> コード（`macos/Packages/SimulatorBridgeKit`、`macos/Packages/DashboardFeature/Sources/DashboardFeature/Simulator`、`macos/SimulatorBridgeService`）で確かめた事実だけを書く。
> **書かないもの**: なぜ非公開部品を XPC サービスに隔離したか・永続化しない理由など（→ [ADR 0179](../adr/0179-embedded-ios-simulator-via-xpc-and-private-frameworks.md)。状態は accepted）、
> 満たすべき要件（→ [specs/embedded-ios-simulator.md](../specs/embedded-ios-simulator.md)）、互換性の実行記録（→ [operations/simulator-compatibility-verification.md](../operations/simulator-compatibility-verification.md)）。

## 全体像

```
Phlox.app（本体。CoreSimulator / SimulatorKit を読み込まない）
 ├─ SimulatorTabView（ChildTab.simulator）── SimulatorTabContent（帯・状態・案内）── SimulatorScreenView / SimulatorScreenNSView（layer.contents = IOSurface、CADisplayLink で seed 確認）
 │         │ タップ・スクロール・キー（正規化座標・キーコード）
 │         ▼
 ├─ SimulatorHub（PhloxApp の @State。アプリで 1 つ）── 端末ごとに SimulatorDisplayConnection ── SimulatorXPCTransport（NSXPCConnection）
 │         └─ SimulatorCatalog ── /usr/bin/xcrun simctl（一覧・起動・停止・スクリーンショット・pbcopy）
 │                                     │ NSXPCConnection(serviceName: <本体の bundle ID>.SimulatorBridge)
 │                                     ▼
 └─ Contents/XPCServices/SimulatorBridgeService.xpc ── SimulatorBridgeService（main.swift）── PrivateSimulatorAPI（Objective-C）
          ├─ CoreSimulator / SimulatorKit を実行時に dlopen、シンボルは NSClassFromString・NSProtocolFromString・dlsym で解決
          ├─ 画面: SimDevice の io ポート → descriptor の framebufferSurface とコールバック → IOSurface を本体へ
          └─ 入力: Indigo HID メッセージ（関数を dlsym）→ SimDeviceLegacyHIDClient で送信
共有の型・プロトコル・座標変換・キー配送の純関数: パッケージ SimulatorBridgeKit（依存なし）
```

## パッケージと配置

| 場所 | 内容 |
|---|---|
| `macos/Packages/SimulatorBridgeKit` | `SimulatorBridgeProtocol`・`SimulatorBridgeClientProtocol`・`SimulatorBridgeInterfaces`（`NSXPCInterface` の設定・通信仕様の版・期限）・`SimulatorConnectionGeneration`・`SimulatorBridgeCapability`・`SimulatorDisplayInfo`・`SimulatorOrientation`・`SimulatorInputMapper`・`SimulatorKeyRouting` |
| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Simulator/` | `SimulatorTabView`（`SimulatorDeviceMenu`・`SimulatorDevicePopUpButton`・`SimulatorWindowVisibility` を含む）・`SimulatorTabContent`・`SimulatorScreenView`・`SimulatorHub`・`SimulatorDisplayConnection`・`SimulatorPolicy`・`SimulatorCatalog` |
| `macos/SimulatorBridgeService/` | `main.swift`（XPC のエントリ・`SimulatorBridgeService`）・`PrivateSimulatorAPI.h/.m`（非公開 API の呼び出しをこの 1 組に集約）・`Info.plist`・`SimulatorBridgeService.entitlements`（中身は空の dict） |
| `macos/project.yml` | ターゲット `SimulatorBridgeService`（`type: xpc-service`、`ENABLE_HARDENED_RUNTIME: YES`、ブリッジングヘッダー `PrivateSimulatorAPI.h`）。`Phlox` ターゲットの依存に `embed: true` で入る。bundle ID は Release が `com.phlox.Phlox.SimulatorBridge`、Debug が `com.phlox.Phlox.debug.SimulatorBridge` |
| `macos/scripts/tests/test_simulator_bridge_signing.sh` | 生成済みアプリの XPC 同梱・署名・権限・本体への非公開リンク混入の検査 |

## 通信の契約（`SimulatorBridgeKit`）

- 通信仕様の版 `SimulatorBridgeInterfaces.protocolVersion = 2`。期限 `replyTimeout = 5` 秒。
- `SimulatorBridgeProtocol`（本体 → 補助）: `probe(reply:)`・`attach(udid:generation:reply:)`・`detach(udid:)`・`sendTouch(udid:phase:x:y:)`・`sendScroll(udid:dx:dy:x:y:phase:)`・`sendKey(udid:keyCode:modifiers:down:)`・`sendButton(udid:button:)`・`releaseAll(udid:)`。
  `sendTouch` の phase は 0 = 開始、1 = 移動、2 = 終了。`sendScroll` の phase は 0 = ホイール、1 = 開始、2 = 継続、3 = 終了、4 = 取消。座標は 0〜1 の正規化座標。
- `SimulatorBridgeClientProtocol`（補助 → 本体）: `surfaceChanged(_:)`。
- `SimulatorBridgeCapability`（`NSSecureCoding`）: `protocolVersion`・`helperBuild`・`xcodeBuild`・`coreSimulatorLoaded`・`simulatorKitLoaded`・`reason`。
- `SimulatorDisplayInfo`（`NSSecureCoding`）: `udid`・`connectionGeneration`・`displayGeneration`・`surface`（`IOSurface`）・`pixelWidth`・`pixelHeight`・`orientation`・`surfaceIsRotated`・`pixelFormat`。`NSXPCInterface` に許可クラスを明示する（`SimulatorBridgeAllowedClassesTests`）。補助プロセスは現在、`orientation = .portrait`・`surfaceIsRotated = false` を固定で返す（4 方向への座標変換は `SimulatorInputMapper` 側にあるが、補助側は向きを検出して渡していない）。
- `SimulatorConnectionGeneration`: 接続（切断・再接続）ごとに `advance()`。`SimulatorDisplayInfo.isCurrent(udid:connectionGeneration:minimumDisplayGeneration:)` と合わせ、古い接続世代・表示世代の応答を捨てる。

## 補助プロセス（`SimulatorBridgeService`）

- `NSXPCListener.service()` で待ち受け、新しい接続ごとに `SimulatorBridgeService` を生成して公開する。接続の切断・中断で `invalidate()`（全端末の取得を `detach`）。処理は 1 本の直列キュー（`com.phlox.simulator.display`）。
- `probe`: `PrivateSimulatorAPI.load()` を実行し、通信仕様の版・`CFBundleVersion`・Xcode の `ProductBuildVersion`（`xcode-select -p` の親の `version.plist`）・各部品の読み込み可否・理由を返す。
- `load()`: `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator` と `<xcode-select -p>/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit` を `dlopen`。`SimServiceContext`・プロトコル `SimDisplayIOSurfaceRenderable`・`SimulatorKit.SimDeviceLegacyHIDClient` の初期化・送信メソッド・`IndigoHIDMessageForMouseNSEvent`・`IndigoHIDMessageForKeyboardArbitrary`・`IndigoHIDMessageForButton`・`hidUsageForCGKeyCode` の存在を確認し、欠けていれば `reason` を設定して以降使わない。
- `attach(udid:generation:)`: 端末が起動中（state 3）であること、画面倍率（`deviceType.mainScreenScale`）が正であること、HID クライアントを作れることを確かめ、`io` の各ポートの descriptor へ画面コールバックを登録する。保持している IOSurface のうち**面積が最大のもの**を公開し、IOSurface の ID が変わったときだけ通知する。最初の公開は `attach` の応答、以後は `surfaceChanged`。端末ごとに `displayGeneration` を 1 ずつ進める。`attach` の前に同じ端末の既存の取得を `detach` する。
- 入力（`PrivateSimulatorAPI`）:
  - タッチ: 開始・移動を押下（Down）、終了を Up として送る。座標が 0〜1 外・状態不整合は破棄してログのみ。
  - スクロール: 10pt に達するまで接触せず合算し、接触点は端の 44pt 内側（小画面は寸法の 1/4 まで）へ寄せる。ホイールは 20 ms 刻みで最小 4 ステップ（距離 5pt ごと）、スクロール終了時は 40 ms 刻みの 6 ステップで減速して離す。
  - キー: キーコード 127 以下を `hidUsageForCGKeyCode` で HID 用途へ変換して押下・解放を送る。押下時に修飾キーの状態が合わなければ左修飾キーを合成して補う。
  - ホーム: 押下を送り、100 ms 後に解放。押下中の再要求は破棄。
  - `releaseAll`: スクロール取消・継続中の接触の終了・押下中キーの解放・ホームの解放。`detach` でも呼ぶ。
- すべての非公開 API 呼び出しは `@try`/`@catch` と `respondsToSelector` で守り、失敗は理由つきのエラー（`NSError` ドメイン `Phlox.SimulatorBridge`）で返す。

## 本体側

**`SimulatorHub`**（`@MainActor @Observable`。`PhloxApp` の `@State simulatorHub` が所有し、`DashboardView` → `SessionTabsContainer` → `SimulatorTabView` へ渡す）

- 端末一覧 `devices`・`listingReason`・`operationReason`、セッションごとの選択端末 `selections`、表示 ID（`SimulatorTabView` ごとの UUID）→ セッションの `visibleDisplays`、セッション単位の「未確認でも試す」`unverifiedSessions`（セッション ID → 端末 UDID。永続化しない）。
- `setVisible(_:displayID:sessionID:)`: 見えている表示の増減を受け、`reconcileConnections()` で「見えている表示が選択している起動中の端末」の集合に合わせて `SimulatorDisplayConnection` を作成・破棄する（既に接続がある端末は共有）。表示が 1 つも無くなると端末一覧の更新タスクを止める。見えている間は 2 秒ごとに `SimulatorCatalog.list()` を呼ぶ（`refreshInterval`）。
- `boot(for:)`・`shutdown(udid:)`・`screenshot(for:destination:)` は `SimulatorCatalog` 経由。端末の起動・停止は、ユーザー操作（帯の「起動」「停止」）以外では行わない。
- `removeSession`: 子タブを閉じたとき・セッション削除時に呼ぶ。`disconnectAll()`: `NSApplication.willTerminateNotification` で呼ぶ（接続を切るだけで端末は停止しない）。

**`SimulatorDisplayConnection`**（端末ごと。`SimulatorDisplayTransport` プロトコルの背後に `SimulatorXPCTransport`（`NSXPCConnection(serviceName:)`）を持ち、テストでは差し替える）

1. `attach(udid:)` → `start`: 既存接続を `disconnect`（世代を進める）→ 新しい transport を作り `resume`。
2. `probe`（期限 5 秒）。通信仕様の版が本体と違えば「通信仕様の版が異なります。アプリを再起動してください」で失敗（再試行不可）。`coreSimulatorLoaded`・`simulatorKitLoaded` が偽または `reason` があれば、その理由で失敗（再試行不可）。
3. `SimulatorPolicy.support(xcodeBuild:runtimeIdentifier:triesUnverified:)` で対応可否を決める。表示不可なら切断して理由（「未確認の組み合わせです」）を出す。
4. `attach`（期限 5 秒）の応答と `surfaceChanged` は、同じ世代検査 `receive(_:)` を通って `displayInfo` を更新する。
5. 期限切れ・`NSXPCConnection` の中断・切断・不正な表示情報は `fail` → 切断し、`reason` を設定して再接続ボタンを許可する。**自動再接続**は、失敗の連鎖ごとに 1 回（表示情報を受け取れたら解除）、かつ 60 秒間に 3 回まで（`SimulatorHub` が接続ごとに `automaticallyReconnects = true`）。再試行不可の失敗は自動・手動とも再接続しない。
6. 入力 `sendTouch`・`sendScroll`・`sendKey`・`sendHome` は、`inputEnabled`（対応状態が入力可 かつ `displayInfo` あり）のときだけ transport へ送る。送信済みの押下キーを `sentKeyCodes` に保持し、`releaseAll()` で `inputRevision` を進めて transport の `releaseAll` を呼ぶ。切断時にも `releaseAll`。
7. 画面更新の観測: `observeFrame` が IOSurface の ID と seed の変化時刻を記録し、5 秒以上変化がなければ `hasStaleFrame`（診断表示用。入力の成否判定ではない）。

**`SimulatorPolicy`**: 許可リスト（`verified`）は **Xcode build `17C52` × `com.apple.CoreSimulator.SimRuntime.iOS-26-2` の 1 組だけ**（`supportsInput: true`）。結果は `unsupported` / `displayOnly` / `supported` / `unverified`。範囲指定や永続化した例外は持たない。表示可否は `unsupported` 以外、入力可否は `supported` と `unverified`。「未確認でも試す」で `unverified` になれるのは許可リスト外の組だけで、部品の読み込み失敗・通信仕様の版不一致は解除しない。

**`SimulatorCatalog`**（`/usr/bin/xcrun simctl` を `Process` で実行。標準出力と標準エラーを並行して読む）

- `list -j devices`: ランタイムが `com.apple.CoreSimulator.SimRuntime.iOS-` で始まり `isAvailable` の端末だけ。並びは起動中を先頭に、名前・ランタイム・UDID の順。壊れた JSON・取得失敗は空の一覧と理由。実行失敗後に `xcrun --find simctl` の終了コードと出力先の実行可否で Xcode 不在を判定し、`DEVELOPER_DIR` を尊重する。利用者向けの理由と元の `diagnosticReason` を分けて保持し、診断はツールチップから読めるようにする。
- `boot`・`shutdown`・`io <udid> screenshot <path>`・`pbcopy <udid>`（標準入力にテキスト）。
- 端末メニューでは選択中を先頭、ランタイムの版を数値の新しい順、名前を自然順に並べる（Catalog 自体の並びは変えない）。

**`SimulatorScreenView` / `SimulatorScreenNSView`**

- `CALayer`（`contentsGravity = .resizeAspect`）に `layer.contents = IOSurface` を設定する。更新通知のたびに `contents` を一度 `nil` にしてから再設定する。`CADisplayLink`（`NSView.displayLink(target:selector:)`、メインの run loop の common モード）が `IOSurfaceGetSeed` を確認し、変わったときだけ再設定する。非表示・最小化中は何もしない。
- 入力は、ウィンドウが key・最小化でない・自分が first responder・`inputEnabled` のとき（`acceptsInput`）だけ送る。`mouseDown` は表示矩形内でのみ開始し、`SimulatorInputMapper.normalizedPoint` で正規化する（AppKit の左下原点を上下反転、余白は送らない、継続中のドラッグは矩形の端へ寄せる、4 方向の変換は `orientation`・`surfaceIsRotated` に従う）。`scrollWheel` は慣性スクロール（momentum）を送らず、トラックパッドは 1 倍・マウス行単位は 10 倍で送る。
- キーは `NSTextInputClient` を実装せず、`keyDown`/`keyUp`/`flagsChanged`/`performKeyEquivalent` のキーコードと修飾キーを `SimulatorKeyRouting.route` で振り分ける。左右の修飾キーは device-dependent ビットで区別し、Caps Lock は切替ごとに押下・解放を 1 組送る。
- `SimulatorKeyRouting.Decision`: `send`（送信済みの押下に対応する解放・リピートは、後から修飾キーが変わっても必ず送る）／`handleInPhlox`（⌘ 付きの新規押下、⌃Tab・⌃⇧Tab、押下を伴わない未送信キーの解放）／`copyPasteboard`（⌘V の新規押下）／`releaseFocus`（⌘Esc）／`sendPressAndRelease`（pbcopy 成功後の ⌘V）。⌘V は `simctl pbcopy` 成功後にだけ ⌘V の押下と解放を送り、失敗時は端末へ送らず理由を保持する。
- first responder を失う・ウィンドウが key でなくなる・最小化・非表示・端末・接続世代の変更・`dismantleNSView` で、入力を持っていた場合に `releaseAll`。
- アクセシビリティ: 役割 `AXApplication`、識別子 `simulator-screen`、ラベル「<端末名> の画面。端末内の UI は VoiceOver で操作できません」。

**`SimulatorTabView` / `SimulatorTabContent`**（帯の高さ 30pt）

- 帯: 端末選択（`SimulatorDeviceMenu`、`SimulatorDevicePopUpButton`）・取得済みの版・状態・「起動」（停止中の端末）・ホーム・スクリーンショット・診断・停止。文言、版、状態の印、端末名の順に縮める。停止は確認ダイアログ（キャンセルが既定・停止は ⌘⌫）を経由し、スクリーンショットは `~/Pictures/Phlox Simulator/Simulator-<UUID>.png` へ保存して Finder で選択表示する。
- `SimulatorTabContent` が画面と状態別の題・説明・操作を表示する。一覧の取得失敗は「再確認」、停止中は「起動」、接続失敗または未確認の組み合わせは「Simulator.app で開く」と、許可されていれば「再接続」／「未確認でも試す」を出す。操作・撮影の失敗だけでは中央の外部起動ボタンを増やさない。外部起動は `com.apple.iphonesimulator` に `-CurrentDeviceUDID <udid>` を渡し、Simulator.app を前面へ出す。端末メニューの外部起動項目は別経路で、失敗をタブ内の `menuOperationReason` に保持する。
- 更新なしの診断は帯の ⓘ から説明を開く。操作・撮影の理由は、画面があるときは帯の下の行、画面がないときは中央の説明に出す。一覧の元の診断は help に保持する。画面があるときだけ下に操作の手がかりを 1 行出す（VoiceOver 有効時は別文言）。キー入力を送っている間は帯に「キー入力を端末に送信中」、下の案内に「⌘ 付きのキーは Phlox が受けます · ⌘Esc で解除」を出し、画面に枠線を出す。
- 表示の可視性: `SimulatorWindowVisibility` が、ウィンドウの表示・最小化・遮蔽・アプリの非表示を見て `hub.setVisible(...)` を呼ぶ。タブが消えると `removeDisplay`。
- ショートカット: ⌃⌘Y（`PhloxApp.swift` のメニュー項目「シミュレーターのタブ」。`router.openChildTab(.simulator)` ＋ `hub.requestMenuFocus`。開いた直後のフォーカスは端末メニュー）、⇧⌘H（タブがフォーカスされていて入力可のときだけ有効なホーム）。
- 識別子: `simulator-tab`・`simulator-device-menu`・`simulator-boot`・`simulator-home`・`simulator-shutdown`・`simulator-diagnostics`・`simulator-support-band`・`simulator-try-unverified`・`simulator-open-external`・`simulator-reconnect`・`simulator-screen`。

## 子タブと永続化

- `ChildTab.simulator`（`Tabs/SessionTabs.swift`）。`SessionTabsContainer` の `.simulator` 分岐が `SimulatorTabView` を出す。
- 保存（`SessionTabStore`）では、`persistenceCopy` で作った保存用コピーだけを書き、実行中の配置は変えない: `tabs` から `.simulator` を除く／`right == .simulator` なら `right = nil`／`left == .simulator` なら `right`（無ければ `.conversation`）を `left` に昇格して `right = nil`／`right == nil` なら `focusesRight = false`。再起動後にシミュレーターのタブは復元されない。

## 制約（コードで確かめた値）

| 項目 | 値・挙動 | 場所 |
|---|---|---|
| 通信仕様の版 | 2 | `SimulatorBridgeInterfaces.protocolVersion` |
| `probe`・`attach` の応答期限 | 5 秒（タッチ等には期限なし） | `SimulatorBridgeInterfaces.replyTimeout` |
| 自動再接続 | 失敗の連鎖ごとに 1 回、60 秒に 3 回まで | `SimulatorDisplayConnection.fail` |
| 画面更新の診断 | 5 秒間 seed が変わらない | `SimulatorDisplayConnection.hasStaleFrame` |
| 端末一覧の更新間隔 | 見えている間 2 秒 | `SimulatorHub.refreshInterval` |
| 許可リスト | Xcode `17C52` × iOS runtime `iOS-26-2` の 1 組（表示・入力とも対応） | `SimulatorPolicy.verified` |
| 対象の端末 | iOS ランタイムの利用可能な端末のみ | `SimulatorCatalog.parse` |
| 対応する入力 | タップ・ドラッグ・スクロール・物理キー・ホームのみ。マルチタッチ・回転操作・音量/サイドボタン・Mac 側の日本語変換は無い | `PrivateSimulatorAPI`・`SimulatorScreenView` |
| 向き | 補助プロセスは縦向き固定の値を返す | `main.swift` の `SimulatorDisplayInfo` 生成 |
| 非公開部品 | 本体には読み込まない。補助プロセスだけが `dlopen` | `PrivateSimulatorAPI.m` |
| 検証状況 | 公証済みビルド・日本語入力・4 方向・実接続の異常系は未検証 | [simulator-compatibility-verification.md](../operations/simulator-compatibility-verification.md)・[delivery/0038](../delivery/0038-file-explorer-and-simulator-worklog.md) |

## テスト

| ファイル | 固定している性質 |
|---|---|
| `SimulatorBridgeKit/Tests`: `SimulatorInputMapperTests`・`SimulatorKeyRoutingTests`・`SimulatorBridgeAllowedClassesTests`・`SimulatorBridgeContractTests` | 座標変換・キー配送・XPC の許可クラスと契約 |
| `DashboardFeature/Tests`: `SimulatorCatalogTests`・`SimulatorPolicyTests`・`SimulatorHubTests`・`SimulatorDisplayConnectionTests`・`SimulatorInputDeliveryTests`・`SimulatorTabPresentationTests` | 端末一覧・許可リスト・Hub と接続の挙動（transport は fake）・入力の配送・非対応表示（画面外描画） |
| `DashboardFeature/Tests`: `SessionTabsPersistenceTests` | 保存用コピーの正規化 |
| `macos/scripts/tests`: `test_simulator_bridge_signing.sh`・`test_simulator_bridge_regressions.py`・`test_simulator_allowlist.py`・`test_simulator_initialization.py`・`simulator-bridge-test-gate.test.sh` | XPC の同梱・署名・本体への非公開部品の混入検出、公開前の Xcode build 照合、通常起動と検証入口で初期化を共有する配線 |
| `macos/PhloxUITests/SimulatorTabUITests`（XCUITest） | ⌃⌘Y でタブが開く（端末メニューにフォーカス・重複しない）・＋メニューから開いて会話へ戻れる・分割と解除 |
