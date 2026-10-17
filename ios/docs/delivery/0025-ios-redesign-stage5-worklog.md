---
status: complete
last-verified: 2026-10-18
---

# 0025: iOS 再設計 段階 5 — 新規チャット画面（作業記録）

> **このファイルの役割**: 計画書 [0020](0020-ios-redesign-plan.md) の段階 5 で行った、新規チャット画面の変更と確認結果を記録する。
> **書かないもの**: 恒久仕様（→ [仕様書](../specs/redesign-2026-10.md)）、API の契約（→ [mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md)）。

## 1. 変更

- `NewChatView`・`NewChatViewModel` を追加し、`Route.newChat(SessionComposeDraft)` の専用画面へ切り替えた。見出しは Mac の 10 種から開くたびに選び、描画では固定できる。Mac と同じ 5 つの提案文をチップに出し、押すと本文末尾へ追加してカーソルとフォーカスを戻す。
- プロジェクトは `/projects` の全件から選び、下部入口では前回値、プロジェクトの「＋」入口では指定値を初期選択する。前回のものが消えたときは未選択。古い Mac ではセッション一覧から候補を作り、表示名を project ID として送らない。未選択時は「プロジェクトを選んでください」で止める。
- 3 エージェントのモデルを一枚のシートにまとめ、選択・既定・検索・取得不可の欄を実装した。選択時はエージェント、思考の強さ、権限を既定へ戻し、Plan を解除する。Mac のモデル応答に既定の思考強度が無いので、Claude Code は Haiku 以外で `high`、Codex/Cursor は `nil` を送る。契約 §8.2 に Mac の `BypassSettings` が無いため、初回 Claude は `bypassPermissions` が選択肢にあればそれを、無ければ `auto` を使う。Mac 側で Bypass を無効にした個別状態は iOS へ届かない。
- 初回送信を専用 ViewModel に切り出した。`spawn → waitUntilReady → send` を順に実行し、作成失敗時は本文を新規画面へ戻す。準備待ち・送信の失敗時は作成済みセッションへ本文と添付を戻す。使用量行を入力欄の下に置いた。`SessionDetailViewModel` から旧ドラフト専用の状態・処理を外した。
- 仕様書、計画書、`architecture/overview.md`、ADR 0008・0012・0023・0028・0030 を現行実装に合わせた。旧 ADR のドラフト経路には superseded の注記を追加した。作業ログ一覧に本記録を追加した。

## 2. 削除とテスト

- 旧ドラフト専用テストファイル 4 件を削除した: `AcceptanceDraftProjectContextTests.swift`、`CodexModelPickerTests.swift`、`DraftSelectionStabilityTests.swift`、`DraftSessionSpawnTests.swift`。その中の 19 テストは、画面分離で不要になったプレースホルダー表示・prepare 再入・古いモデルピッカー契約を確認していた。
- 旧ドラフト用のテスト 2 件も削除した: `draftAwaitingInitialSpawnShowsSendNotStop`（`DraftComposeSendButtonAcceptanceTests.swift`）と `draftDoesNotShowInitialLoadingSpinner`（`SessionDetailLoadingWhiteboxTests.swift`）。同じファイルにあった実セッションの停止ボタン・初回ロード確認は残した。テスト構造体名を `DraftComposeSendButtonAcceptanceTests` から `SessionDetailStopButtonAcceptanceTests` に改めた。`NavigationBackSwipeProbeTests` はホームの VoiceOver 名を「ホーム」から「ホーム（セッション一覧に戻る）」へ更新した。
- 直した確認内容（前 → 今）: `AcceptanceDraftProjectContextTests` の下書き用 project 初期値／spawn 確認 → `NewChatViewModelTests` の下部入口・「＋」入口・前回値欠落・0 件・旧 Mac の確認。実セッション名の確認 → `SessionDetailProjectContextTests.sessionContextUsesServerProjectName`。
- `CodexModelPickerTests` と `DraftSelectionStabilityTests` の旧ドラフト行・再取得時の選択保持確認 → `NewChatViewModelTests` の 3 エージェント一覧・取得不可・エージェント切替・既定値・SpawnRequest の確認。`DraftSessionSpawnTests` の初回送信確認 → 新規画面の spawn→ready→send と各失敗の確認。
- `DraftComposeSendButtonAcceptanceTests.draftAwaitingInitialSpawnShowsSendNotStop` と `SessionDetailLoadingWhiteboxTests.draftDoesNotShowInitialLoadingSpinner` はドラフト専用のため削除。実セッションの停止・初回ロード確認は保持。`NavigationBackSwipeProbeTests` の期待値は「ホーム」から「ホーム（セッション一覧に戻る）」へ変更した。
- 追加したテストは 18 件: `NewChatViewModelTests` 17 件（見出し、提案文とカーソル、プロジェクト初期値と欠落・0 件・旧 Mac、前回設定、初回既定、モデル切替と既定化、取得不可、SpawnRequest の各値と nil、spawn→準備待ち→送信、作成・準備・送信それぞれの失敗）と `SessionDetailProjectContextTests` 1 件。
- 変更前は Swift Testing 588 件・100 スイート、XCTest 379 件が成功。変更後は Swift Testing 585 件・98 スイート、XCTest 379 件が成功した。Swift Testing の差分 −3 件は旧専用ケースの削除 21 件と新しい画面・実セッションのテスト 18 件による。

