---
status: complete
last-verified: 2026-10-17
---

# 0024: iOS 再設計 段階 4 — 入力欄・セッション設定・使用量リング（作業記録）

> **このファイルの役割**: 計画書 [0020](0020-ios-redesign-plan.md) の段階 4 で行った、入力欄・セッション設定・使用量リングの変更と確認結果を記録する。
> **書かないもの**: 要件（→ [仕様書](../specs/redesign-2026-10.md)）、API の契約（→ [mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md)）。

## 1. 入力欄

### 変更

- `DSInputBar` を 2 段に作り直した。本文は最大 5 行で内部スクロールし、通常時と選択肢のない質問への回答時でプレースホルダーを切り替える。添付は 56pt のサムネイル、番号、削除操作、枚数を表示し、4 枚後も「＋」を残す。本文中の `[Image #N]` は太字アクセント色にした。添付・設定の失敗は欄の上に赤字で表示する。
- 2 段目に画像追加、モデル、思考の強さ、権限、送信／停止を配置した。新規チャット向けのプロジェクト選択は差し込み口を用意した。幅判定は純粋関数にし、思考の強さと権限のメニュー化、プロジェクト名の省略、2 段目の折り返しを行う。強い権限は Mac から届く値で判定し、常に赤いチップとして表示する。
- iOS 26 は `glassSurface(.inputField)`、iOS 18 は素材面と細い枠を使う。入力欄用の `DSFont` トークンで通常・Dynamic Type 最大の字面を選ぶ。
- セッション詳細では既存の `SessionModelSelecting` と `GET /sessions/{id}/settings`・設定 PATCH を接続した。モデルは選択中エージェントの候補だけをシートに出し、思考の強さ・権限は Mac から届いた選択肢を使う。選択後すぐ PATCH し、成功時は settings を取り直す。失敗・409 は元の値を保って赤字を出す。425 は ready を待って一度だけ再送する。権限変更時は Plan を解除する。強い権限の選択には OS 標準の確認アラートを使う。
- 仕様書、計画書、`architecture/overview.md`、ADR 0018・0042 を現行実装へ合わせた。ADR 0016 は既に ADR 0046 で superseded のため変更していない。README の一覧に本記録を追加した。

### 削除とテスト

- `DSChatInputBar.swift` を削除した。これだけを対象にしていた XCTest 6 件も削除した: `testChatInputBarCannotSubmitWhenEmptyOrWhitespace`、`testChatInputBarCannotSubmitWhileLoading`、`testChatInputBarCanSubmitWithText`、`testChatInputBarMinHeightMeetsTouchTarget`、`testChatInputBarFieldCornerRadiusMatchesCampPill`、`testChatInputBarSendButtonUsesArrowUpIcon`。
- テスト名と検証内容を変更した: `inputBar_keepsExistingContracts` → `inputBar_usesTwoRowsAndDesignTouchTargets`、`testInputBarMinHeightMeetsTouchTarget` → `testInputBarChipAppearanceAndTouchTarget`、`testSubmitBarLogicSharedBetweenInputBars` → `testSubmitBarLogicAndSessionInputBarUseSameEligibility`。本文プレースホルダーのテストは「やりたいことを入力」と「回答を入力」の両方を確認するようにした。旧 4 行上限・ピル外観の確認は、新しい 5 行・カーソル・56pt 添付・34pt チップ・44pt タップ領域の契約確認に置き換えた。
- 追加したテストは `DSInputBarLayoutTests` の 7 件（4 幅例、強い権限の幅別表示、wire 値判定）、`SessionSettingsSelectionTests` の 6 件（選択肢が空の状態、PATCH と再取得、既定の null、Plan、409、425）、`sendingEmptyNonRunningInputKeepsDisabledSpinnerSlot`、`nilSelectedModelUsesMacDefaultModelForChipAndSheetMarker`。

### 見本との見比べ

