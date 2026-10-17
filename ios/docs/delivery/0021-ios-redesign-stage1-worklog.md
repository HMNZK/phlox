---
status: active
last-verified: 2026-10-17
---

# 0021: iOS 再設計 段階 1 — 土台の部品と、廃止する機能の削除（作業記録）

> **このファイルの役割**: 計画書 [0020](0020-ios-redesign-plan.md) の段階 1 で何を消し、何を足したかの記録。とくに「テストを消したのは機能と一緒に消したからで、残す機能のテストを弱めたのではない」ことを、削除した機能ごとに示す。
> **書かないもの**: 要件（→ [specs/redesign-2026-10.md](../specs/redesign-2026-10.md)）、決定の理由（→ ADR 0043〜0048）。

## 0. 先に確かめたこと: 左上のホームのボタンと端スワイプ（ADR 0033）

- **決めた作り方**: システムの戻るボタンのまま、セッション一覧のタブの `NavigationStack` のバーに、戻るの印を `house` にした appearance を掛ける（[ADR 0048](../adr/0048-home-button-is-the-system-back-button-with-a-house.md)）。デリゲートは差し替えない。
- **確かめ方**: アプリにホストした単体テスト `ios/PhloxMobileSnapshotTests/NavigationBackSwipeProbeTests.swift` で、1 段 push した画面の `interactivePopGestureRecognizer` の有効・`gestureRecognizerShouldBegin`・バーの項目・戻るの印・pop→push 後を見た。XCUITest・入力・操作の合成は使っていない。
- **結果**: iOS 26.2（`Phlox ios-redesign 26`）・iOS 18.3.1（`Phlox ios-redesign 18`）とも 1/1 pass・exit 0。4 つの作り方の表は ADR 0048。決めた作り方では、開始の判断は true、家の印は pop→push の後も残った。
- **確かめていないこと**: 指での端スワイプ、家の印を押したとき、戻った後の一覧の大タイトル（ADR 0033 で実機だけに出た不具合）。**実機での確認をユーザーに頼む**（段階 6 のセッション画面の作り替えの後）。
- **見本との差**: サブエージェント詳細で家の印を押すと親のセッションへ戻る（見本は一覧へ）。仕様書 15 章 U-21。

## 1. 消した機能と、一緒に消したテスト

各行の「消したテスト」は、消した機能だけを確かめていたテスト。残す機能を確かめるテストは消していない・期待値を変えていない。

| 機能 | 消したソース | 消したテスト | 残した関連（理由） |
|---|---|---|---|
| 端末画面と出力カード（ADR 0044） | `TerminalScreenIOS/`（5 ファイル）と `Package.swift` の product・target、`PhloxCore` の `TerminalScreen.swift`。`PhloxAPI.output`・`terminalScreen` と DTO・クライアント・スタブ。`SessionDetailView`・`SessionDetailViewModel`・`SessionDetailMetrics` の出力の取得・ポーリング・表示 | `TerminalScreenIOSTests/`（4 ファイル）、`TerminalScreenTests.swift`。部分: `E2EFlowTests.testOutputFetchForDetail`、`APIExtensionsClientTests.testOutputPercentEncodesSpaceInSessionID`、`PhloxNetworkingTests.testOutputDecodes`、`ChatVisibilityAcceptanceTests.noIndicatorInTerminalMode`、`SessionDetailViewModelTests` の出力の取得・切り替え・切り詰め 7 件、`SessionDetailViewTests` の出力 7 件、`SessionDetailViewUXTests` の端末表示 5 件、`SessionDetailLoadingWhiteboxTests.outputFallbackCompletesInitialLoading`、`SessionDetailErrorRecoveryAcceptanceTests.terminalRecoveryClearsLoadError` | 会話のコマンドの出力（`ChatMessage.command.output`）は残す。会話の取得の失敗は、前は出力の取得の失敗として出ていたので、会話の取得から直接エラーを出すようにした（404 は空の会話に落とす。テストを足した）。通信エラーの表示と、会話が届いたときに戻るテストは残す |
| 使用量タブ（ADR 0045） | `Features/Usage/UsageView.swift`、`AppTab.usage`、`AppRoot` のタブ・ルーター・経路 | 部分: `AppShellViewModelTests` の使用量タブの順序・選択（タブの順序の確認は「セッション・設定」に直した） | `UsageViewModel` とそのテスト（段階 4 の入力欄の下のリングで使う） |
| 俯瞰グリッド | `Features/SessionsOverview/`（5 ファイル）、`AppRoot`・`AppShell` の経路と保持 | `SessionsOverviewViewModelTests.swift`。部分: `AppShellViewModelTests.selectingCurrentNonOverviewTabDoesNotChangeOverviewMode`・`shellRetainsTheInjectedOverviewInstanceAndItsSelection` | なし（下部タブから到達できないデッドコードだった。ADR 0007） |
| Codex の 4 択シート | `CodexApprovalSheet.swift`、`ApprovalViewModel` のシートの分岐（`agentKind`・`showCodexSheet`）、`ApprovalBarView` のシートの表示 | `CodexApprovalSheetTests.swift`。部分: `testCodexUsesSheet`・`testCodexTapOpensSheetWithoutResponding` | Codex も今の承認バーの「承認」「却下」から直接応答する（`testCodexCanAcceptAndDeclineFromApprovalBarActions` で確かめる）。段階 6 で承認のカードに置き換える |
| 独立した質問の回答画面 | `Features/ChatAnswer/`（2 ファイル）、`Route.chatAnswer`、`AppRoot` の経路、一覧の `onAnswerQuestion` | `ChatAnswerViewModelTests.swift`。部分: `ChatSurfaceAcceptanceTests.chatAnswerSendReturnsToIdle` | 質問ありの行はセッション画面を開く。セッション画面の質問のカードと `UserQuestionAnswerTests` は残す |
| UI テスト（ADR 0047） | `PhloxMobileUITests/` のターゲット、`project.yml` のターゲットとスキームの test、`Makefile` の `run-ui-test`、UI テストだけが使うスクリプト（`compare-screenshots.py`・`extract-design-screenshots.py`・`fake-phlox-server.py`）。見本の画面から `spawn`・`spawnError`・`chatAnswer`・`codexApproval` | `PhloxMobileUITests/` の 7 ファイル（`PhloxMobileScreenshotTests`・`PhloxMobileUITests`・`SessionDetailBackSwipeUITests`・`SessionInputBarRunningUITests`・`SessionListTitleLiveRegressionUITests`・`SessionTerminalLiveRegressionUITests`・`Wave5RegressionUITests`） | `-UITesting` の見本のデータ・`run-simulator.sh --screen`・描画テスト（`PhloxMobileSnapshotTests`） |
| 呼び出し元の無い部品・権限文 | `DSVoiceInputController`・`DSFAB`・`DSTextField`・`DSConnectionIndicator`・`DSFixedBottomCTA`、`Info.plist`・`project.yml` のマイクと音声認識の権限文 | `DSVoiceInputSetupTests.swift`・`VoiceInputControllerTests.swift`。部分: `AtomsTests` の `DSTextField` 4 件・`DSFAB` 6 件・`DSConnectionIndicator` 2 件、`MoleculesTests` の `DSFixedBottomCTA` 3 件 | `DSCampAgentBadge` は行・吹き出し・アバターから使われていたので、ここでは残し、ロゴの置き換え（2 章）で消す |

