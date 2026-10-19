# 段階8b 統合後の限定修正

追加compile修正: 最新unitはテスト実行前にDSDisclosureHeightModifierのAnimatable準拠で停止した。ViewModifier由来のMainActor隔離をanimatableDataへ推論したことが原因。補間値はCGFloatのみでUI状態を参照しないため、既存DSSidePane.DSPanePresentationと同じくanimatableDataをnonisolatedに宣言する。bodyのUI隔離は保持し、@preconcurrency/unchecked/設定緩和/テスト変更は行わない。再実走は専任へ渡す。

ADR0038差分結果: 共通Viewの遅延builder＋高さのみの挿入/削除transitionとToolGroupの明示guardを適用した。10callerを検索点検し、閉時のslice/コピー/詳細行/tree構築は遅延closure内にある。元CommandGroupRowWindowTestsは無変更、新counter回帰1件を追加。既存寸法テストは親幅proposalを明示し、幅/高さの期待を維持した。git diff --checkのみ実施し、新unit/lint/iOS compile/link/実開閉描画は未実走で統合GO待ち。

ADR0038回帰の根本修正計画: 全数unitはXCTest398件pass、Swift Testing660件pass/1件fail。DSDisclosureContentのinitがcontent()を即評価し、閉ToolGroupのrowsSliceを構築してしまった。元CommandGroupRowWindowTestsと期待は維持し、callerのif isExpandedを復元する。共通Viewもbuilderを遅延保持し、展開body内だけ評価する。高さだけのAnimatableModifierによる挿入/削除transitionで.25/RM即時を保ち、opacity/本文scale/slideを加えない。共通化した7経路を含む全callerで閉時の重い子構築を止める。閉時に自然幅を測るため本文を構築することも避け、幅は親proposalを使用する。既存共通Viewテストの120pt幅条件は明示親proposalとして与え、幅/高さの期待値は維持する。新たにbuilder呼出回数で閉時未評価/開時評価を検査する。実走は統合GO後。

追加DI承認: C1の本物timeout→retry検査向けにconnectTimeout（既定20秒）と既存ConnectionConfigStoring（既定UserDefaults実装）を内部initへ注入する。既存環境にconfig口がないため、別の環境構造を増やさず既存protocolを直接受ける。短いdeadlineを指定してもrefresh・list state判定・makeConnectFailure・実retry callbackは本番経路を使用する。既定poll間隔1200ms/採用C1コピー/通常起動は不変。テスト結果固定や偽成功分岐は追加しない。

AppRoot実遷移検査のDI契約: 内部initializerに任意のAppModel/NavigationRouterを受け取り、指定がなければ既存UITestingNavigator/設定による初期化を維持する。明示modelは認証既定値とbootstrap初期config/reachabilityで上書きせず、以降の本物reachability stream・pushルーティング・接続表示を通す。テスト用の固定成功分岐やタイムアウト改変は追加しない。RootTransitionTestsは別担当所有で、この実rootをhostして観測する。実走は親統合GO後。

AC2-8追加修正計画: SessionDetailFileChangeCardの「セクションをコピー」は本文側に44pt操作領域の保証がなかった。Buttonの実labelへ最小幅/高さDSTouch.minSizeと矩形contentShapeを付ける。右寄せ・文言・コピー原文・自然な折返しは維持する。単純なレイアウト修正なので実装を写すunitは増やさず、統合後の実UI/AX操作領域確認へ渡す。今回は差分確認のみで実走しない。

## 追加契約: ロック中の接続表示

AC3-7連携の追加契約: AppRootは再接続処理中のprivate Stateを持ち、await開始前のguardで連打を抑止し、deferで終了時に戻す。refreshとcurrent取得が終わるまでAppShellへisReconnectingを渡す。AppShell本体の自然高/スピナーは別担当所有で、本担当は編集しない。通常時の文言/配置は維持。統合後は制御可能なrefreshを保留してspinner可視・連打でAPIが1回・成功/失敗後に操作復帰することを実UIまたは統合fixtureで確認する。現時点ではこの操作検証は未実施で、private View stateをテスト用に公開しない。

差分結果（未実走）: 詳細5経路と一覧2経路を高さonlyの共通Viewへ接続し、state全体を包む一覧のwithAnimationを除去した。共通Viewは複数childを1つに束ね、copy行欠落を防ぐ。接続円弧は.9周期、RM時paused/角度0、failure切替animationもRM時nil。登録追加はDSDisclosureContentTestsのmultipleChildrenPreserveFullContentHeight/connectionSpinnerPeriodAndReducedMotionとAppModelTests.testLockHidesConnectingOverlayWithoutDiscardingPendingOrFailedConnection。AppRootは実使用guardをshowsConnectingOverlayへ変更し、接続状態は保持する。git diff --check後、unit/lint/iOS compile/link/描画/実OS RMは親統合GOへ引継ぐ。

AC3-9の起動ゲート優先を実使用guardで保証する。backgroundでFace IDがlockedになった場合、接続中または失敗のoverlayを隠し、接続タスク・失敗情報・待機秒数は破棄しない。AppModelの`showsConnectingOverlay`をAppRootが参照し、再unlock時は継続中の状態を再表示する。登録回帰は接続中/失敗の両入力をlock→unlockし、表示条件と状態保持を検査する。全体のnative alert/sheet排他まで検証済みとは扱わない。テスト/ビルドは親統合GO後。

## 計画と範囲

- 統合済みの他担当差分を保持し、`IOSColor`、`DSCodeBlock`、一覧の投影・専用テスト、`UsageRingRow`、`NewChatView` だけを必要に応じて修正する。
- Chat の色、コードコピー、attention のみの一覧、使用量の取得時期と最大文字サイズ、作成中・失敗表示を、実コードと採用見本で照合する。
- AC の文章と見本・採用済みカタログが衝突する箇所は、古い表示へ戻さず根拠を報告する。
- テスト・ビルド・シミュレータは専任検証へ引き継ぐ。この担当はコード確認と `git diff --check` を行う。

## 結果