## 3. 見本との見比べ

- iOS 18.3 の `Draft`・`DraftFromProject`・`DraftSuggest`・`DraftEntryEmpty`・`DraftModel`・`DraftModelNa`・`DraftPermDanger`・`DraftMoreSE`・`DraftCreating`・`DraftFailed`・`DraftSE`・`DraftDT`・`DraftDark` の 13 枚を開き、同名の盤面と比較した。モデルシートは見本の 3 エージェント・同じモデル行・選択／既定表示に合わせ、面の角丸と行カードも調整した。`DraftMoreSE` のメニュー見本は操作を合成せず、撮影専用の静的表示で描いた。
- 撮影ホストではキーボードを描けないため省いた。したがって見出し・提案・入力欄・使用量行の縦位置はキーボードがある盤面と異なる。ホーム印はナビゲーションのシステム戻るボタンを使うため、盤面の白い丸背景が iOS 18.3 の画像には出ない。本文入力・メニュー選択の実機 UI 操作はしていない。
- iOS 26.2 の現行ソースによる画像は比較できなかった。直近の起動は `Application failed preflight checks` / `Busy` でアプリが起動せず、make は Error 65 で終了した。以前の 26.2 画像はレイアウト確定待ちを足す前の撮影なので、最終比較の根拠には使わない。

画像は `.verification/ios-redesign-stage5-20261018/snapshots/` の `Draft` から始まる iOS 18.3 の 13 枚、ログは同じ作業ディレクトリの `logs/`。盤面画像は `.verification/ios-redesign/design-boards/`。

## 4. 検証

| 検証 | 結果 | ログ |
|---|---|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | Swift Testing 588 件・100 スイート成功、exit 0。XCTest は段階 4 の記録 379 件 | `logs/swift-test-before.log` |
| 変更後 `swift test --package-path ios/Packages/PhloxKit` | XCTest 379 件、Swift Testing 585 件・98 スイート、失敗 0、exit 0 | `logs/swift-test-final2.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | exit 0 | `logs/generate-final.log` |
| 指定 `xcodebuild build`（PhloxMobile・generic iOS Simulator） | `BUILD SUCCEEDED`、exit 0 | `logs/app-build-final2.log` |
| 描画テスト・iOS 18.3 | 3 件・2 スイート成功、exit 0。新規チャット画像 13 枚 | `logs/snapshot-ios18-final3.log` |
| 描画テスト・iOS 26.2 | アプリ起動前に `Busy` / `Application failed preflight checks`。テスト 0 件、make Error 65（`compact-test` exit 2） | `logs/snapshot-ios26-final.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | 生の色・フォント値 0 件、exit 0 | `logs/lint-final.log` |
| `rg -n '#available\(iOS 26' ios --type swift` | 4 件、`DesignSystemIOS` 共通部品の 2 ファイル、exit 0 | `logs/availability-final.log` |
| `git diff --check` | exit 0 | `logs/diff-check-final.log` |

iOS 18.3 の描画ログには既存の `Modifying state during view update` 41 件、`CGGStackRestore: CG GState restored too many times` 54 件があった。ほかに push 登録の `aps-environment` entitlement 不足 1 件、起動計測イベントの送信失敗 2 件が記録された。描画テスト自体は 3 件成功した。XCUITest は実行していない。

## 直し: 既定を Mac から返す

### 変更

