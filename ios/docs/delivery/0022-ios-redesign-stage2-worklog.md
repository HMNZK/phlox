---
status: active
last-verified: 2026-10-17
---

# 0022: iOS 再設計 段階 2 — API の配線とサブエージェント詳細の廃止（作業記録）

> **このファイルの役割**: 計画書 [0020](0020-ios-redesign-plan.md) の段階 2 で何を足し、何を消したかの記録。とくに「テストを消したのは機能と一緒に消したからで、残す機能のテストを弱めたのではない」ことを示す。
> **書かないもの**: 要件（→ [specs/redesign-2026-10.md](../specs/redesign-2026-10.md)）、ワイヤの形（→ [specs/mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md) §8.10・§8.11）、決定の理由（→ macOS ADR 0216 の追記 8・9）。

## 0. 先に決めたこと（2026-10-17）

- ユーザーの決定: U-21（サブエージェント詳細の廃止）、U-2（表示できない会話＝Mac で端末として動いているセッション）。
- 「終了」は足さない（PM 決定。仕様書 U-3）。Mac に完了と別の「終了」の状態が無いため。
- 残りの未決のうち U-4・U-5・U-6・U-15・U-17・U-18・U-20・U-22・U-23 を、Mac に合わせる → 見本 → 最も単純、の順で決めた（仕様書 15 章）。

## 1. サブエージェント詳細の廃止

仕様書 AC-8-13・15 章 U-21 に従い、サブエージェントの行は押せない表示にした。段階 6 の見た目の作り替えは含めない。以下のパスは `ios/Packages/PhloxKit/` を基準とする。

| 機能 | 消したソース | 消したテスト | 残した関連（理由） |
|---|---|---|---|
| サブエージェント詳細画面・会話取得・ポーリング・描画制限 | `Sources/Features/SessionDetail/SubAgentDetailView.swift`・`SubAgentDetailViewModel.swift`（ファイル削除） | `Tests/FeaturesTests/SubAgentDetailViewModelTests.swift`（3 件）・`SubAgentFreezeWhiteboxTests.swift`（3 件）・`SubAgentRenderBudgetTests.swift`（8 件）・`AcceptanceSubAgentTranscriptWindowTests.swift`（7 件）をファイル削除。部分: `SubAgentAndAttachmentAcceptanceTests.subAgentDetailLoadsMessages` | 本体の会話の取得・ポーリング・`TranscriptWindow`・コピー・ツール行の描画は使用中なので残す |
| 行から詳細への遷移と、そのための一覧取得 | `SessionDetailView.selectedSubAgentID`・`navigationDestination(item:)` のサブエージェント経路と行の押下処理。`SessionDetailViewModel.makeSubAgentDetailViewModel`・`resolveSubAgentID(forMessageID:)`・`subAgentID(forMessageID:)`・`refreshSubAgentIndex`・`updateSubAgentMarkerIndex`・`subAgentMarkerIndex` と `load`／`refresh` からの取得呼び出し。`DSSubAgentRow.isTappable`・`onTap`・Button・詳細の案内・「›」・タップ領域指定 | 部分: `SubAgentAndAttachmentAcceptanceTests.resolvesSubAgentIDByMarker`・`doesNotResolveOnMarkerMismatch`・`doesNotResolveOnOldServer`、`SessionDetailViewModelTests.testResolveSubAgentIDByMarkerMessageID`・`testResolveSubAgentIDReturnsNilOnOldServer`・`testRefreshSubAgentIndexDoesNotSetLoadErrorOnOldServer` | `ChatMessage.subAgent`・`ChatRowKind.subAgent`・`DSSubAgentRow` は会話の行表示に必要。ラベルと本文を VoiceOver の1要素にまとめ、ボタンの特性は付けない。全文の長押しコピーは残す。`SubAgentAndAttachmentAcceptanceTests` の画像添付7件は不変 |
| iOS の一覧・詳細会話 API と型・スタブ | `PhloxCore/Protocols/PhloxAPI.swift` の `subAgents(sessionID:)`・`subAgentMessages(sessionID:subAgentID:)`（プロトコルと既定実装）、`PhloxNetworking/PhloxAPIClient.swift` の同メソッド、`DTOs.swift` の `SubAgentsListDTO`・`SubAgentDTO`、`PhloxCore/Models/APIExtras.swift` の `SubAgentSummary`・`SubAgentStatus`。`Tests/FeaturesTests/MockAPI.swift` の両 API・結果・回数・ログ・`setSubAgentsOutcome`・`setSubAgentMessagesOutcome` | 部分: `APIExtensionsClientTests.testSubAgentMessagesPercentEncodesSlashInRequestPath`・`testSubAgentMessagesPercentEncodesSpaceAndHashInRequestPath`、`APIExtensionsAcceptanceTests.subAgentsDecodesContract`・`subAgentMessagesDecodesContract` | `PhloxNetworkingTests/SubAgentMessageAcceptanceTests.swift` は全4件を残す（通常会話の subAgent デコード・本文欠落・未知種別・既存6種を検証しており、詳細取得のテストではない）。汎用のパス符号化と承認 API のテストは残す。`App/AppEnvironment+UITesting.swift` に廃止する API・見本データは無く、変更不要。Mac の API（契約 §2・§3）は変更しない |