| 項目 | 結果と根拠 |
| --- | --- |
| Chat 背景 | `IOSColor.swift:59` の `bg.code` を #E9E9EE / #1C1C1E へ変更。`Chat.dc.html:709,724` の `codeBg` が正本。同見本の吹き出し:35、コード:49、出力:96,117,132で共用している。実装の利用先も `DSCodeBlock.swift:57`、`SessionDetailUserMessageBubble.swift:37`、`SessionDetailCommandOutputView.swift:25` の3用途だけであり、無関係なカード色には波及しない。`DS.dc.html:422` の古い値との文書不一致は親へ報告する。 |
| AC-8-4 コピー | `DSCodeBlock.swift:31-35` を日本語の `Label` と最小44ptの領域へ変更。既存のコピー処理、等幅・シンタックス色・横スクロールは維持。 |
| AC-4-4 attentionのみ | 監査の仕様文章との差は事実だが、`List.dc.html:390-392` は対応待ち欄だけを表示する。`SessionGrouping.swift:156-158` の空roots除外を維持し、`SessionGroupingTests.attentionOnlyProjectsLeaveOnlyTheAttentionSection` を追加した。親が AC の文章を見本に合わせて補正する方針を確認済み。プロジェクトへセッション行を重ねない AC-4-3 も維持。 |
| AC-4-17 | 下部の再接続帯の要件として扱い、カードへ操作を追加しない。 |
| AC-4-18 | 仕様:146の「HTTP番号はカードに出さない」および `List.dc.html:405-408` と、仕様:340の技術値を最後に表示する規則・`Errors.dc.html:119,124`（F1/F4）のHTTP技術値は衝突する。段階8aのカタログ採用を維持し、`SessionListView.swift:671-675` の等幅技術脚注は変更しない。親が見出し・本文には出さず技術脚注に出す旨へ文章を補正する。 |
| U-7 / AC-7-5 | 欠落仮説を反証。`AppRoot.swift:110-112` で前景復帰時に共有 usage の `load()` を実行する。新規画面は `NewChatView.swift:87-90`、詳細画面は `SessionDetailView.swift:212-214` で入力欄のある画面を開いた際にも取得する。一覧の3秒ポーリングへは追加しない。`UsageViewModel.swift:61-63` に同時取得の抑止がある。重複するライフサイクル処理は追加しない。 |
| AC-7-7 | `UsageRingRow.swift:90` で最大Dynamic Type（accessibility5）では3組1行の候補を外し、Claude+CodexとCursorの2行を第一候補へ変更。`UsageRingPresentation.swift:53` がClaude/Codex/Cursor順を固定する。**最大サイズで2行になる条件は、Claude+Codexの必要幅以上あること。** それより狭い幅では既存の各1組3行へ逃がす。ほかの文字サイズでは既存の3組1行→2行→3行の選択を維持。リングの上限30pt（`UsageRingRow.swift:85`）・拡大ラベル22pt（`DSFont+IOS.swift:63-65`）は統合済み。375/428ptの最大サイズでの描画確認を専任担当へ引き継ぐ。 |
| AC-5-12 | 3行同時表示は `Draft.dc.html:34-36` の見本どおり。`NewChatView.swift:133-168` は同じ3行を表示する。「順に出す」という文章は見本と衝突するためコードは変更しない。 |
| AC-5-13 | `NewChatView.swift:287-306` は採用済みカタログの題・原因・次の操作・技術値を表示する。`Errors.dc.html:128` のF7と整合し、古い赤い1行の文章要件とは衝突する。段階8aの決定（`0028-ios-redesign-stage8-worklog.md:15`）を維持し、親が文章を補正する。 |

## 確認範囲

- 品質設定は `ios/Makefile`、`ios/project.yml`、`ios/scripts/lint-raw-values.sh`、`ios/Packages/PhloxKit/Package.swift` を確認した。このcheckoutの `.github/workflows/` にiOSのCI設定はなく、`pages.yml` のみ。
- `git diff --check` は終了コード0。
- テスト・lint・ビルド・シミュレータ描画・コピー操作の実走は未実施。専任検証担当へ引き継ぐ。
- この担当はプロセスや使い捨て検証物を作成していない。コミット・マージ・push は未実施。

## 追加計画: 写真Pickerの混在選択

- `0029-ios-redesign-8b-attachments.md` の担当外連携事項を引き取り、DSInputBarから各画面・ViewModelへ選択順の `Result<SendAttachment, Error>` を渡す。成功と読込失敗を別コールバックへ分離しない。
- 既存の画像だけを渡すAPIは維持し、共通の受理ループで失敗位置・最初のエラーと有効画像の採番を保つ。ダミーDataを作らず、共有AgentDomainは変更しない。
- 読込失敗の前後にサイズ・寸法・有効画像を混在させ、両ViewModelへ値を渡す登録テストを追加する。実走は専任検証へ引き継ぐ。

### 追加結果

- `DSInputBar.swift:478-483` は写真の選択順を `.ordered` で要求する。`:1259-1275` は各選択の成功・読込失敗・Dataなしを `Result` として順序を保って1回通知する。失敗をboolへ集約する別コールバックは除去した。Dataなしは `invalidImage` の失敗値とし、偽の画像Dataは作らない。
- `NewChatView.swift:241` と `SessionDetailView.swift:416-418` が同じ結果配列をVMへ渡す。`NewChatViewModel.swift:360` と `SessionDetailViewModel.swift:297` の受理は、読込失敗をA5としてその位置で記録し、後続の成功・失敗で先のエラーを消さない。成功値だけを既存の枚数・サイズ・寸法検査と採番へ通す。プレビューのdetached生成、元画像と既存キャッシュ、本文の保持は維持した。
- 既存の `[SendAttachment]` 入力APIは成功値へ写して同じ受理処理へ渡す。独自の共有型やテスト専用状態は追加せず、共有AgentDomainのsource/testは変更していない。
- `AttachmentIntakeTests.swift` に `pickerLoadFailureKeepsSuccessfulImagesAndFirstError`、`pickerEarlierSizeErrorSurvivesLaterLoadFailure`、`pickerEarlierDimensionErrorSurvivesLaterLoadFailure`、`pickerOnlyLoadFailuresPreserveExistingDraft` を追加（新規/詳細Pickerの2経路）。実際のPickerと同じoctet-streamの成功値と読込失敗値を受理側へ渡し、画像だけの受理・形式の正規化・元Data・既存添付・採番・本文・最初のA2/A4/A5を検査する。
- 既存 `restoredTotalOverflowSkipsOnlyImageThatDoesNotFit` は読込失敗あり/なしの2入力へ拡張し、先に起きたA3が後の読込失敗に上書きされないことも検査する。
- 変更後の `git diff --check` は終了コード0。追加テスト・型チェック・ビルド・lint・写真ライブラリUIを含む実走は未実施。専任検証が最新差分を取り込んで実行する。

## 追加計画: 正本テスト入口のscratch対応

- `git diff HEAD..dev -- macos/scripts/run-swift-tests.sh macos/scripts/tests/run-swift-tests-output.test.sh` を確認した。devの `SWIFT_TEST_SCRATCH_ROOT` 対応だけを主featureへ取り込む。
- 絶対パスの検査、パッケージ別scratch配列、test/build/bin-pathへの伝播を取り込む。Assets.car既存時のスキップ判定変更は取り込まない。
- 既存スクリプトの回帰検査へ空白を含む絶対パスの3経路・パッケージ別分離・相対パス拒否を追加する。実走は専任担当へ引き継ぐ。

### scratch対応の結果

- `macos/scripts/run-swift-tests.sh:36-40` に絶対パス検査、`:119,131,134` に3経路へのscratch引数伝播、`:147-148` にパッケージ別引数をbackportした。Assets.car既存時にreturnする従来の判定（`:136`）は維持。
- `macos/scripts/tests/run-swift-tests-output.test.sh` の既存Swiftテストダブルで実際のargvを記録し、空白を含むルート配下のAgentDomain/DesignSystem各パッケージへbuild-tests/bin-path/testが分かれることを検査する。相対パス指定時はSwiftの起動前に失敗することを検査する。資源カタログ再生成に関するdevの別変更は取り込んでいない。
- `git diff --check` は終了コード0。スクリプトの実走は未実施。親と専任検証担当へ編集完了を通知した。