テストの件数（`swift test --package-path ios/Packages/PhloxKit`）: 削除前 619 件・105 スイート → 削除後 547 件・96 スイート（どちらも exit 0）。減った 72 件は、上の表の「消したテスト」から、足した 1 件（会話の 404 を空の会話に落とす）を引いたもの（ファイルごとの件数の数え合わせはしていない）。

## 2. 足したもの・変えたもの

| 項目 | 足した・変えたもの | 消したもの |
|---|---|---|
| 色（仕様書 2.1） | `DesignSystemIOS/Tokens/IOSColor.swift`（`accent`・`accentOnFill`・文字 3 段・`stop`/`badge`・`status.*`（`stalled` を含む）・面）。共有の `DSColor` と名前がぶつからないよう別の名前空間にした。ライト・ダークは `ThemeStore.active` で決める。呼び出し元と `.tint` を移した | `DSColor+IOS.swift`（`campAgentColor`・`campAccentBright`・`campAttention`・ほかの camp の色）、`DSGradient.swift`、`DSGradientButton.swift`、紫の光彩 `DSShadow.ctaGlow`・`fabGlow`（AC-2-1） |
| 状態の語（2.3） | `IOSStatusVocabulary.swift`（状態 → 語・色・太さ。待機は出さない）。状態のチップ・注意の行・処理中の表示がこれを使う。「回答待ち」「質問待ち」は「質問あり」に | 終了コードごとの表示の区別（完了は 1 つの語） |
| ロゴ（2.2） | `DSAgentBrandIcon.swift`（共有の `AgentBrandIcon` を包む。Cursor だけ暗い面で輪郭が見えるよう細い線）。VoiceOver はエージェント名 | `DSCampAgentBadge`・`DSAgentAvatar`・`DSAgentBadge`（略号のバッジ） |
| ガラス（2.6） | `Support/GlassSurface.swift`（`glassSurface(_:)`。対応待ちバー・入力欄・カード・丸いボタン）。`#available(iOS 26, *)` はこのファイルだけ。今は呼び出し元が無い（段階 3〜6 で使う） | — |
| 左上のホーム（ADR 0048） | `Support/NavigationStackHomeBackButton.swift`。一覧のタブの `NavigationStack` に付けた。戻るボタンの読み上げは「ホーム」 | 探りのテストの作り方 A2・B・C（結果は ADR 0048） |
| DotGothic16（2.4・AC-11-3） | `ios/Resources/DotGothic16-Regular.ttf`・`OFL.txt`（Mac と同じファイル）、`UIAppFonts`、`display.dot`（28・xxxLarge〜AX4 34・AX5 44）、設定の「このアプリについて」のライセンスの行と `DotGothic16LicenseView` | — |
| 描画テスト（計画書 6.1） | 安全領域と倍率、部品の見本 `components`、フォントとライセンスの確認。`NavigationBackSwipeProbeTests` はホームの部品を確かめるテストに書き換えた | — |
| 前からの不具合 | 色を `static let` で持っていた 3 か所（`DSChatBubble.userMessageForeground`・`DSToggle` の 2 つ・`DSMarkdownText` のテーマ）を、毎回引く形にした。最初に引いた外観の色で固まり、ライトの後にダークを描くと会話の文字が背景に沈んでいた | — |