- iOS 26.2 と iOS 18.3.1 の `ReplyEmpty`、`ReplyTyping`、`ReplyRunEmpty`、`ReplyRunText`、`ReplySending`、`ReplyStarting`、`ReplyPermDanger`、`ReplyPermFail`、`ReplyMore`、`ReplyHaiku`、`ReplyModel`、`ReplyAttach`、`ReplyAttachErr`、`ReplyDT`、`ReplyDark` を開き、対応する盤面画像と見比べた。通常／実行中／送信中／起動中、強い権限、Haiku、モデルシート、添付、狭幅、Dynamic Type 最大、ライト／ダークを確認した。入力欄の面は iOS 26 がガラス、iOS 18 が素材面＋枠線になった。
- `ReplyModel` は検索欄・エージェント見出し・閉じる操作の位置を合わせた。撮影時に出ていた「ビューがウィンドウ階層にない状態で表示しようとした」警告は、撮影用ホストが画面に載った後にシートを開くよう変更して解消した。添付エラーは見本では 2 行、今回の 428pt 画像では 1 行になったが、仕様の 1〜2 行に収まる。
- `ReplyTyping` の入力例は見本と同じだが、カード内の折り返しで 1 文字だけ行末が異なる（見本は 2 行目が「だけ」で終わり、今回の画像は「教」まで入る）。撮影用画面ではキーボードを開いていないため、その領域は見本と異なる。親画面のヘッダー／背景も盤面と同一ではなく、比較対象は入力欄とその直近の表示に絞った。
- `ReplyMore` の開いたメニューと強い権限アラートは撮影していない。OS 標準のメニュー／アラートを開く操作は合成していない。新規チャット全体、使用量リング、承認／質問カードは後続段階のため今回の画像範囲外。

画像: `.verification/ios-redesign/stage4-input-20261017/snapshots/Reply*-*ios26.png` と `Reply*-*ios18.png`（各 15 枚）。見本は `.verification/ios-redesign/design-boards/`。検証ログは `.verification/ios-redesign/stage4-input-20261017/logs/`。

### 検証

変更前の `swift test --package-path ios/Packages/PhloxKit` は XCTest 384 件、Swift Testing 572 件・98 スイート成功、exit 0。変更後は XCTest 378 件、Swift Testing 587 件・100 スイート成功、失敗 0、exit 0。XCTest が 6 件減ったのは削除した `DSChatInputBar` 専用テスト、Swift Testing が 15 件増えたのは上記の新しい契約テストによる。

| 検証 | 結果 | ログ |
|---|---|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | XCTest 384 件・Swift Testing 572 件 / 98 スイート成功、exit 0 | `logs/verify-s3-swift-test.log` |
| 変更後 `swift test --package-path ios/Packages/PhloxKit` | XCTest 378 件・Swift Testing 587 件 / 100 スイート成功、失敗 0、exit 0 | `logs/swift-test.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | exit 0 | `logs/generate.log` |
| 指定 `xcodebuild build`（PhloxMobile・generic iOS Simulator） | `BUILD SUCCEEDED`、exit 0 | `logs/build.log` |
| 描画テスト・iOS 26.2 | 3 件・2 スイート成功、exit 0。入力欄画像 15 枚 | `logs/snapshot-ios26.log` |
| 描画テスト・iOS 18.3.1 | 3 件・2 スイート成功、exit 0。入力欄画像 15 枚 | `logs/snapshot-ios18.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | exit 0 | `logs/lint.log` |
| `rg -n '#available\(iOS 26' ios --type swift` | 4 件。すべて `DesignSystemIOS` の共通部品、exit 0 | `logs/availability.log` |
| `git diff --check` | exit 0 | `logs/diff-check.log` |

途中で `PhotosPicker` の旧引数、iOS 18 のテーマ初期化、添付 0 件の範囲、条件分岐の戻り値でビルド／描画が失敗した。該当 API・初期化・範囲・戻り値を直した。また、最初の package test は `textInputAutocapitalization` が macOS で使えずコンパイル失敗したため、iOS に限定して再実行し成功した。最初の lint は入力欄の生フォント値を検出したため `DSFont` トークンに集約した。Dynamic Type 最大では指定サイズが OS でも拡大されていたため、トークンを固定サイズとして扱うよう修正した。入力欄幅の Preference 警告は `onGeometryChange` に置き換えて消えた。最初の `generate` は環境変数の渡し方が誤って exit 126、`env PATH=…` に直して exit 0。スナップショットの最初の起動も `PATH=…` を実行ファイルとして渡したため exit 126（`File name too long`）でテストを開始できなかった。`env PATH=…` に直して両 OS の最終実行は成功した。

最終描画ログには両 OS で push 登録時の `aps-environment` entitlement 不足が各 1 件、iOS 26 で `BottomAnchorMaxYKey tried to update multiple times per frame` が 1 件、iOS 18 で `Modifying state during view update, this will cause undefined behavior.` が 19 件残った。iOS 26 の起動計測に関する `Failed to send CA Event` は 2 件記録された。iOS 18 の SwiftUI 警告は途中の 38 件から 19 件に減ったが、残りの発生元は特定できていない。Xcode build・lint・generate の最終ログに失敗はない。XCUITest・文字入力／操作の合成は行っていない。共有の `macos/Packages/DesignSystem` と `AgentDomain` は変更せず、コミットもしていない。