## 最終撮影統合の計画

- 撮影用コードだけを変更し、Dim3場面を8001px画像の実際の追加、Totalを正式なrecovery入力と20MB画像の実際の追加で復元する。旧 `attachmentLoadFailed` 呼び出しを選択結果の公開APIへ追従する。
- ListCollapsedの非対応待ち行を実ドメインの未読完了3件へ合わせ、C-19に従いエラーは対応待ちへ残す。SEのsafe area/標準バーは再描画前に補正せず最小確認計画を記録する。
- 別途許可された共有 `ChatRenderKitTests.swift` の1テストだけをthrowsと非Optional取得へ修正する。製品ソース・PhloxKitのsource/testは変更しない。

### 最終撮影統合の結果

- `DesignSnapshotRenderTests.swift:538-585` の4場面の除外を撤去。A4は実8001×1 PNGの追加、A3は正式なrecoveryで70MBの元PNGと小画像2枚を復元後に20MBの有効PNGを追加して発生させる。A3は追加前エラーなし・拒否後既存添付保持も検査し、期待文言だけの偽状態にしない。通常4×20MBで合計超過しない事実はfixtures記録に明記した。旧読込失敗の公開API呼出も選択順Resultへ追従した。
- `AppEnvironment+UITesting.swift` のlistCollapsedだけ、隠れたwrite-unit-testsとadr-0044を完了未読へ変更。routing-tableの既存完了未読と合わせて未読3、refactorとproxy-testsで実行中2となる。C-19により対応待ちのRoseは内訳から除くため、見本のエラー1は作れない。根拠は `List.dc.html:308-315` がすべてのunreadフラグ・errorを数える一方、仕様C-19（redesign-2026-10.md:396）と実投影は表示行・子孫のdoneUnreadのみを数えること。仕様変更の保留にはせず、決定済みの数え方で撮る。
- SEタブ切れは推測修正なし。iPhone16のscene上の375×667仮想windowと、375×667のSE3実sceneの差を狭幅sceneだけ比較する計画をfixtures記録へ追記し、専任担当へ共有した。
- 共有 `ChatRenderKitTests.swift:noNewlineMarkerDoesNotAdvanceNumbering` はthrowsと `try #require(lines.first(where:))` へ変更。原文一致・表示対象外・旧/新の採番検査を維持して、Optionalを曖昧に残さない形とした。
- `git diff --check` は終了コード0。撮影test source安定を専任へ通知済み。ビルド・テスト・撮影は未実走。

### 初回PhloxKitコンパイル診断の修正

- 親から初回のコンパイル失敗（テスト本体未実行）の連絡を受け、`SessionDetailReplyApprovalTests.swift` の成功完了入力を `.completed(exitCode: 0)` へ修正した。後続のOptional取得とacceptの型文脈にキャストを加えず、元の検査を維持した。
- `AttachmentIntakeTests.swift` へ `import ImageAttachmentKit` を追加し、`Package.swift` のFeaturesTestsへ同productの直接依存を明示した。撮影テストも同moduleのimportを明示した。
- UIの型に触る `DSReasoningTextWhiteboxTests` をMainActorへ隔離し、非isolated同期テストからの呼び出し警告の原因を修正した。期待値や製品コードの隔離は変更していない。
- source/testの編集安定と再実行可能を親・専任へ通知した。`git diff --check` は終了コード0。この担当による再コンパイル・実走は未実施。

### 再実行後の旧fixture・色契約修正の計画

- `testImagePreparationFailureUsesA5CopyAndKeepsDraft` の破損画像は受理時に拒否されるため、正式なrecovery入力へ変更し送信準備失敗の意味を維持する。A5・本文・添付保持を弱めず、API未送信も検査する。
- TokensTestsのbg.code 3期待だけを、採用済みC-20と独立したChat.dc.html:705/709/724の会話共通パレットへ合わせる。他トークンは変更しない。テスト実走は専任担当へ引き継ぐ。

修正結果: 上記2ファイルの対象箇所だけを変更した。A5の既存3アサーションを維持し、復元した添付の同一性とAPI sendCount=0の検査を追加した。bg.codeはライト#E9E9EE・ダーク#1C1C1Eを見本の独立した値から検査し、各期待のコメントにC-20とChat705/709/724を記載した。製品source・撮影sourceは変更していない。`git diff --check`は終了コード0。こちらのテスト再実走は未実施。

### iOS専用Picker経路の依存宣言

- 最終iOSビルドで、Macの条件付きコンパイルでは対象外だった `DSInputBar.swift` の `ImageAttachmentPreparationError` が未解決と判明した。使用元のimportとDesignSystemIOS targetの直接product依存を追加し、型を定義するImageAttachmentKitを明示する。
- 製品挙動・テスト期待は変更しない。今回追加した同エラー型の参照と条件付きコードのimportも検索し、撮影テストと両VMにはimportがあることを確認する。iOS再ビルドは専任担当へ引き継ぐ。

結果: `DSInputBar.swift:4` のimport、`Package.swift:64` のDesignSystemIOS直接依存を追加した。Sources/と撮影テストのImageAttachmentPreparationError/ImageAttachmentPreparer参照は計4ファイルで、それぞれ同moduleのimportを確認した。`git diff --check` は終了コード0。製品挙動・テスト期待の変更なし、こちらの再ビルドは未実走。

### 撮影テストの型スコープ・直接依存

- `snapshot-ios18.log:1108` の実診断は `SnapshotResponseGate` から別型のprivate nested `SnapshotError` を参照したこと。撮影ファイル内で共用するprivateなファイルスコープのenumへ移す。
- ImageAttachmentPreparationErrorは同ログのTesting failed集約行にだけあり、今回のfrontendの位置付き診断にはない。前の `build-app-widget-final.log:300` ではDSInputBarの不足を記録しており、そのimportと依存は修正済み。撮影ファイルのimportも存在する。今回、撮影targetが直接使うImageAttachmentKitをproject.ymlにも直接依存として明示し、間接的な製品依存へ頼らない。
- ビルド・撮影の再実走は専任へ引き継ぎ、型スコープと依存以外の挙動・期待は変えない。

結果: `DesignSnapshotRenderTests.swift:1905` のファイルprivate enumへ移動し、同ファイルの3参照からアクセスできるスコープにした。`project.yml` はAgentDomainの既存ローカルパッケージを明示し、撮影targetだけImageAttachmentKit productを直接参照する。`git diff --check` は終了コード0。再生成・iOS18撮影testのビルド/実走が未実施のため、親と専任へ再検証を引き継ぐ。

### UsagePop実行失敗の修正計画

- `snapshot-ios18-final.log:3092` は準備中のAXボタン探索がnilで停止しており、Popoverの描画は未到達。公開accessibilityElements/countの両方を探索し、key windowとAX形成の待機を整える。本物のAX activation後に実popoverのpresented controllerを検査する。
- `PHLOX_SNAPSHOT_INPUT_SCENES=UsagePop` など入力/Usage群だけを選ぶ限定撮影を追加。不明IDを拒否し、部分実行と明示する。未指定なら従来の全描画を行い、正式な全描画ゲートは残す。
- 警告のread-only調査は別担当が行う。こちらはボタン/Popoverとscene選択だけ修正し、ビルド/実走は専任へ引き継ぐ。