- Mac の `GET /agents/{kind}/settings` に `defaultEfforts`（モデル ID ごと）と `defaultPermission` を追加した。キーは値があるときだけ返す。既定値の計算は `newChatDefaultSettings` にまとめ、新規チャット初期化・モデル選択・API 応答で共有する。Claude の権限は `BypassSettings` が有効なら `bypassPermissions`、無効なら `auto`。Codex・Cursor の権限既定は省略する。endpoint handler は既存の `AppBootstrap/ControlActionHandler.swift` が `newChatSettingsOptions` を返していたため、応答組み立ての追加変更は不要だった。
- iOS の DTO とモデルで両フィールドを読み、保存値が無いとき・モデル変更時は Mac の値だけを使う。既定キーがない古い Mac では effort と permission を `SpawnRequest` から省く。権限の保存値が現在の選択肢に無ければ Mac の既定へ戻す。
- 同じエージェントのモデル変更では effort だけモデル既定へ戻し、permission と Plan は保つ。エージェント変更では Mac と同じく、そのエージェントの保存済み設定（Plan を含む）へ戻し、保存値が無ければ既定を使う。Mac の `NewChatDraftStore.selectHarness`・`NewChatView.selectModel` を確認した。
- 入力欄のチップは、選択肢があって値が未指定なら「既定」を表示し、選択肢が無ければ隠す。段階 4 の AC-6-12 と同じ規則。
- 仕様書 14 章 C-9 を更新した。`architecture/overview.md` には iOS 独自の既定を定める記述が見つからなかったため、追記していない。

### テストの変更と追加

- 初回既定の確認（前 → 今）: iOS が Claude の effort を `high`、permission を `bypassPermissions` 優先で決める → Mac が返した `defaultEfforts`・`defaultPermission` を使う。Mac の Bypass 設定がオフなら `auto`、オンなら `bypassPermissions` になる。
- モデル切替（前 → 今）: モデル切替時に permission と Plan も既定化 → 同一エージェント内では permission と Plan を保ち、effort だけモデル既定へ戻す。エージェント変更時はそのエージェントの保存済み permission・Plan、または Mac 既定へ戻す。
- 古い Mac の spawn 確認（前 → 今）: optional 値を省略する一般確認 → Mac の既定キーが無い場合に effort・permission の JSON キーが存在しないことを明示して確認。
- 追加・拡張した確認: Mac wire の既定キー有無、Mac の初期値と API 値の一致、Bypass オン・オフ、iOS の既定キーあり／なしの decode、Mac 既定の採用、無効な保存 permission のフォールバック、同一エージェントでのモデル変更、エージェント変更時の保存値復元。
- `swift test --package-path ios/Packages/PhloxKit` は段階 5 の記録時の 585 件・98 スイートから、今回 590 件・98 スイートへ増え、今回の全件が成功した。

### 検証

| 検証 | 結果 | ログ |
|---|---|---|
| Mac `ControlServer` | 169 件・23 スイート成功、exit 0 | `.verification/ios-redesign-default-settings/logs/mac-controlserver.log` |
| Mac `AppBootstrap` | 176 件・23 スイート成功、exit 0 | `.verification/ios-redesign-default-settings/logs/mac-appbootstrap.log` |
| Mac `DashboardFeature` 専用ゲート | 本体 2,165 件・211 スイートで 2 issues（既知 issue 1 件を含む）、Git 別パス 41 件・4 スイート成功。全体 exit 1 | `.verification/ios-redesign-default-settings/logs/mac-dashboardfeature.log` |
| 失敗した `FocusBorderRenderTests.履歴の開いた区画だけを上下キーで移動する` の絞り込み再実行 | 1 件・1 スイート成功、exit 0。全件の合格を示すものではない | 実行結果はこの節に記録（専用ログなし） |
| iOS `PhloxKit` | 590 件・98 スイート成功、exit 0 | `.verification/ios-redesign-default-settings/logs/ios-phloxkit-final.log` |
| `make generate` | exit 0 | `.verification/ios-redesign-default-settings/logs/ios-generate.log` |
| iOS Simulator 向け Debug build | `BUILD SUCCEEDED`、exit 0 | `.verification/ios-redesign-default-settings/logs/ios-app-build-final.log` |
| Mac Debug build | `BUILD SUCCEEDED`、exit 0。アプリは起動していない | `.verification/ios-redesign-default-settings/logs/mac-app-build.log` |
| 描画・iOS 18 | 3 件・2 スイート成功、exit 0 | `.verification/ios-redesign-default-settings/logs/ios-snapshot-18-final.log` |
| 描画・iOS 26 | 3 件・2 スイート成功、exit 0 | `.verification/ios-redesign-default-settings/logs/ios-snapshot-26-final.log` |
| `make lint` | exit 0、生の色・フォント値なし | `.verification/ios-redesign-default-settings/logs/ios-lint-final.log` |