テストの件数（`swift test --package-path ios/Packages/PhloxKit`、削除前・削除後とも **exit 0**）:

| ランナー | 削除前 | 削除後 | 削除数 |
|---|---:|---:|---:|
| XCTest | 430 | 404 | 26 |
| Swift Testing | 547（96 スイート） | 541（96 スイート） | 6 |
| 合計 | **977** | **945** | **32** |

削除した32件は、ファイル削除21件と部分削除11件の合計。失敗・skip は削除前後とも0件。段階 1 の記録 0021 の「547 件」は Swift Testing の件数であり、今回は XCTest も分けて記録した。残した混在ファイルの関数本文は変更前と一致することを比較で確認した。`ChatRowKindTests`・`ChatRecapIOSWhiteboxTests`・`ChatSurfaceAcceptanceTests`・`ChatVisibilityAcceptanceTests`・`CommandGroupRowWindowTests`・`ChatMessagesDecodingTests`・`SubAgentMessageAcceptanceTests`・`DSChatActivityComponentsTests` はファイル全体が変更前と一致する。残す機能の期待値変更・skip の追加はない。

資料は `architecture/overview.md` の型・API・ID 解決・詳細画面の説明を廃止に合わせて更新した。過去の作業記録 0014・0021 の「今も使う」「見本との差」には当時の記述であることと今回の廃止先を添えた。過去の ADR 本文・見本の HTML は変更していない。

検証は指定の `~/.agents/scripts/compact-test --full <ラベル> <コマンド>` 経由で実行した。ログは worktree ルートの `.verification/ios-redesign/logs/` に保存する。

| 検証 | 結果・exit | ログ（上記ディレクトリ内） |
|---|---|---|
| 削除前 `swift test --package-path ios/Packages/PhloxKit` | 977 件成功・exit 0 | `stage2-subagent-before.log` |
| 削除後 同コマンド | 945 件成功・exit 0 | `stage2-subagent-after.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | 成功・exit 0 | `stage2-subagent-generate.log` |
| `xcodebuild build -project ios/PhloxMobile.xcodeproj -scheme PhloxMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/ryosuke/Projects/Phlox-oss-worktrees/ios-redesign/.verification/ios-redesign/build CODE_SIGNING_ALLOWED=NO` | `BUILD SUCCEEDED`・exit 0 | `stage2-subagent-build.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | raw color/font literal の検査成功・exit 0 | `stage2-subagent-lint.log` |
| `rg -n 'SubAgentDetail\|subAgentMessages\|resolveSubAgentID\|SubAgentSummary' ios --glob '!ios/docs/**'`（正規表現の縦棒は実行時にエスケープしない） | 0 件・exit 1（rg の一致なし） | `stage2-subagent-references.log` |
| 残したテストの本文比較 | 変更なし・exit 0 | `stage2-subagent-retained-tests.log` |

削除後の SwiftPM 再コンパイルでは、変更していない `DSReasoningTextWhiteboxTests`・`DSChatBubbleAttachmentTests`・`InputBarAttachmentNumberingAcceptanceTests` から、MainActor に隔離された静的プロパティ／メソッドを非隔離のテストから参照する警告が出た（原文は `stage2-subagent-after.log`）。テスト失敗は無く、今回の対象外として変更しなかった。独立した型チェック・静的解析コマンドは設定されておらず、型の検査とリンクは SwiftPM テストビルドと iOS アプリビルドの範囲。XCUITest は未実行。実機のタップ・VoiceOver の音声・画面の目視確認は未検証。ログとビルド成果物は PM の後続検証用に保持し、アプリ・サーバーは起動していない。コミットはしていない。

## 2. 通信層の配線

契約 §8.1〜§8.11 と仕様 2.3・U-2・U-3・U-6・U-8・U-22 に沿って、API・モデル・状態語彙を追加した。画面の作り替えは含めていない。

- `GET /sessions`: `backend`・`isStalled`・`hasUnseenCompletion`・`parentSessionId`・`statusEnteredAt` を `Session` に写す。旧 Mac では backend=`appServer`、2つのフラグ=false、親と時刻=nil。`Session.displayState` は共有 `SessionDisplayState.resolve` を使い、iOS 語彙は9状態を既存 iOS 色で表す。`Session.isPTY` を追加した。
- 並び: API の変換・一覧グループ・ウィジェット保存はいずれも入力順を保持する。`SharedSessionWriter` にあった `updatedAt` 順の並べ替えを外した。
- userQuestion: `toolName`・`toolDetail` を質問1件のモデルへ追加し、`toolName` の有無を `isToolPermission` で判定する。Mac `ControlQuestionWireContract` と一致する定数を追加した。
- 取得口: `GET /agents/{kind}/settings`・`GET /projects` を `PhloxAPI` とクライアントに追加。既存のセッション設定シーム `SessionModelSelecting` に `PATCH /sessions/{id}/settings` を加え、`GET /sessions/{id}/settings` の effort・permission・Plan 項目を拡張した。未指定の spawn 設定は body から省く。
- 旧 Mac: agent settings と projects の404は nil、session settings の新項目欠落は選択肢なし・Plan不可、設定更新の空の400は `PhloxError.unsupported`。理由付き400と409・425・500は status と理由を `PhloxError.server` に残し、404は `notFound`、spawn の422は `spawnRejected` として区別する。permission の `null` と未指定は別にエンコードする。
- モック: `StubPhloxAPI`・`MockAPI`・`UITestPhloxAPI` に新規取得口を反映した。