**消したトークンを確かめていたテスト**は、新しい値を確かめる形に置き換えた（assert は減らしていない）。前に確かめていたこと → 今確かめること:

| テスト | 前 → 今 |
|---|---|
| `testBrandGradientUsesCampRGBValues` → `testAccentAndAccentOnFillMatchDarkTheme`・`testIOSColorTokensMatchLightTheme`・`testIOSColorTokensMatchDarkTheme` | グラデーションの RGB・角度 → accent と上の文字、ライト・ダークの全色 |
| `testCampColorAliasesMatchDesign` → `testRedesignReplacesLegacyColorsWithSemanticTokens` | camp の色 → 意味の色・面 |
| `testCampModalBackdropMatchesDesignBrightness`・`testBackdropOverlayOpacityMatchesCampBrightness`・`testBackdropMetricsUseDSColorModalBackdropToken` → `testModalBackdropUsesRedesignDimToken`・`testBackdropMetricsMatchRedesignValuesInLightAndDarkThemes`・`testBackdropMetricsUseIOSDimTokenInLightAndDarkThemes` | camp の暗転 → `dim`（ライト 0.28・ダーク 0.45） |
| `testToggleUsesCampStyleTokens`・`testApproveVariantUsesStatusRunningAndTextOnBrand`・`testDeclineOutlineVariantUsesCampAttentionBorder` | camp の色 → `text.primary`・`status.success`、`accent`・`accentOnFill`、`status.error` |
| `testStatusChipResolvesDistinctIconsForAllSixStates` → `testStatusChipUsesCanonicalWordsAndOmitsWaiting`・`testStatusVocabularyDefinesWordColorAndWeightForEveryCurrentState` | 記号の区別 → 状態ごとの語・色・太さ（アプリ内は文字だけ。2.3） |
| `testStatusChipDistinguishesCompletedExitCodes` → `testStatusChipUsesTheSameCompletedStyleForAllExitCodes` | 終了コードごとの表示 → 「完了」1 つ |
| `testSessionRowCampAbbreviationsDelegateToCampAgentBadge` → `testSessionRowAgentLogoUsesSharedBrandAssets` | 略号 → 共有のロゴ |
| `testAttentionRowCampTokensMatchDesign`・`testAttentionRowChipUsesAwaitingTint` → `testAttentionRowUsesApprovalStatusTokens`・`testAttentionRowQuestionUsesQuestionTint` | camp の色 → 承認・質問の状態の色 |
| `testAttentionRowSubtitlePreservesQuestionFormat`・`testAttentionRowChipLabelsDistinguishApprovalAndQuestion` | 「回答待ち」「質問待ち」 → 「質問あり」 |
| `testNavigationChromeUsesSurfaceAndDarkScheme` | 共有の面・前の accent → `IOSColor.bg.base`・`IOSColor.accent` |
| `testCampShadowGlowValuesMatchDesign` → `testDialogShadowValuesMatchDesign` | 紫の光彩とダイアログの影 → ダイアログの影だけ（光彩は消した） |

## 3. 検証

2026-10-17、作業全体の差分に対して（検証の担当が実行。コードは変えていない）。

| 検証 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | 547 件成功・失敗 0・skip 0、exit 0 |
| `make -C ios generate` | exit 0 |
| `xcodebuild build`（`PhloxMobile`・`PhloxWidget`、`generic/platform=iOS Simulator`） | どちらも BUILD SUCCEEDED、exit 0 |
| `make -C ios snapshot`（iOS 26.2・iOS 18.3） | どちらも 3 件成功（描画・ホームの部品・DotGothic16 とライセンス）、TEST SUCCEEDED、exit 0 |
| `make -C ios lint` | exit 0 |
| 消した名前の `rg`（`ios/docs` を除く） | 0 件 |
| `rg -ln '#available\(iOS 26' ios --type swift` | `GlassSurface.swift` の 1 つだけ（AC-2-12） |

`macos/` は変えていないので、macOS のテストは走らせていない。XCUITest は走らせていない。

ログに出た警告（テストは通った）: iOS 26 で `BottomAnchorMaxYKey tried to update multiple times per frame` が 1 回。iOS 18 でセッション画面を描くたびに `Modifying state during view update` が 2 回（計 10 回）と `CGGStackRestore`。`Modifying state` は、ホームの部品を外して撮っても同じ 10 回出たので、ホームの部品が原因ではない（セッション画面の側。段階 6 の作り替えで見る）。