`DashboardFeature` の全体ゲートでは `FocusBorderRenderTests.swift:239` の選択行の期待値が一致せず失敗した。絞り込み再実行は成功したが、全体ゲートは green ではない。もう一つの issue は既知の `GTWRegression_改名前の名前を再利用しても利用順を混同しない()`（`GitHistoryWorkflowTests.swift:114`）。テストの skip・無効化・期待値変更はしていない。XCUITest は実行していない。

### 画像比較

- iOS 18 の画像 11 枚: `.verification/ios-redesign-default-settings/snapshots/ios18/snapshots/`。iOS 26 の画像 11 枚: `.verification/ios-redesign-default-settings/snapshots/ios26/snapshots/`。新規チャット画面は `Draft-428x926-light-ios18.png` / `Draft-428x926-light-ios26.png`、モデル一覧は `DraftModel-428x926-light-ios18.png` / `DraftModel-428x926-light-ios26.png`。
- 両 OS の新規チャット画面とモデル一覧を同名の見本（`.verification/ios-redesign/design-boards/Draft-428x926.png`、`DraftModel-428x926.png`）と見比べた。行カード背景は `DSColor.surface` を明示して見本に近づけた。新規チャットの中央部は、スナップショットホストでソフトウェアキーボードを描けないため見本より下がる。モデル一覧は既存の `.height(680)` の高さと `NavigationStack` の閉じるボタンが OS ごとに異なり、iOS 18 では見本のピル背景が出ない。入力中の配置と実機キーボード表示はこの画像では比較できない。
- 指定シミュレーターは終了時に両方 `Shutdown` を確認した。iOS 26 の撮影前に指定された `simctl shutdown` を実行した時点では既に `Shutdown` で、simctl は状態エラー 405 を返した。その後の描画テストは成功し、再確認時も両方 `Shutdown`。削除はしていない。

この修正で iOS 26.2 の描画確認は完了した。`DashboardFeature` 全体ゲートの失敗は上記のとおり残る。

## 検証（段階 5 の差分全体。検証の担当 Codex gpt-6-luna high が実行。コードは変えていない）

| 検査 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | XCTest 379 件・Swift Testing 590 件成功、失敗 0・skip 0、exit 0 |
| `make -C ios generate`・`xcodebuild build`（PhloxMobile・PhloxWidget） | exit 0 |
| `make -C ios snapshot`（iOS 18.3） | 3 件成功、exit 0 |
| `make -C ios snapshot`（iOS 26.2） | 1 回目はシミュレーターの起動直後に `Busy ("Application failed preflight checks")` でテスト前に失敗。`simctl bootstatus -b` で起動完了を待って再実行し、3 件成功、exit 0 |
| `make -C ios lint`・`git diff --check` | exit 0 |
| `rg -ln '#available\(iOS 26' ios --type swift` | 2 ファイル（GlassSurface.swift・DSPlatformTabView.swift） |
| Mac `ControlServer`・`AppBootstrap` | 169 件・176 件成功、exit 0 |
| Mac `run-swift-tests.sh DashboardFeature` | 全体のゲート exit 0（Git 別パス 41 件成功を含む）。直しの節で失敗した `FocusBorderRenderTests` は今回は失敗していない |
| Mac Debug ビルド | exit 0（アプリは起動していない） |

警告（テストは通った）: iOS 18 で `Modifying state during view update` 41 回・`CGGStackRestore` 56 回（原因は未特定。段階 6・8 で見る）、iOS 26 で `IOSurfaceClientSetSurfaceNotify failed` 1 回、`::1:8765` への接続の失敗の記録。XCUITest は走らせていない。ログは `.verification/ios-redesign/logs/verify-s5-*.log`。

段階 8 で直すもの: 428pt の iOS 18・26 で「高」と「Manual」のチップの間隔が詰まる。チップと提案チップの文字が見本より大きい。
