---
status: active
last-verified: 2026-10-17
---

# 0023: iOS 再設計 段階 3 — 下部ナビゲーションと一覧（作業記録）

> **このファイルの役割**: 計画書 [0020](0020-ios-redesign-plan.md) の段階 3 で行った、下部ナビゲーションと一覧本文の作り替え・確認結果を記録する。
> **書かないもの**: 要件（→ [仕様書](../specs/redesign-2026-10.md)）、作り方の理由（→ [ADR 0049](../adr/0049-standard-tabview-for-navigation.md)）。

## 1. 下部のナビゲーション

### 作り方の判断

- **OS 標準でできたもの**: iOS 26 は `TabView` の標準タブ・`Tab(role: .search)` の新規チャット操作・`tabViewBottomAccessory`・`.tabBarMinimizeBehavior(.onScrollDown)` を使った。iOS 18 も標準 `TabView` を使い、見出し右の 44pt 新規チャット操作は一覧だけに置いた。対応待ちとオフラインの表示は両 OS の共通部品へ寄せた。OS が提供するタブバーを独自表示へ置き換えていない。
- **OS 標準だけでは足せなかったもの**: iOS 18 の `TabView` にタブバー直上の欄を置く標準 API は使えないため、各タブ内容の `safeAreaInset` に欄を挿入した。初回描画ではタブバーに重なったので、`TabView` の外側ではなく各タブの内容内へ移し、標準タブバーの上に配置した。
- **未確認**: SwiftUI `TabView` が選択中タブの再タップで selection Binding setter を呼ぶ保証は公開資料で確認できなかった。setter が同じタブ値を受けた場合のルート復帰・一覧先頭スクロールは実装したが、XCUITest と操作の合成を使わない条件のため、実際の再タップは確認していない。
- iOS 26 の描画テストは一覧を下端へ移動した画像を出すが、`.onScrollDown` による縮小状態までは撮れなかった。OS の縮小はスクロール操作時の状態であり、操作合成を使わないため、縮小タブの見本比較は未確認。

### 変更と削除

- `AppShellView` を OS 標準タブに置き換えた。対応待ちは表示状態の 4 種から件数を作り、Mac の取得順で先頭を選ぶ。オンライン時の読み込み中・接続判定中・空・取得エラーではバーを出さない。オフライン時は最後の件数をバッジに残し、既存 `UnreachableViewModel` の最終取得時刻を使った再接続欄を表示する。詳細・下書き compose ではタブと欄を隠す。
- タブ再選択時に一覧のルートへ戻して先頭へ移動する要求を一覧へ渡す。新規チャット操作は既存の `SessionComposeDraft` へ遷移する。対応待ち欄の長押しメニューに、状態・エージェント・プロジェクトと「セッション一覧で見る」を置いた。
- `SessionNavigationState` を View 非依存の型として追加し、表示状態の件数・先頭・バー有無・バッジ・VoiceOver 名を集約した。
- ADR 0006 を superseded にし、ADR 0049 と `architecture/overview.md` を追加・更新した。計画書 6.1 の全画像名に OS 版を付ける記述を更新した。仕様書 `redesign-2026-10.md` にあった既存の差分は本作業で編集せず保持した。

削除したファイル:

- `Features/AppShell/AppShellViewModel.swift`
- `Tests/FeaturesTests/AppShellViewModelTests.swift`。このファイルだけを確認していたテスト `tabsAreSessionsAndSettingsInOrder` と `selectingTabChangesSelectedTab` を削除した。タブ選択後の表示状態は、新しい状態テストと描画テストで確認する。

追加したテスト (`SessionNavigationStateTests`):

- `includesTheFourAttentionStates`
- `preservesServerOrderWhenSelectingFirstAttention`
- `hidesAttentionAccessoryWhenListIsNotLoadedWithSessions`
- `preservesBadgeCountWhileOffline`
- `omitsZeroCountFromSessionsAccessibilityLabel`

描画テストには対応待ちあり・なし、オフライン、セッション詳細、iOS 26 の一覧下端状態を加えた。既存の一覧・セッション詳細画像名にも `-ios18` / `-ios26` を加えた。`run-simulator.sh --list-screens` にも同じ5画面を追加し、実行して一覧を確認した。

### 見本との見比べ