実装結果: `PHLOX_SNAPSHOT_INPUT_SCENES` はカンマ区切りの入力/Usage scene名を受け、不明名・空指定を拒否する。指定時は入力/Usage群の該当sceneだけを撮り、ログに部分実行であることを明示する。未指定の全描画経路は維持。AX探索では公開のaccessibilityElementsとcontainer countの両経路を探索し、3秒上限でtree形成を待つ。prepareWindowありのwindowをkeyにし、終了時に元のkeyへ復帰する。UsagePopはデータありの実使用量行・実AX activation・presented UIPopoverをrequireする。`git diff --check`は終了コード0。検証担当へUsagePop単独再実行を依頼済みだが、本物Popoverの実行成功はまだ確認できていない。

pair監査の再判定は `.verification/ios-redesign-stage8b/visual-pair-triage.md` に記録し、親と画像担当へ通知した。比較6画像を開いた。fade・OS18標準タブ・G1文言は既存設計で説明でき、設定の末尾到達は静止画とコードだけでは確認できないため、公開UIScrollViewのoffset/insetとAX frameを使う最小probeを記録した。製品コードは未変更。

### UsagePop失敗後の診断と独立した表示修正

- 単独probeでもUsageRingRow.buttonはnilで停止しPNGなし。本物Popoverの成功は未確認。待機延長はせず、scene接続/key状態/root controller/UIView階層/公開AXの配列・count・ID・labelを上限付きで出力する診断を追加した。window/scene/screen寸法とsafe areaも記録し、iPhone16（393×852）上の仮想window差を、物理寸法の合う14Plus（428×926）で切り分ける。
- 詳細群は `PHLOX_SNAPSHOT_DETAIL_SCENES=ReplyDT,ReplySE` の限定撮影を追加。Input指定と同時使用は拒否し、不明名・空指定も拒否する。限定実行は全描画成功を意味しない。
- ReplyApprovalCardの単独許可priority0/セッション許可priority1が前者を押し潰すため、不均等priorityを撤去し各操作に44pt以上の幅を確保した。これ以外の語彙・意思決定・動作は変えない。DetailDT実画像の黒い細棒を表示不具合として扱い、代表ReplyDT/ReplySEの再描画が必要。
- 設定エラーは長い採用文言の全文を優先し自然折返し、添付は通常2行・アクセシビリティ文字では必要行まで折返す。AC6-11の「赤い1行」は全文が収まる場合とし、狭幅・大きい文字では折返す決定を仕様へ記載した。無理な縮小はしない。ReplySendingは本文へ予めImageマーカーを入れず、通常の追加操作が採番して挿入するよう修正。ReplyMoreは今回撮影範囲外であり、実装済みMenuの偽shotを追加しない。
- 警告の因果確認用に `PHLOX_SNAPSHOT_LAYOUT_DIAGNOSTICS=1` のときだけDEBUGで2 preference callbackとDSInputBar幅更新の前後markerを追加。共通描画にもsafeArea書込/各layout/待機/ready/prepareの細分markerを追加した。一時診断は調査後に除去する。機能無効化やmaterial撤去はしていない。stateとCGGは別原因として検査する。
- 現時点は編集と `git diff --check`（終了コード0）のみ。製品修正の再描画、AX診断probe、警告原因の確定は未実施。

### 14Plus診断後の根本修正と外部実操作モード

- `usagepop-14plus-layout.log:494-496` でstate警告がnative selection Binding setterの同期State書込内に発生した。setterは非Observableの小さな世代付き配送器へ通知だけを渡し、次のMainActorターンで最新1件を反映する形へ変更した。外部cursor同期でpendingを無効化し、配達時の本文・cursor整合も確認する。TextSelectionの原値とString.Indexを保持し、IMEの本文を解釈・変換しない。cursorの公開も同じ遅延反映内で行い、古い追加Taskに新しい外部cursorを上書きさせない。
- 新規DSInputSelectionDeliveryTestsは即時書込なし/最新選択優先、外部cursorによる取消、本文変更による古いIndex拒否と次選択の受理を登録する。実走は専任へ。
- ReplyDT代表画像は許可の幅は戻ったが2行ボタンが縦圧縮された。決定領域全体へfixedSize(vertical:true)を追加し、可変幅・最小44ptを保ってTextの自然高と余白を背景内へ確保する。本文ScrollViewの途中clipとボタンの重なりは区別する。再描画は未確認。
- 同ログではwindow/screen/sceneが428×926で一致したがsceneはForegroundInactive、UIHostingView以下の公開AX配列/countは0。アプリ内公開AX探索では実ボタンを得られない。待機増加はしない。親が今回専用14Plus Simulatorウィンドウを開き、外部CUAから実AXタップする経路を承認した。
- 撮影専用 `PHLOX_SNAPSHOT_EXTERNAL_USAGE_ACTIVATION=1` ではUsagePop群だけ外部実操作を最大60秒・100msのasync pollで待つ。実presentedPopoverのrequireは維持し、状態の初期trueや本番setterの公開はしない。未指定は既存アプリ内AX経路のまま。
- readyは撮影出力ディレクトリの `<scene>-external-ready.json`。scene/phase/PID/UDID/window/screen/sceneActivationをatomic書込し、stderrもflushする。phaseはawaitingTap→presentedまたはfailedへ更新する。所有は本統合作業、ログは専任検証の出力先で保持する。親のCUA操作と専任のcompact-test開始をreadyファイルで同期する。
- CGG警告はstateと別件で、selection setter後・preference後・幅書込後にも発生している。state修正だけで解消したとは扱わない。一時markerは確認後に除去する必要がある。

外部probeのコンパイル診断追記: Swift6 SDKで利用不可のNSStringFromCGRectをready JSONから除去し、window/screenの矩形を公開CGRectプロパティの[x,y,width,height]数値配列へ変更した。製品コードは変更なし。`git diff --check`終了コード0、再実行は専任へ引き継ぐ。

### 外部Popover成功後の次段撮影準備