## 2. 使用量のリング

### 変更

- `AppRoot` に使用量用の `UsageViewModel` を 1 つ置き、セッション詳細・新規チャット下書き・一覧へ環境値で渡す。入力欄が見えるとき、アプリが前面に戻ったとき、一覧の引っ張って更新で取得する。3 秒ごとの一覧更新には使用量を含めない。
- 成功値をアプリ内で保持し、取り直し中も表示を残す。失敗時は前の値を古い値として残し、取得時刻を表示する。初回取得前・0 件・前の値がない失敗では行を出さない。
- `UsageRingPresentation` に残りの計算、Claude Code → Codex → Cursor の枠順、20% 未満の注意判定、リセット書式、吹き出しと VoiceOver の文言をまとめた。`UsageRingRow` は入力欄の下に 44pt のボタンを置き、押すと 300pt の OS 標準ポップオーバーを開く。
- 使用量行をセッション画面と現在の新規チャット下書きに接続した。入力欄の下にあったターンのコスト・コンテキスト行は外した。ターン使用量のデータと書式は段階 6 用に残し、最後の返答の下の表示は段階 6 で実装する。
- 見本用に通常・注意・部分欠損／取得不可のデータを追加した。スナップショット用の会話・入力欄の本文も `UsageNormal`・`ReplyRunText` の盤面に合わせた。
- 前半で見つかった 428pt の `Accept Edits` 省略を修正した。`cmpVals` と同じ幅判定を保ち、チップ本文を固定幅で切り詰めず、チップ・余白・停止／送信ボタンを含む見積もりを更新した。

### 削除

- 使用量タブ専用だった `UsageViewModel.isEmpty`・`isUnavailable`・`formattedUsedPercent`・`resetsAtLabel` と、一覧 ViewModel が持っていた `cliUsage`・`cliUsageError`・`refreshCLIUsage` を削除した。
- 入力欄の下に誤って置かれていた `$0.42 · コンテキスト 22%` を削除した。
- 旧 `UsageViewModelTests` 10 件（`loadFetchesCliUsageAndPopulatesAgents`、`okStateExposesBucketsAndUnavailableStateFlagsUnavailable`、`loadFailureSetsFailedState`、`isEmptyOnlyWhenLoadedWithNoAgents`、`isEmptyFalseWhenLoadedWithAgents`、`formattedUsedPercentClampsAndRounds`、`resetsAtLabelNilForMissingDate`、`resetsAtLabelRelativeWithin24Hours`、`resetsAtLabelAbsoluteBeyond24Hours`、`resetsAtLabelPastShowsResetDone`）を削除し、新しい表示・取得契約を検証する 10 件に置き換えた。

### テスト

- `UsageViewModelTests` の 10 件で、残りの丸め・0% の最小弧・20% 未満の判定・枠順・リセット書式・吹き出し文言・VoiceOver 文言・取得前／0 件／失敗後の行表示・前値の保持・取得中の重複呼び出し抑止を確認する。
- `DSInputBarLayoutTests.runningReply428KeepsFullAcceptEditsChip` を追加し、本文あり・実行中の 428pt でも `Accept Edits` を省略しないことを確認する。`SessionListViewModelTests` に引っ張って更新で使用量も取得するテストと、3 秒間隔の一覧購読では使用量を取得しないテストを追加した。
- `DesignSnapshotRenderTests` に 9 場面（`UsageNormal`・`UsageLow`・`UsageNa`・`UsageStale`・`UsageRefresh`・`UsageNormalDT`・`UsageNormalDark`・`UsagePop`・`UsagePopDark`）を追加した。ポップオーバーはライト／ダークとも撮影できた。

### 見本との見比べ

出力した iOS 26.2／18.3.1 の `UsageNormal`・`UsageLow`・`UsageNa`・`UsageStale`・`UsageRefresh`・`UsageNormalDT`・`UsageNormalDark`・`UsagePop`・`UsagePopDark` を開き、対応する盤面と見比べた。ロゴとリングの順、18pt の通常リング、Dynamic Type 最大の 30pt リングと 2 行配置、残り 20% 未満の注意色、取得不可の空リング、時刻表示、吹き出し内の枠・残り・リセットの並びと値は揃った。ポップオーバーは両 OS で撮影できた。`ReplyRunText` も再撮影し、428pt の `Accept Edits` 全文表示と見本の本文を確認した。