- `Shell` と `Shell18`: タブ、iOS 26 の丸い新規チャット、iOS 18 の見出し右の新規チャット、対応待ち欄の位置・文字・色・余白を確認した。iOS 18 は欄が標準タブバーの上に分かれて表示される。
- `ShellOffline`: 「Mac に届きません」・最終取得時刻・再接続操作を確認した。iOS 18 は補足を全文表示できる。iOS 26 は `Tail…` で省略され、見本より数文字早く切れる差が残る。オフラインでもバッジは 2 件を保つ。
- `ListManyScrolled`: 一覧内容は下端位置まで描画されたが、iOS 26 のタブバーは展開状態のまま。縮小状態を作れなかった理由は上記の操作合成制約。対応待ち欄とタブの見た目自体は `Shell` と一致した。
- 一覧の本文・行・設定画面の内容は今回の対象外のため、盤面とは異なる部分が残る。

書き出し先: `<worktree>/.verification/ios-redesign/snapshots/`。最終 iOS 26 は 17 枚、iOS 18 は 16 枚。今回出した画像名には OS 版が付いている。出力先には前段階で作った OS 版なしの `sessionList` / `sessionDetail` 画像も残っているため、既存成果物として保持した。描画画像と検証ログは見比べ・後続作業用に保持する。
全ログ: `<worktree>/.verification/ios-redesign/stage3-nav-20261017/`。

### 検証

最終コードに対して `~/.agents/scripts/compact-test` 経由で実行した。

| 検証 | 結果 | ログ |
|---|---|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | 561 テスト・98 スイート成功、exit 0 | `swift-test-before.log` |
| 変更後 同コマンド | 564 テスト・98 スイート成功、exit 0 | `swift-test-after.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | exit 0 | `generate-final.log` |
| 指定 `xcodebuild build`（PhloxMobile・generic iOS Simulator） | `BUILD SUCCEEDED`、exit 0 | `build-final.log` |
| 描画テスト・iOS 26.2 | 3 テスト・2 スイート成功、exit 0。画像 17 枚 | `snapshot-ios26-final.log` |
| 描画テスト・iOS 18.3.1 | 3 テスト・2 スイート成功、exit 0。画像 16 枚 | `snapshot-ios18-final.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | raw 色・フォント値検査成功、exit 0 | `lint-final.log` |
| `run-simulator.sh --list-screens`・`git diff --check` | exit 0 | 実行出力なし |
| `rg -n '#available\(iOS 26' ios --type swift` | 4 件。すべて `DesignSystemIOS/Support/GlassSurface.swift` または `DSPlatformTabView.swift` 内 | — |

初回の `generate` は環境変数の位置を誤って compact-test に渡したため exit 126。以降は `compact-test … env PATH=… make …` に直し、exit 0。最初の lint は AppShellView と `DSPlatformTabView` にあった固定フォント値を検出して exit 2 になった。既存 `DSFont` スタイルへ置き換え、再実行で exit 0。初期の描画試行ではコンパイル条件式と古い OS で使えない API を直し、空描画のテスト用データを増やし、iOS 18 のバー重なりを修正した。最終の両 OS は pass。

描画実行時の警告: iOS 26 は通知登録に有効な `aps-environment` entitlement が無いというログ 1 件と、`BottomAnchorMaxYKey tried to update multiple times per frame` 1 件。iOS 18 は同じ通知登録ログ 1 件、`Modifying state during view update` 12 件、`CGGStackRestore: CG GState restored too many times` 2 件、複数アーキテクチャ候補から先頭を使うという xcodebuild 警告 1 件。テストはすべて pass。XCUITest、操作合成、入力ソース変更は行っていない。`macos/Packages/DesignSystem` と `AgentDomain` は変更していない。コミットはしていない。

## 2. 一覧

### 変えたもの