- 親・専任から、外部UsagePop実タップでテスト成功、親がPNG上の本物Popover確認、state警告0件、CGGStackRestore3件、タップ後のAXRuntimeCommon `Unknown client: PhloxMobile` 1件と報告された。selection修正の実測裏付けとするが、CGG・AXRuntime警告は未解決であり省略しない。
- `PHLOX_SNAPSHOT_SCREEN_SCENES` の既知IDはSetSE/SetSEDark/ShellSE/ListSE/DraftMoreSE/DraftMoreDT。空・不明IDと他filterの同時指定を拒否する。SE4画面は物理SE3で375×667のみを撮るための限定経路。設定は既存renderPairSettingsSnapshotsを絞り、Shell/Listは本物AppShellView/SessionListViewと既存fixtureで再現する。これでviewportの違う全群を再撮影しない。未指定の正式全描画経路は維持する。
- 第2prepareWindowはDraftMoreSE/DTの本物Menu操作。`PHLOX_SNAPSHOT_EXTERNAL_MENU_ACTIVATION=1` で同じreadyファイル・外部実タップ方式を使い、公開presented controllerをrequireする。成功前提ではなく、Menuが別UIWindowに出る可能性もあるため、ready JSONのphaseごとに可視windows・root/presented controller・levelを記録する。公開検出が成立しなければ失敗として報告し、Menu画像を模造しない。
- `PHLOX_SNAPSHOT_CGG_PROBE` はPlainColor/RegularMaterial/TextField/UIKitPlainの1つだけを指定する明示診断entry。不明値・screen filter併用を拒否し、同じprivate windowImageで428×926・47/34・scale2・light・key windowを揃える。TextFieldは非フォーカス・文字入力なし、UIViewRepresentableは背景色だけ。純色に本文が無いのは診断の意図なので、このentryに限り本文検出を対象外にし、drawHierarchy成功とPNG寸法/書込を検査する。正式sceneの本文チェックは有効なまま。
- CGGの4variantは別々に実行し、差が出たvariantとPlainColorを追加2回ずつ再現確認する設計。Apple内部の原因は断定しない。初回probe・繰返し検証は未実施。製品sourceはパッケージ全体検証中のため安定状態を維持し、今回変更は撮影fileと記録だけ。

検証担当報告: PhloxKit全1041件（XCTest391＋Swift Testing650、追加3件含む）pass・lint pass。ただし新規配送テストの変数textをSendable closure捕捉後に変更する警告が出たため、テストの状態をMainActorの小さな参照型へ置き換えた。本文変更による古い配達拒否・次選択の受理という検査意図は維持し、製品sourceは変更していない。変更後の再実行は未実施、`git diff --check`終了コード0。

SE用fixtureのコンパイル修正: `replydt-final-14plus-corrected.log` は追加したAppShellView呼び出しの必須引数不足でexit65、撮影テスト本体未実行・画像0件である。描画不良の結果とは区別する。既存の一覧Shellと同じ契約でhidesTabBar=false/hidesAccessory=falseを明示し、タブと対応待ちを表示する入力を補った。製品挙動・期待は変更なし。`git diff --check`終了コード0。再コンパイルと撮影実走は専任へ引き継ぐ。

SE3実描画後の追加修正: 通常文字のセッション許可だけfixedSize(horizontal:true)としていた条件を除去し、通常/DTとも横幅は枠内へ折り返す。最小44ptと自然な縦高は維持した。親・専任は停止済みでsource編集再開可を確認してから変更した。`git diff --check`終了コード0、再描画は未実走。

arming撮影待ちの最小案（未実装）: 現在の0.8秒settleはAPI readinessを待つ前で、承認カードが後からmountした場合の0.6秒armingを保証しない。承認を持つ詳細caseだけ、messages/approvalsのreadiness完了→MainActorへyield→ReplyApprovalPolicy.armDelayの実時間待機を行い、その後に既存の0.15秒presentation待ちと描画へ進める。Stateの初期true・arming機能の無効化・色の固定はしない。待機後の公開AX enabledまたは実画像の濃度も親が確認する。描画完了とarm完了は別条件として記録する。

arming案の採用・実装: 詳細fixtureの本物ViewModelでcurrentReplyApprovalが生じたことを、Viewのtaskから撮影専用readinessへ通知する。承認のある詳細case（API approvalsあり、または共有displayStateがapproval）だけ、上限3秒でこの実状態を待ち、yield後にReplyApprovalPolicy.armDelay（0.6秒）を実際に待ってから既存の描画へ進む。APIの返却だけをカード表示完了と見なさない。`[approval arming <case>] real card ready; wait ...begin` と `wait.end` をstderrへ出し、通常shotの証拠として残す。一時layout markerとは異なり、待機機能とこの記録は診断除去後も維持する。waitUntilReadyをasync throwsへし、キャンセルと準備失敗を伝播する。SE横幅修正と同じsource改訂として`git diff --check`終了コード0。実走は専任へ引き継ぐ。

SE3タブラベル診断A: `PHLOX_SNAPSHOT_VIEWPORT_HOLD=1` とSCREEN_SCENES=SetSEまたはShellSEの1件指定で、原条件のままpreDraw後に10秒async保持する。出力dirの`<scene>-viewport-ready.json`へholding/holdEnded/capturedをatomic記録し、window/hosting view/safeArea/additional、公開tabBarのwindow換算frameを出す。製品TabViewとrenderer、fixture固定frameは未変更。詳細はverificationのse-tab-crop-triage.md。コード確認とdiff --checkのみ実行、外部simctl対比は未実走。

A結果後のB: ready JSONを確認し、host375×667に対してtab controller375×677、tabBar.maxY677という実測を得た。additionalSafeAreaは0。親・専任はnativeとdraw両方の切れを確認した。SetSEの最外frameのheightだけを診断env `PHLOX_SNAPSHOT_NATURAL_ROOT_HEIGHT=1` で外すB比較を追加し、他の条件・製品は維持。SetSE単独・viewport hold併用を必須にする。Aは保持してB別出力へ比較を引き継ぐ。diff --check0、B未実走。通常full renderへの適用範囲判断はB確認後。

B正式結果後の通常適用: Bはcontroller375×667/tabBar.maxY667に一致、親・専任がnative/draw双方のタブラベル全文とstate/CGG0を確認した。windowImage呼出15箇所を全検索し、本物画面11経路のうち元から自然高のInput/Usageを除く10箇所へ、最外rootの全高固定除去を適用した（幅のみ維持）。対象はsessionList/Shell基本・派生/List/ListMany/詳細/狭幅Shell・List/Pair/Settings/Draft。Components・CGG静的probe・Widget/LiveActivityの独自キャンバスは保持。製品レイアウトと安全領域・rendererは変更していない。NATURAL_ROOT_HEIGHT診断分岐は削除し、A/B証拠は保存。

一時診断の整理: DSInputBarとSessionDetailViewのlayoutProbe呼出・関数と、markerしか処理しないonChangeを削除した。selection配送器や外部cursor同期は維持。撮影fileに限りbounds/safeArea前後/preDraw前後の5marker呼出とprobe関数を残し、SetSE/ReplyDT再確認後に最終除去する。実arming待機・対象caseログは通常撮影機能として維持する。diff --check0。source安定を親・専任へ通知し、SetSE通常経路のframe再実測とReplyDT（実arming後）表示/CGG件数確認を引き継ぐ。

Claude承認の待機条件修正: ReplyDTの再撮影はpassだが、親・専任が灰色disabledとarmingログ欠落を確認した。前記の「API approvalsあり、またはdisplayStateがapproval」ではClaudeのpending tool permissionを取りこぼした。製品SessionDetailViewModel.replyApprovalsと同じく、PTY/Cursorを除外、CodexはAPI approvals、Claudeはpending userQuestionの共有isClaudeToolPermissionQuestion判定を使う。AskUserQuestionの通常質問は除外する。case名による分岐やState初期値は使わず、本物currentReplyApprovalのreadiness→実armDelay→既存描画の順は維持する。