足したテスト:

- `IOSRedesignStage2APITests`: `sessionListReadsMetadataAndPreservesOrder`、`oldSessionDTOUsesCompatibilityDefaults`、`agentSettingsGetsKindPathAndDecodes`、`oldMacAgentSettings404ReturnsNil`、`projectsGetsAndDecodesInResponseOrder`、`oldMacProjects404ReturnsNil`、`sessionSettingsDecodesExtendedFields`、`oldSessionSettingsMissingNewKeysUsesUnavailableDefaults`、`spawnSendsOptionalSettings`、`spawnOmitsNilOptionalSettings`、`updateSessionSettingsSendsSelectedKeysAndExplicitNull`、`updateSessionSettingsOmitsUnspecifiedKeys`、`oldMacPatch400MapsToUnsupported`、`patchValidation400RetainsReason`、`patch409ReasonsRemainDistinct`、`patchMapsNotFoundNotReadyAndServerFailure`、`spawn422MapsSettingsFailure`、`wireConstantsMatchMacNames`。
- `ToolPermissionQuestionTests`: `decodesToolPermissionQuestion`、`missingToolNameIsNotPermission`。
- `SessionDisplayStateTests`: `testSessionUsesSharedDisplayStateRules`、`testVocabularyMapsAllNineSharedStates`。
- `SharedSessionStoreTests`: `testSharedSessionWriterPreservesInputOrder`。

テスト件数と検証:

| 検証 | 変更前 | 変更後 | exit |
|---|---:|---:|---:|
| XCTest | 404 | 407 | 0 |
| Swift Testing | 541（96スイート） | 561（98スイート） | 0 |
| 合計 | **945** | **968** | **0** |

初回の変更後テストでは、共有デザインシステムの色を誤って iOS の状態色に使い、XCTest 17件が失敗した。状態判定は共有ルールのまま、色を既存の iOS トークンへ戻して再実行し、最終は968件成功。初回ログは `ios-api-stage2-iteration1.log`、最終ログは `ios-api-stage2-final.log`。

| 検証 | 結果・exit | ログ |
|---|---|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | 945件成功・exit 0 | `ios-api-stage2-before.log` |
| 変更後 同コマンド | 968件成功・exit 0 | `ios-api-stage2-final.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | 成功・exit 0 | `ios-api-stage2-generate.log` |
| 指定の `xcodebuild build`（generic iOS Simulator、指定 Derived Data） | `BUILD SUCCEEDED`・exit 0 | `ios-api-stage2-build-final.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | raw value lint 成功・exit 0 | `ios-api-stage2-lint-final.log` |

最終の SwiftPM テスト・Xcode ビルド・lint のログに警告・エラーはない。XCUITest は未実行。`macos/` と共有 `DesignSystem`・`AgentDomain` は変更していない。コミットはしていない。

## 3. 検証（2026-10-17、段階 2 の差分全体。検証の担当 Codex gpt-6-luna high が実行。コードは変えていない）

| 検査 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | XCTest 407 件・Swift Testing 561 件（98 スイート）成功、失敗 0・skip 0、exit 0 |
| `make -C ios generate`・`xcodebuild build`（PhloxMobile・PhloxWidget、iOS Simulator） | すべて exit 0 |
| `make -C ios snapshot`（iOS 26.2・iOS 18.3） | どちらも 3 件成功、exit 0 |
| `make -C ios lint`・`git diff --check` | exit 0 |
| `swift test --package-path macos/Packages/ControlServer`・`AppBootstrap` | 168 件・176 件成功、exit 0 |
| Mac の Debug ビルド（`xcodebuild -scheme Phlox -configuration Debug`。起動はしていない） | exit 0 |
| `rg 'SubAgentDetail|subAgentMessages|resolveSubAgentID|SubAgentSummary' ios`（資料を除く） | 0 件 |

ログに出た警告（段階 1 と同じもの）: iOS 26 の `BottomAnchorMaxYKey tried to update multiple times per frame` 1 回、iOS 18 の `Modifying state during view update` 10 回と `CGGStackRestore` 2 回。Mac のビルドで App Intents のメタデータ抽出の省略の警告 2 件。XCUITest は走らせていない。