- `SessionListProjection` を View 非依存の一覧モデルに置き換えた。対応待ち 4 状態を先頭に分離し、プロジェクト欄には同じ行を重ねない。プロジェクトの順は `GET /projects`、取得できない古い Mac は届いたセッションの順。未割当欄は「その他」とする。
- 同じプロジェクト内の親子だけを木にし、見つからない親・別プロジェクトの親は根に置く。子の開閉は既定で閉じ、`SessionListView` のメモリ内だけで保持する。折りたたみ時の `+N` と内訳は子孫を数える。
- 行を名前と状態語だけにし、未読名だけを semibold にした。実行中名の光の帯は 3.2 秒の 1 回再生とし、Reduce Motion で止める。VoiceOver 用の欄・開閉・行・プロジェクト新規チャット文言を投影モデルに集めた。
- プロジェクト見出しの「＋」から、その `projectID` を含む既存の下書き画面を開く。引っ張って更新ではセッション・プロジェクト・使用量を再取得する。
- `EmptyStateView`、`UnreachableView`、接続判定中、取得エラー 500/401 を盤面のコピーと配置に合わせた。500 エラーには HTTP コードを出さない。
- `AppEnvironment+UITesting.swift` に盤面名・状態の描画データを追加し、描画テストに `List`、`ListMulti`、`ListCollapsed`、子の開閉、読み込み・接続判定・空・オフライン 3 種・エラー 500/401・ダーク・375×667・Dynamic Type 最大を追加した。仕様書 4 章、計画書、`architecture/overview.md` も新しい一覧の仕様へ更新した。

削除した一覧部品:

- `DesignSystemIOS/Molecules/DSSessionRow.swift`（ロゴ・時刻・補足行を含む旧一覧行）
- `DesignSystemIOS/Molecules/DSAttentionRow.swift`（状態別の色帯を持つ旧対応待ち行）
- `DesignSystemIOS/Molecules/DSSkeletonRow.swift`（旧行のロゴ付き読み込み行）

### テストの変更

置き換えたテスト（前 → 今）:

- `groupsSessionsByProjectPreservingOrder` → `projectGroupsFollowAPIOrderAndOmitProjectsWithoutSessions`、`nilProjectOrderKeepsReceivedProjectOrderAndPutsUnassignedLast`、`sessionsWithSameProjectIDStayGroupedAcrossNameChanges`
- `unassignedSessionsGoToTrailingDefaultGroup` と `fallsBackToProjectNameWhenProjectIdMissing` → `nilProjectOrderKeepsReceivedProjectOrderAndPutsUnassignedLast`
- `groupsByProjectIdWhenBothIdAndNamePresent` → `sessionsWithSameProjectIDStayGroupedAcrossNameChanges`
- `testAttentionSessionsAreFiltered` → `testProjectionSeparatesAttentionFromProjectRows`
- `testTitleMatchesCamp` → `testCopyMatchesListEmptyDesign`
- `testUnreachableHostShowsPingHint` → `testUnreachableHostShowsEndpointAndNoResponse`
- `testOfflineNetworkCardMentionsOutOfRange` → `testOfflineNetworkUsesNeutralInternetMessage`
- `testUnreachableHostCardTitleAndPingDetail` → `testUnreachableHostShowsRedStateDetailAndLastFetchFooter`
- `testLastUpdatedTextNilWhenNoTimestamp` → `testFooterExplainsWhenThereWasNoSuccessfulFetch`
- `testRetryInvokesCallback` → `testRetryCallsTheProvidedReconnectAction`
- `sessionAndChatUseTheirSpecifiedLogoSizes` → `chatUsesItsSpecifiedLogoSize`（一覧ロゴの検査を削除）

一覧に出さなくなった機能だけを確かめていたため削除したテスト:

- `AgentBrandIconTests.skeletonRowsUseTheSessionLogoSize`、`AtomsTests.testSessionAgentLogoSizeMatchesRowsAndSkeletons`
- `MoleculesTests.testSessionRowAgentLogoUsesSharedBrandAssets`、`testSessionRowCampDetailLineCombinesSubtitleAndTime`、`testSessionRowCampDetailLineFallsBackToStatusLabel`、`testSessionRowCampTimeShowsSecondsUnderOneMinute`、`testSessionRowOpacityReflectsIdleAndCompleted`、`testSessionRowAgentLogoUsesThirtyEightPoints`
- `MoleculesTests.testSkeletonRowDefaultBarWidthRatios`、`testSkeletonRowUsesAgentLogoSizeFromSessionRow`
- `MoleculesTests.testAttentionRowUsesPromptWhenAwaiting`、`testAttentionRowFallsBackToSubtitleWhenNoPrompt`、`testAttentionRowUsesApprovalStatusTokens`、`testAttentionRowSubtitleAppendsRelativeTime`、`testAttentionRowSubtitlePreservesQuestionFormat`、`testAttentionRowChipLabelsDistinguishApprovalAndQuestion`、`testAttentionRowQuestionUsesQuestionTint`、`testCampRelativeTimeDelegatesToCompact`
- `EmptyStateViewTests.testSubtitleMentionsSpawnViaPlus`、`testCTATitleMatchesCamp`、`testIconPlaceholderUsesDashedAccentBorder`、`testLoadedListSubtitleFormat`
- `SessionListViewModelTests.testListSubtitleFormatsSessionCountAndHost`、`testListSubtitleUsesFallbackHostWhenConfigMissing`、`testAttentionSectionTitleIncludesCount`、`testOtherSectionTitleIsCampLabel`、`testSessionCountIsZeroWhenNotLoaded`。件数・ホストの見出し表示自体を廃止し、必要な接続先表示は `connectionEndpoint` を別に検証する。
- `UnreachableViewModelTests.testBannerTextIncludesOfflineAndLastFetched`、`testBannerTextOfflineOnlyWhenNoTimestamp`。バーは一覧本文からなくし、時刻案内はカードの footer で検証する。

追加した主な View 非依存テスト:

- `fourAttentionStatesAreSeparatedAndNotDuplicatedInProjects`、`projectGroupsFollowAPIOrderAndOmitProjectsWithoutSessions`、`sessionsWithSameProjectIDStayGroupedAcrossNameChanges`、`nilProjectOrderKeepsReceivedProjectOrderAndPutsUnassignedLast`
- `childrenAreNestedOnlyWhenParentIsInTheSameProject`、`collapsedSummaryCountsAttentionAndDescendantsInMacOrder`
- `unreadNameUsesPrimarySemiboldWhileOtherNamesStaySecondary`、`statusWordsMatchTheSharedVocabulary`、`accessibilityLabelsCoverHeadersDisclosuresAndProjectChatAction`
- `testProjectsResponseOrdersTheViewModelProjection`、`testPullRefreshAlsoReloadsProjectsAndUsage`、接続先の設定有無を確かめる 2 テスト、`testUnknownStateUsesConnectionJudgingCopy`

### 見本との見比べ

- iOS 26.2 と iOS 18.3.1 の出力を 2 倍へ正規化し、List の各状態を盤面画像と見比べた。前半で指摘された灰色帯と英語の大見出しはなくなり、見出しは「セッション」。タブの印も線の印。接続判定中の間隔と取得エラーのボタン形を調整し、エラーのボタンは見本と同じカプセル形になった。
- `List` と `ListCollapsed` の盤面例は対応待ちを承認・質問の 2 件で見せる一方、AC-4-3 はエラー・無応答も含める。実装は AC に従い 4 状態を上部へ出し、プロジェクト欄から重ねて除いたため、例より件数と欄の縦位置が変わる。
- `ListCollapsed` の盤面例は未読 3。Mac の `SidebarCollapsedSummary` と同じ `.doneUnread` 判定では、この描画データは未読 1 になる。件数の定義は明記済み仕様と Mac 実装を優先した。どちらを正とするかの追加回答は未着。
- 空状態のアイコンと接続判定中の回転印は SF Symbol / `ProgressView` の描画が盤面の作図と少し異なる。OS 標準部品を使うため形状差が残る。
- `ListOffNet` 本文カードは合うが、下部バーの「Mac に届きません」は盤面のネットワーク切断文言と異なる。これは前半で作った下部ナビゲーション側の表示で、前半の作業記録 §1 にも記載済み。
- `ListError` の 500 文面、401 の再接続文面、カードの余白・ボタン形、空状態の文面・位置、375×667、Dynamic Type 最大を確認した。iOS 18 の標準タブバーは `Shell18` と同じ標準表示になる。

画像出力先: `<worktree>/.verification/ios-redesign/snapshots/`。List 用画像は iOS 26 が 16 枚、iOS 18 が 16 枚。盤面との比較用に 2 倍へ正規化した 32 枚を `<worktree>/.verification/ios-redesign/visual-review-adjusted-20261017/` に置いた。検証ログは `<worktree>/.verification/ios-redesign/session-list-20261017/`。

### 検証

最終コードに `~/.agents/scripts/compact-test` 経由で実行した。