登録テストapprovalSnapshotWaitMatchesActualViewModelは、Claudeのpendingツール許可・通常質問・回答済み許可、Codex承認、Cursorの5入力を本物VM.load/loadApprovalsへ渡し、承認の有無と撮影待機の対象が一致することを検査する。製品側の判定は変更しない。再描画はReplyDTとReplyCodexでbegin/endログとarming後の実画像を確認する必要があり、この改訂では未実走。

CGG追加診断計画と実装: 先の4primitiveは専任から全0件と報告され、単独primitive原因という仮説は反証された。asset経路の比較のためPHLOX_SNAPSHOT_CGG_PROBEへBrandClaude/BrandCodex/BrandCursorを追加した。DesignSystemの実AgentBrandIcon(kind:size:)を22ptで単体表示し、Cursor専用iOS外枠等の別描画を混ぜない。既存と同じwindowImage・画面寸法・light・描画検査を使い、製品asset/sourceは変更しない。撮影targetにDesignSystemを直接依存として宣言した。3診断は部分検証であり正式全描画ゲートの代替ではない。追加コードのコンパイル・撮影は専任へ引き継ぎ、実行前に成功とは扱わない。

ブランド診断追加後のリンク調査: brand-arming-14plus.log:909の撮影targetリンクでAgentDomainの型metadata/conformanceとImageAttachmentLimitsが未解決、exit65となりテスト本体未実行。ImageAttachmentKitとDesignSystemはいずれもAgentDomainを依存先とするが、撮影targetはAgentDomainをimport/直接参照しながらproduct依存を宣言していなかった。生成pbxprojの撮影FrameworksはImageAttachmentKit/DesignSystemのみで、実LinkFileListには撮影objectとhostのdebug.dylib、リンクcommandにもAgentDomain.frameworkの直接入力がない。ログではAgentDomain.frameworkが別途生成・依存先productにリンクされており、host経由の間接的なシンボル供給へ依存していた欠落が露呈した。正本project.ymlの撮影targetへAgentDomain productを直接追加する。既存DesignSystem/ImageAttachmentKit依存は保持し、共有package/sourceやNewChatは変更しない。generate後のリンク成功は未検証で専任へ引き継ぐ。

同ログの付随警告はAppIntents metadata extraction skipped（依存なし）、CoreAudioTypes/UIUtilitiesのauto-linked framework未検出、SwiftUICoreへの直接リンクはallowed clientでない、の4件。今回の未解決シンボルとは区別し、解消したとは扱わない。

撮影hostの副作用分離: SnapshotTestsはPhloxMobile.appをTEST_HOSTとして使うが、従来のscheme test actionに-UITestingがなく、fixtureとは別のhost初期化がlive environmentとPushRegistrationServiceを作っていた。既存PhloxMobileApp.initのUITesting分岐はstub environment/service=nil、PhloxAppDelegate.didFinishLaunchingの同guardはLive Activity開始・通知権限要求より前にreturnする。AppRootのUsage取得もこのstub APIへ向く。親が採用した最小修正として、Snapshots.testだけへ-UITestingを明示し、撮影開始時にその起動引数をrequireする。通常run/製品source/各fixtureの状態は変更しない。ログ抑制ではなくhost composition rootの選択を直す。専任から4probe終了・編集再開可を受けて変更し、generate後の起動引数検査/1primitiveのlive副作用不在/実承認待機を再確認する。今回実走は専任へ引き継ぐ。

Cursor最小再現後の比較計画: 親・専任よりブランド単体はClaude0/Codex0/Cursor1のCGG警告と報告され、次はhost分離後baselineを採取した。SnapshotTests専用Assets.xcassetsへ元Cursor SVGと、元からmask/inner clip/outer clip参照属性を各1つだけ独立除去した3素材を置く。defs/path/gradient/viewBox/fill/preserves-vectorは保持する。共有製品素材は変更しない。元SHA256は7dc00bc09f225fcda46cbc9c6b669c69c025a231877d6c17baa6a003f04f02b2。Bundle(for:専用test token)のSwiftUI Imageを実共有componentと同じresizable/scaledToFit/22ptで描く。生成はXML属性単位の削除と構造比較で検査し、差分/hashをverificationへ保存する。

品質比較の採用基準を先に固定する: 同一22pt・light/dark・scale1/2/3のbaseline/候補で最大チャンネル差1/255以内、差分pixel率0.1%以下、外形/透過境界の欠落なし。超過は不一致として報告し、結果に合わせて閾値を緩めない。まず3variantのCGG件数を測り、0の最小候補をbaselineと追加2回確認してから品質比較する。diagnostic entryはCursorAssetBaseline/CursorNoMask/CursorNoInnerClip/CursorNoOuterClip。PHLOX_SNAPSHOT_CGG_SCALEは1/2/3（既定2）、PHLOX_SNAPSHOT_CGG_DARKは0/1（既定0）を診断時だけ受け付ける。正式撮影のscale/themeは変更しない。素材の製品採用は比較結果を親へ報告してから判断する。

生成結果: test-only baseline+3variantの指定1属性以外のXML tree一致を生成時に確認した。hash/元からの独立差分は.verification/ios-redesign-stage8b/cursor-vector-variant-generation.mdへ保存。画像比較の差分pixel率は画面全体で薄めず、22ptアイコンの同位置cropを対象とする。test bundle画像の存在も描画前にrequireする。素材の追加後は正本generateでテストtargetへasset catalogを登録する必要がある。コンパイル/描画/画像一致は未実走。

進捗fixtureの追加: 既存DraftCreating/Darkは採用見本どおりwaitingを維持し、実NewChatViewのcreatingを示すDraftSpawning、sendingを示すDraftSendingを追加した。SCREEN_SCENESでDraftSpawning/DraftSending/DraftCreatingを限定選択できる。別workerのseedProgressForSnapshot(text:waitSeconds:stage:)拡張へ接続し、creating時のhasCreatedSession=false/submittedTextあり/編集不可と進捗ラベルは製品の状態解釈に従う。NewChat製品3fileは当担当では変更しない。このAPIの親統合後に撮影compile可能となるため、source安定通知時に統合依存を明記する。VMの未完spawn回帰は別担当、当fixtureは画面の描画確認を担う。

Cursor比較の次段: 専任・親よりBaseline1/NoMask0/NoInnerClip1/NoOuterClip1件のCGG警告、host分離後ほか警告0と報告された。NoMaskは原因切分けの候補だが、親の既存22pt/2x/light比較で5pixel・最大channel差7となり事前threshold1を超えたため、品質一致とは扱わず製品採用は保留する。RGBA getbboxはalpha差0でRGB差を落とすため、各channel差とany-channel差分maskを使い、率の分母は全canvasでなくアイコンcropとする。

PHLOX_SNAPSHOT_CGG_PROBE=CursorMaskEquivalenceを追加し、同じtest bundleのBaseline/NoMaskをlight/dark×scale1/2/3×22/128ptで逐次24枚出す。各条件で同一のwindowImage・背景・中心配置を使い、variant/size/scale/styleをPNG名とbegin/endmarkerへ含める。ラベルは描かない。特別entryとCGG_SCALE/DARKの併用は拒否する。既存の最大channel差1/255・crop内差分pixel率0.1%の基準は維持し、比較値は親がPillowで算出する。Draft2probe終了通知後に編集、製品/共有素材は未変更。コンパイル・描画は専任へ引き継ぐ。