残る差はスナップショットの親画面にある。描画テストは入力欄と使用量行を切り出す簡易ホストのため、見本のセッションヘッダーがなく、ライト背景は見本の薄いグレーに対して白い。比較対象のリング行・吹き出し自体にはずれがない。会話、入力欄の本文、ターン使用量の行は見本に合わせている。

書き出し先は `.verification/ios-redesign-usage-ring-20261017/snapshots/`。例: `UsageNormal-428x926-light-ios26.png`、`UsageNormal-428x926-light-ios18.png`、`UsagePop-428x926-light-ios26.png`、`UsagePopDark-428x926-dark-ios18.png`。同じフォルダに 9 場面それぞれの両 OS 版がある。

### 検証

| 検証 | 結果 | ログ |
|---|---|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | XCTest 378 件、Swift Testing 587 件・100 スイート成功、exit 0 | `.verification/ios-redesign/stage4-input-20261017/swift-test-final-18.log` |
| 変更後 `swift test --package-path ios/Packages/PhloxKit` | XCTest 379 件、Swift Testing 588 件・100 スイート成功、失敗 0、exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/swift-test.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | xcodegen 成功、exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/generate.log` |
| 指定 `xcodebuild build`（PhloxMobile・generic iOS Simulator） | `BUILD SUCCEEDED`、exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/build.log` |
| 描画テスト・iOS 26.2 | 3 件・2 スイート成功、exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/snapshot-ios26.log` |
| 描画テスト・iOS 18.3.1 | 3 件・2 スイート成功、exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/snapshot-ios18.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | 生フォント値 0 件、exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/lint.log` |
| `git diff --check` | exit 0 | `.verification/ios-redesign-usage-ring-20261017/logs/diff-check.log` |

途中の検証失敗は修正した。最初のテスト編集はテスト用 initializer と期待値が一致せず失敗し、直した。`--filter UsageRing` の診断実行は 0 件を選んだため結果に使わず、パッケージ全体を再実行した。最初の lint は `UsageRingRow.swift` の固定フォント値を検出したため、iOS 用 `DSFont` の `iosCaption`／`iosCaption2` に置き換えた。最初の単体テスト再実行では caption token の未定義と共通 `DSFont.caption` との名前衝突がコンパイルで見つかり、iOS 専用名に直した後の 379 件・588 件はすべて成功した。最初の `UsagePop` 描画には失敗時の古い値バナーが出たため、吹き出し用 fixture を成功状態にして撮り直した。

スナップショット実行時の警告も記録する。iOS 26.2 は `BottomAnchorMaxYKey tried to update multiple times per frame.` と `IOSurfaceClientSetSurfaceNotify failed e00002c7` が各 1 件出た（前者は段階 4 前半のログにも記録済み）。iOS 18.3.1 は `Modifying state during view update, this will cause undefined behavior.` が 28 件、`CGGStackRestore: CG GState restored too many times` が 26 件出た（両方とも前半のスナップショットログにも記録済み）。両 OS で push 登録は `aps-environment` entitlement 不足、localhost `::1:8765` は connection refused。iOS 18 では Xcode が複数 destination の先頭を使う警告も出た。これらのログがあっても描画テストは両 OS とも成功した。XCUITest と文字・タップ操作の合成は実行していない。共有の `macos/Packages/DesignSystem` と `AgentDomain` は変更せず、コミットもしていない。

## 検証（段階 4 の差分全体。検証の担当 Codex gpt-6-luna high が実行。コードは変えていない）

| 検査 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | XCTest 379 件・Swift Testing 588 件成功、失敗 0・skip 0、exit 0 |
| `make -C ios generate`・`xcodebuild build`（PhloxMobile・PhloxWidget） | exit 0 |
| `make -C ios snapshot`（iOS 26.2・iOS 18.3） | どちらも 3 件成功、exit 0 |
| `make -C ios lint`・`git diff --check` | exit 0 |
| `rg -ln '#available\(iOS 26' ios --type swift` | 2 ファイル（DesignSystemIOS の共通の部品だけ） |

警告（テストは通った）: iOS 18 で `Modifying state during view update` 28 回・`CGGStackRestore` 26 回（原因は未特定。段階 6 でセッション画面を作り替えるときに見る）、iOS 26 で `IOSurfaceClientSetSurfaceNotify failed` 1 回、両 OS で `::1:8765` への接続の失敗の記録 1 回ずつ。XCUITest は走らせていない。