| 検証 | 結果 | ログ |
|---|---|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | 564 テスト・98 スイート成功、exit 0 | `swift-test-before.log` |
| 変更後 同コマンド | 568 テスト・98 スイート成功、exit 0 | `swift-test-final-20261017.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | exit 0 | `generate-final-20261017.log` |
| 指定 `xcodebuild build`（PhloxMobile・generic iOS Simulator） | `BUILD SUCCEEDED`、exit 0 | `build-final-20261017.log` |
| 描画テスト・iOS 26.2 | 3 テスト・2 スイート成功、exit 0。List 16 枚 | `snapshot-ios26-final-20261017.log` |
| 描画テスト・iOS 18.3.1 | 3 テスト・2 スイート成功、exit 0。List 16 枚 | `snapshot-ios18-final-20261017.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | raw 色・フォント値検査成功、exit 0 | `lint-final-20261017.log` |
| `rg -n '#available\(iOS 26' ios --type swift` | 4 件、exit 0 | `availability-final-20261017.log` |
| `git diff --check` | exit 0 | `diff-check-final-20261017.log` |

描画時の警告: iOS 26 は通知登録に有効な `aps-environment` が無いログ 1 件と `BottomAnchorMaxYKey tried to update multiple times per frame` 1 件。iOS 18 は同 entitlement ログ 1 件、`Modifying state during view update` 12 件、`CGGStackRestore` 2 件、複数アーキテクチャ候補の先頭を使う xcodebuild 警告 1 件、起動計測イベント送信失敗 2 件。これらはログに残し、テスト pass と区別した。テストの skip・期待値の書き換え・握りつぶしはしていない。XCUITest・入力／操作の合成は行っていない。シミュレーターは両方とも Shutdown を確認した。共有の `macos/Packages/DesignSystem` と `AgentDomain` は変更していない。コミットはしていない。

## 3. 見比べのあとの直し

U-6 と C-19 / AC-4-6 に合わせ、対応待ちの順序と閉じた欄の内訳・配置を修正した。前の作業の未コミット差分は保持し、コミットは行わない。

### 変更したファイル

- `Sources/Features/SessionList/SessionGrouping.swift`: `SessionAttentionQueue.ordered` に抽出・並べ替えを集約。`statusEnteredAt` の古い順、時刻なしは末尾、同順位は受信順。内訳は表示木をたどり、行と子孫だけを集計する。
- `Sources/Features/AppShell/SessionNavigationState.swift`: バーの先頭と長押しメニューが同じ共通処理を使う。
- `Sources/Features/SessionList/SessionListView.swift`: 名前と内訳の間に可変余白を入れ、内訳を「＋」の左へ寄せる。
- `App/AppEnvironment+UITesting.swift`: 一覧見本の対応待ち4行に固定時刻を設定。承認 → 質問 → エラー → 無応答の順を保つ。
- `Tests/FeaturesTests/SessionGroupingTests.swift` と `SessionNavigationStateTests.swift`: 下記の変更・追加。
- `docs/architecture/overview.md`: 共通の並び順と内訳の集計範囲を記載。
- この作業記録。

`Sources/` と `Tests/` は `ios/Packages/PhloxKit/` からの相対パス。

### テストの変更（前 → 今）

- バーの先頭: 受信順の `first → second` → 時刻の古い `second → first`。先頭だけでなくメニュー全件の順を検査し、欄の全件・先頭とも一致することを追加で検査。
- 閉じた欄の内訳: `承認待ち 1 質問あり 1 エラー 1 無応答 1 実行中 2 未読 3` → `実行中 3 未読 3`。対応待ち4状態をテストデータに残して除外を検査し、孫を1行追加して子孫集計を強化した（そのため実行中は2から3）。対応待ち欄に4行が残ることも検査する。

追加4テスト: 古い時刻優先、時刻なし末尾（時刻なし同士の受信順も維持）、同時刻の受信順維持、「その他」で対応待ち親を除いた子・孫を集計し対応待ちの子を除外すること。

### 検証

ログ保存先: `<worktree>/.verification/ios-redesign/compare-fixes-20261017/`。指定コマンドは `~/.agents/scripts/compact-test --full` 経由で実行する。