追加候補CursorAlphaMask: 原本からmaskのstyle属性のmask-type:luminanceをalphaへ1箇所だけ変更したtest-only素材を追加した。ほかのXML tree一致を生成時確認し、hash/diffも同記録へ保存。既存単独CGG entryで先行測定可能であり、同等比較loopにも加えて36枚とした。白い矩形maskでは数学的にalpha/luminanceが同じであることを前提とするが、実レンダリングの一致と警告解消は未検証で製品採用しない。strict thresholdは維持。専任はCursorAlphaMask単独でCGG/既存原本との画素比較を先に試し、その結果から36枚の単一起動比較へ進める。

品質36の結果と次候補: 親のcursor-quality-36-result.jsonによるとNoMaskはstrict4/12条件のみ合格、22pt全6条件は3〜5pixel/最大差16、128pt3xも2pixel/最大差4で不合格。AlphaMaskは画像12/12合格だがCGG12/12件で解消せず。従って同等画質を保つ警告除去は未達で、製品素材採用はしない。次のtest-only CursorNoMaskDoubleClipは、元のg要素のmask参照を同じ矩形の既存clip1参照へ置換する。元のmask定義・外側clip・path/gradient/fillは保持する。既存単体CGG entryへだけ追加し、まず22pt/2x/lightで測定する。警告またはstrict画素基準が不適合なら大型matrixは追加反復しない。今回も製品素材は未変更、閾値は維持する。

正式ゲート前のsource整備計画: 本物MenuDT外部tapが完了し検証プロセス停止後、実験前source/projectとtest-only Assets.xcassetsをverificationのdiagnostic-source-archiveへmanifest付きで退避する。CGG各entry・品質loop・viewport hold/frame JSON・一時layout marker・専用UIKit/token型と診断専用DesignSystem直接import/依存を削除する。本文検出を外すdiagnostic専用引数も除去し、正式shotでは常に検査する。AgentDomain/ImageAttachmentKit直接依存、実arming待機/証拠ログ、外部Usage/Menu readyと実presentation require、部分scene選択/登録テスト/自然高/新Draft状態は維持する。出力先は入口で一度作成し、fresh dirでも先行ready JSONを保存できるようにする。製品Cursor素材はユーザー判断待ちで原本を維持し、CGG警告が残る既知状態を隠さない。

整備結果: diagnostic-source-archive/manifest.jsonへ元source/project/全test-only素材のSHA256と所有を記録してから退避した。上記のCGG/viewport/layout実験入口・helper/marker・専用型を除去し、素材catalogはsourceからarchiveへ移した。DesignSystemの診断専用直接package/importを除去し、AgentDomain/ImageAttachmentKitの直接依存は維持した。入口createDirectoryでreadyの先行書込を修正した。正式shotの本文検出は常時有効、arming/外部実presentation/部分選択/登録テスト/自然高/進捗fixtureは保持。障害時だけの上限付きAX dumpとbody-failure画像は、撮影失敗の一次証拠として継続利用するため保持し、body-failure名へsceneIDを付けて別sceneの上書きを防いだ。製品source内に一時selection/layout markerが残らないことを検索確認した。コード確認とgit diff --checkのみ実施し、generate/compile/正式描画は専任へ引き継ぐ。

最終画像監査で判明した2件の修正計画: ListOffUnknownの再接続帯欠落は製品の状態分岐漏れ。SessionRepository.swift55-64/ADR0027決定3・5によりunknownのまま20秒後にlistState.offlineとなる経路は実在する。AC4-17とList.dc.html428/187-193はこの画面でも下部再接続を要求するが、SessionNavigationStateはunknownを一律accessory=nilにしていた。unknown+offlineだけoffline accessoryへ替え、判定中loading/loaded+unknownはnilを維持する。回帰テストでは判定中から締切後への状態入力と、最後のバッジ保持/古い対応待ち項目非表示を検査する。ShellOfflineのFaceIDオンは撮影入力の誤りで、見本Shell.dc.html47、ADR0017、UserDefaults storeの既定はいずれもオフ。ShellOfflineのInMemory storeだけ明示falseとし他Shellの従来入力は維持する。製品defaultは変更しない。専任の既存artifact描画中につきcompile/testは実走せず、差分完成後にPhloxKit標準全数/lint、iOS compile/link、ListOffUnknownとShellOfflineの再描画へ引き継ぐ。診断退避とCursor原本/既知CGGは変更しない。

Hosted snapshot linkage修正計画: 最終18/26ログでAgentDomainのObjective-Cクラス二重定義10件が判明した。host debug.dylibはAgentDomain.o等を静的所有し、snapshotが別のAgentDomain.frameworkをloadして同じプロセスへ第2コピーを持ち込んでいた。過去snapshot-ios18-finalにも10件あり、今回のSE26/unknown帯が初出原因ではない。以前の警告集計がobjc行を含めていなかったため、警告0の記述はこの10件を含む形に訂正が必要である。詳細根拠はverificationのobjc-duplicate-linkage-triage.md。

AC2-9/2-10監査後の修正計画: 新着追従は80pt条件を維持して0.3秒へ、Reduce Motionでは初回/更新ともスクロール移動をアニメーションしない。ConnectionSettingsSectionの0.9秒回転はRM時停止し文言を維持する。思考/承認差分の独自開閉には、子を実寸配置しLayoutの高さだけを0.25秒補間する小さなDSDisclosureContentを共用し、RM時は即時切替とする。外観はSettingsの設定変更とAppRootのテーマ反映へ0.2秒のフェード用transactionを適用する。削除の0.3秒はSessionList UIが実際のlastKnownSessions ID列の変化へanimation(value:)で適用し、非同期Taskの生成だけを包む実装にはしない。既存DSMotionへ名前付き時間を追加し、スクロール初回/追従/RMの意味ある契約テストを拡張する。他担当のThinkingIndicator/撮影fixtureは変更しない。実走はsource全変更後の専任一括検証へ引き継ぐ。

同じAppRoot所有範囲のC1修正計画（後続確認で撤回）: Errors.dc.html153の次の手1文へ戻す計画を一度適用したが、0029-ios-redesign-8b-pair.md:111に「採用済みPair盤面のチェックリスト形式を維持」の後続採用記録があった。旧NEW-32の判断待ち記録だけを根拠に未承認とした判断は不十分だったため、親の訂正に従い今回のC1変更だけを元の3項目へ復元した。文言体系の一本化は別途仕様判断であり今回行わない。実構成のconnectionEndpoint脚注、motionと他8b差分は保持する。F2 formatterは別担当なので変更しない。

動き/C1の実装差分: DSMotionへdisclosure(.25)/followNewContent(.3)/appearance(.2)/rowRemoval(.3)を追加。DSDisclosureContentは子の実寸を保つLayoutの高さだけを補間し、collapsed時はaccessibilityとhit testingを隠す。思考・承認差分の外/内開閉へ適用し、RM時はanimation=nil。詳細の80pt条件を維持して追従を.3へ、RM時はscrollToを即時にしsendStateの移動transactionも外した。接続テスト回転はRM環境の変更にも追従して停止/再開する。一覧はlastKnownSessionsのID列にvalue animationを付け、await後の実データ更新が届いた際に.3秒で再配置する。外観変更とテーマ更新を.2秒で反映しrootのtransitionはopacity。C1は正本の次の手1文へ戻し、実接続先脚注を保持した。