| 検証 | 件数と結果 | ログ |
|---|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | XCTest 384件・失敗0、Swift Testing 572件・98スイート成功、exit 0 | `unit.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | 生成1回成功、exit 0（テスト件数対象外） | `generate.log` |
| 指定 `xcodebuild build` | `BUILD SUCCEEDED`、exit 0（テスト件数対象外） | `build.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | 色・フォントの直書き検査成功、exit 0（テスト件数対象外） | `lint.log` |

Swift Testing は前作業の568件から4件増えて572件。XCUITest は実行しない。

| 描画テスト（上記2実行は直列） | 件数と結果 | ログ |
|---|---|---|
| 指定 iOS 26.2 シミュレーター | 3テスト・2スイート成功、exit 0、List画像16枚 | `snapshot-ios26.log` |
| 指定 iOS 18.3 シミュレーター | 3テスト・2スイート成功、exit 0、List画像16枚 | `snapshot-ios18.log` |

`git diff --check` も exit 0。generate・build・lint はテストではない。独立した型チェック・静的解析コマンドは今回確認した Makefile に未設定（Swift のコンパイルは build と swift test で実施）。

### 画像の見比べと警告

両OSの `ListCollapsed-428x926-light-ios18.png` / `ListCollapsed-428x926-light-ios26.png` と `List-428x926-light-ios18.png` / `List-428x926-light-ios26.png` を開き、見本の `ListCollapsed-428x926.png` / `List-428x926.png` と見比べた。保存先はいずれも `<worktree>/.verification/ios-redesign/` 以下の `snapshots/`（描画）と `design-boards/`（見本）。

- 閉じたPhlox欄の「実行中 2 未読 1」が「＋」の左へ寄ったことを両OSの画像で確認した。
- 対応待ちは承認・質問・エラー・無応答の順で、バーの先頭も承認の行。長押しメニューの順は共通データを使う実装と単体テストで確認し、メニューを実際に開く操作は実施していない。
- 見本の対応待ち2件に対して描画は4件、見本の内訳「エラー 1 実行中 2 未読 3」に対して描画は「実行中 2 未読 1」。今回の仕様どおり対応待ち4状態を移し、その欄に残る `.doneUnread` の行だけを数えた差である。見本の数値へ合わせるための状態変更はしていない。

今回の描画ログの警告は、両OSで通知登録の `aps-environment` 不足各1件、iOS26で `BottomAnchorMaxYKey tried to update multiple times per frame` 1件、iOS18で `Modifying state during view update, this will cause undefined behavior` 12件と `CGGStackRestore: CG GState restored too many times` 2件、複数の実行先候補の先頭を使う xcodebuild 警告1件。警告は解消しておらず、テスト成功と区別する。

終了後に両指定シミュレーターの `Shutdown` を確認した。iOS26への明示的なshutdown要求は既に停止済みで exit149（`Unable to shutdown device in current state: Shutdown`）。erase/delete は実行せず、別作業の起動中シミュレーターは操作していない。今回の xcodebuild の終了も確認済み。ログ・画像・指定ビルド出力は再確認用として保持した。既存の未コミット変更を巻き戻しておらず、コミットも行っていない。

## 4. 検証（2026-10-17、段階 3 の差分全体。検証の担当 Codex gpt-6-luna high が実行。コードは変えていない）

| 検査 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | XCTest 384 件・Swift Testing 572 件成功、失敗 0・skip 0、exit 0（段階 2 の XCTest 407 件から減ったのは、1・2 章で消した旧部品のテスト） |
| `make -C ios generate`・`xcodebuild build`（PhloxMobile・PhloxWidget） | exit 0 |
| `make -C ios snapshot`（iOS 26.2・iOS 18.3） | どちらも 3 件成功、exit 0 |
| `make -C ios lint`・`git diff --check` | exit 0 |
| `rg -ln '#available\(iOS 26' ios --type swift` | `GlassSurface.swift`・`DSPlatformTabView.swift`（どちらも DesignSystemIOS の共通の部品。AC-2-12） |
| `run-simulator.sh --list-screens` | 27 画面、exit 0 |

警告（テストは通った）: 両 OS で `aps-environment` が無く通知の登録に失敗、iOS 26 の `BottomAnchorMaxYKey`、iOS 18 の `CGGStackRestore` 2 回、同じ UDID に arm64・x86_64 の候補がある xcodebuild の警告。XCUITest は走らせていない。