追加登録テスト: reducedMotionNeverAnimatesFollowingScroll（初回/追従ともRMで移動なし、80/81pt境界維持）、DSDisclosureContentTests.interpolationPreservesWidth（0/.5/1の高さと不変幅を実SwiftUI layoutで検査）、reducedMotionKeepsNaturalEndpoints（RMの開閉終点）。テスト・build・描画は未実走。次の専任gateはPhloxKit標準全数/lint、iOS app/snapshot compile/link/analyze、RM切替時の接続spinner/新着追従/独自開閉、外観fade/実削除後の行詰めを確認する。C1撮影fixtureは別所有に旧checklist seedが残るため親へ連携済み。診断archiveと製品Cursor素材・閾値は変更していない。コード確認とgit diff --check終了コード0のみでsource安定を引き継ぐ。

親承認の最小修正として、SnapshotTestsのAgentDomain/ImageAttachmentKit直接依存を削除せずlink:falseとし、BUNDLE_LOADER=$(TEST_HOST)を通じてhost所有のsymbolを参照する。現artifactではsnapshotの未定義共有symbol13件すべてがhostのglobal exportに存在することをnmで照合した。ただし実リンク成功の代替ではない。[XcodeGen2.45.4公式仕様](https://github.com/yonaskolb/XcodeGen/blob/2.45.4/Docs/ProjectSpec.md#dependency)と[生成実装870–890行](https://github.com/yonaskolb/XcodeGen/blob/2.45.4/Sources/XcodeGenKit/PBXProjGenerator.swift#L870-L890)では、link:falseはpackage productをPBXTargetDependencyに残してFrameworksへの追加だけを外す。共有packageのproduct型や製品Swift/fixture/期待値/画像閾値は変更しない。generate後のcompile-only依存保持、compile/link、最新loadhashの18/26 hosted runtimeで二重定義0件を専任が確認するまで解決済みとはしない。CGG既知警告とは別に数える。

C1復元結果: 上記の一文統一を撤回し、AppRootの次の手「Macで次の3つ…」とsleep/Phlox/Tailscaleの3チェックリストだけを元へ戻した。直前の「動き/C1の実装差分」にあるC1一文復元の記述は一時変更の履歴で、現在は採用済みチェックリストである。motion修正・実endpoint・他担当差分は変更せず、git diff --checkのみ実施した。compile/test/描画は未実走。

開閉テストのcompile修正計画: accessibility-motion-phloxkit.log:42の失敗はmacOSのaccessibilityReduceMotionがread-only KeyPathで、environment書込に渡せないことによる（tests未開始）。OS設定を書き換えず、実Viewが利用するDSMotion.disclosureAnimation(reduceMotion:)へ環境値からの選択をまとめ、RMでnil/通常でdisclosureになる契約を直接検査する。自然な開閉終点と途中の不変幅/高さの実SwiftUI layout検査は維持する。テストの意味はpolicy選択＋layout寸法であり、OSのRM環境を実際に切り替えた操作検証とは主張しない。親許可に従いcompact-test経由で再実走し結果を追記する。

再実走結果: 初回全数は1047件passだが、追加scroll testのMainActor隔離不足警告が24行あった。隣接する既存UI契約テストと同じ@MainActorをtestへ付け、製品のactor回避は行わず再実行した。最終compact-test exit0、XCTest391件/0失敗＋Swift Testing656件/108 suites pass（1047件）、warning/error各0。根拠はverification/motion-disclosure-fix/logs/phloxkit-final.logと同OWNERのPID記録。git diff --check0。今回のcompilerエラーと警告は修正後の全数で解消を確認したが、iOS build/描画と実際のOS RM切替は未実施で専任へ残す。

固定caption修正計画: caption-dynamic-type-auditに列挙された本番Textの固定caption11をiosCaption2（標準11/動的）へ置換し、captionStrongは共有Tokens.swift27のmediumを維持する。既存の明示bold/semibold等もそのまま残す。SF Symbol単独font・preview・shared macOS・InputBar段階指定は変更しない。同型で追加承認されたSessionDetailToolCallGroupRowの「残りN件」も対象。

出力/差分の文脈確認: 監査の「出力全体11」は誤読で、SessionDetailCommandOutputView44の固定captionは操作行だけ。本文は同17のcampMonoCaption（動的12/等幅）であり、AC8-9が個別に等幅12を明示する。差分もChat.dc.html132/740のf.out=12に一致する既存動的campMonoCaptionを維持する。AC2-7一般mono.block13を理由に個別カードの採用12を無条件変更しない。今回は固定Textの動的化だけを行い、技術本文のfont/既定サイズ/等幅を変えない。unit/lintは全source統合後の親GOまで未実走とする。

追加承認された同型箇所: EmptyStateViewの本番説明auxiliary固定12はiosCaptionへ、DSSessionNavigationChromeが使うsessionDetailTitle固定17/semiboldはheadline.weight(.semibold)へ変更する。既定のサイズとweightを維持しDynamic Typeへ追従させる。TokensTests等にこの旧固定定義を要求する期待がないことを検索確認し、テスト期待値は変更しない。fixed symbolとほかのtokenは維持する。

固定font修正差分完成: 承認済み14fileの本番Textを上記どおり置換した。固定captionの残りはConnectionSettingsのchevron1箇所とSessionListのchevron2箇所だけで、symbol用として保持。captionStrongは.mediumを維持し、既存.bold等の呼出側weightも保持した。出力/差分本文の動的等幅12は個別仕様に従い無変更。14fileのSHA256/所有はverification/caption-font-source-hashes.jsonへ保存。git diff --check0、unit/lint/build/描画は親の全source統合GO待ちで未実走。他担当のThinkingIndicator/撮影fixture・shared macOS・InputBar・テスト期待値・画像閾値は変更していない。

最終motion棚卸しの追加契約: remaining-motion-complete.mdへ全候補を分類した。CommandCard/FileChangeCard/ToolCallGroupRow（group/tool子）/TranscriptCards（settled question）の5経路と、SessionListのproject/子開閉を共通DSDisclosureContentへ統一する。既存幅・横scroll・copy原文・showMore・AX identifier・VM状態と親autoFollow80ptを維持し、子をscale/slideさせず高さだけ.25、閉時AX/hitなし、RM即時。共通Viewは複数のcontentも1つのVStackとしてLayoutへ渡し、先頭以外（コピー操作等）を落とさない。独自接続円弧は.9/360度、RM時静止＋文言保持、failure切替のtransactionもRMで無効にする。OS標準ProgressViewの内部周期を独自制御へ拡張しない。具体所有は上記6製品file＋AppRoot/DSDisclosureContent/DSMotion/対応testと本記録。旧viewport説は再利用せず、read-only環境への書込・Actor回避・期待値緩和はしない。実走は親の統合GO後。
