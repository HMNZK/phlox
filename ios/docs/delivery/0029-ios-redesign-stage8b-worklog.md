---
status: active
last-verified: 2026-10-19
---

# 0029: iOS再設計・段階8bの引継ぎと修正

「iOS公開」セッション（9288D076）からCodexセッション（9166D433）が引き継ぐ。基点は段階8aの `0c21a964`。元セッションは利用上限で停止した。前段の承認と仕様決定は維持する。

## 範囲

一覧とナビゲーション、接続と設定、新規チャットと入力欄と使用量、会話、承認と質問カードを分担して修正する。撮影データの取り違えは独立担当にする。既存比較記録は検証対象として扱い、実コード・見本で確認した問題だけを直す。作業用worktreeは `ios-redesign-{list,pair,composer,chat,cards,fixtures}`。

各担当の変更は未コミットの差分として回収し、feature/ios-redesign上で統合検証する。devへのマージと追加コミットは具体的な差分・検証結果を提示して確認する。

## 検証計画

設定済みのiOS lint、PhloxKit単体テスト、アプリとウィジェットのビルド、iOS 26.2と18.3の描画テストを実行する。共有パッケージの変更があれば正本スクリプトでmacOS側も検証する。テストはcompact-test経由、生成物と記録は各worktreeの `.verification/ios-redesign-stage8b/` に保存する。XCUITestは実行しない。

元レビューの指摘は、削除後の404、QRに見本値が表示される経路、撮影用設定値の製品への混入。現コードで確かめて対応する。元レビューの未確認領域（テスト変更・受け入れ基準・資料整合）も確認対象として残す。

## 現況（r44 / 2026-10-19）

現況の正本は [stage8b/NEXT.md](../../../.verification/ios-redesign-stage8b/NEXT.md)。この節は現source・現runの状態だけを記し、旧runは下の時点別履歴と各OWNERで区別する。

r44製品sourceはfreeze中。DSInputBar `9f570f…`、他の製品SHAはac台帳の現source欄を参照。PhloxKit 1,062/108 suites、lint、generic App+embedded Widget、Widget、analyze、BFTは成功。r44 actual SE3 iOS26 targetedは9/9・1 PNGでstrict viewport内のinput/send同時可視を確認。品質gate warning/errorは0、runtime warningとは分ける。511入力manifestはrun前後一致。

iOS26 fullは単一runとして未達。3回目は外部操作取り逃しで8/9・188 PNG・exit65。続く6個のscene限定runは各9/9・1 PNGでUsage 4件のfresh AX proofとmenu 2件のpresentedを確認したが、合算はfull217 passではない。union130/217、未選択87 scene。iOS18 r44 fullは9/9・217 PNG・skip0、Usage 4 proof/Menu 2 presented、live 3 SHA一致。runtime診断はBottomAnchor warning 6件・CGGStackRestore 260行。compiler warning/error 0とは別。

追加suiteは511 manifestのtest-only変更でBFT成功。Additionalは承認済みfixture共有後4/4 pass・14 PNG・skip0・exit0（code/diff左右offset、model/rename両順）。ScrollFollow 79/81は正規runも2/2 fail。native scroll 926、inset47+34、root845、guide0で座標前提が成立せず、追従距離/時間は未計測。追加調査は終了。

Root auto18は8定義/10ケースpass、fopen errno=2が2件（full runではfopen 0）。Root regular18はcompose→Backの2操作が成功した後、scroll操作が画面を動かさず1 fail・exit65。残り3操作は未確認。iOS18 native alert: T2は1/1 pass・skip0・compact0。parameterized runは1定義/3 callerでP3成功、T1/T3はACK timeout（0/1定義pass・1 fail、exit65）。T1の実SE3相当375×667/AX5 alertでtitle上端とcancel下部の文字欠けを親が実見。T2はbutton縦順/可視、説明文はnative scroll内に一部のみ。actual SE keyboard DETAIL runは9/9・skip0・1 PNG・exit0。keyboardGuide (0,407,375,260)、input (28,64.02445,319,144)、send (294,273.02445,68,68)、keyboard表示/firstResponderを確認。誤ったINPUT scene指定の8/9・exit65は成功に含めない。alert再runは追加しない。6複合ACは未確認のまま維持し、AC2-9の押す/戻す/開閉/承認/spinner/外観/削除時間を全体合格へ昇格しない。物理端末・Face ID許可/認証・実push・VoiceOver・IMEは未検証。XCUITestは実行しない。

専用simulator 9台は個別delete後に全ID不在を確認。cache 8 dir計4,240,263,972 bytesをTrashへ移動、r39/build 729,333,428 bytesも移動し内部xcresult 0。永久削除ではなく、r44原本は保持。`remaining/final-build-trash-result.json` を参照。作業treeは未commitで保持し、merge/publicationは未実施。

### r37完了時の検証結果

iOS26 formalは9/9・212 PNG、Root auto8定義/10ケース、regular7-step、native delete AX5が各pass。iOS18 formalは9/9・212 PNG、CGGStackRestore284件。Root auto8定義/10ケース fail/skip0・exit0、regular3-step1/1、native delete AX5 1/1 exit0。両OS delete runは時間が短くlive lsof未採取。18 Large復帰はreadback済み。両OS AX5 buttonは各125.33ptで実行が上、キャンセルが下。親の画像目視では18の説明文は全て可視、26の説明下端はnative本文領域で切れる。button layoutと説明全文の到達は別条件。

AC台帳は133定義/133行/重複0、静的根拠127、未確認6（AC-2-8/2-9/3-2/3-4/3-9/10-5）。r37 Detail AX5 targeted画像4枚とgeometryでは操作欠け/重なりが改善した範囲を確認したが、実scroll・IME・実機操作は未確認。Root finger-panは2 eventが約1.17msでmoved0のため、連続gestureの証拠ではなく製品不具合とも判定しない。Face ID初回許可は未回答、実認証成功・実機・実push・実camera・VoiceOver・IMEも未確認。XCUITestは実行しない。

cleanupはr37時点でexit 0完了。累計27ディレクトリと派生比較PNG 1,404枚を削除し、stage8b/build内xcresult 1件をinode保持で `remaining/preserved-final-build-results/build/Logs/Test/` へ保全。final-cleanup-checkの選別対象であるstage8b自作build/test runnerは0件で、OS全体のprocess不在は主張しない。Simulator計4台を正規CLIで個別削除し、一覧からの不在を確認。記録は `remaining/final-cache-cleanup-result.json`、`remaining/final-cleanup-check.json`、`remaining/final-simulator-cleanup.md`。r38検証環境のcleanupは未実施。空き容量57,478,979,584 bytesはr37 cleanup時点の値。コミット・dev merge・公開は未実施。

## 過去の現況記録（r18以前、現況ではない）

現況の単一正本は [stage8b/NEXT.md](../../../.verification/ios-redesign-stage8b/NEXT.md)。この節以下の過去run記録は当時の履歴であり、最新状態や合否の根拠として読み替えない。

**過去の現況記録（2026-10-19、r22b）:** r22 PhloxKitは1,062 pass・108 suites、failure/warning/error 0。generic app+embedded Widget、standalone Widget、analyze、lint、Snapshot BFTは各exit 0・warning/error 0（BFTは0 testsのbuild確認）。r22b iOS18 Gate Glyphは2/2 pass・36 PNG、親5 scroll ACKと全文OCR、Capsule外白画素0。正式iOS18 r22bは9/9 pass・204 PNG、実load 3 SHAはBFT一致、509 source filesに差分なし。診断はCGGStackRestore 272、Unknown client 1、warning/error 0。Gate Glyph/formal iOS26は未実走。

Root r22b iOS26 all-search-excluded direct-compose controlは1/1 pass・8/8 ACK。2回の実Back後に一覧・tab bar・新規チャットcircleをfresh screenshotで確認し、最終routerDepth 0/native stack 1。初回ACK timeoutは別artifactに保持する。この制御はSearch/circle actionを使わず、Search経由の不具合解消を示さない。r17b/r18/r19/r20 Search経路の失敗を保持し、r21の2 direct push/pop passもUI Backとは区別する。Root lifecycle候補はintegration_fixes適用中・未検証。Face ID許可は未回答のため未許可、本物の認証成功なし。現Simulatorは26のみbooted/Large、18 shutdown/Large。AC 122根拠あり/11未確認、コミット/マージ/公開承認待ちを維持。

**現況の読み方（2026-10-19、r18まで）:** Offline26 r12とOffline18 r16は各24/24の実UI条件をpass。26 test SHA `b819…` は実行済みだがlive lsof未採取。18の24 UUID出力は指定環境変数の出力先ではなく `remaining/offline-runtime/` にあり、PID78054の実行記録と紐づく。Usage26 r11は末尾/先頭のstrict offsetが一致してpass、Usage18はbottom 12pt・top 20pt不足のfailを保持する。26 formal r14は登録9定義すべてpass、204 PNG、製品payload `cae1…` のlive SHA一致。「10件」は誤集計として撤回。現sourceの18 formal fullは一次結果を確認できず未確認。Gate26旧2ケースは成功、Gate18旧host428はpassだがsynthetic375はOCR assertion fail（実PNGでは全文可視）。新Gate `6ac…` 2ケースのpassはBFTだけでiOS実走なし。RootList r17bは7操作/ACK後にrouterDepth 1・tab hiddenのままtimeout。r17d direct push/native pop対照はpassしたが実UI Backではない。AppRoot候補446e…のr18も同条件でfailし、候補はarchive後に戻され、現在のAppRootは `98c4…`。根本原因とr19元製品native-pop対照は未確定。r18のlive-load JSONにあるUDID欄は誤記で、実UDIDは `4372E22F-0235-49F5-90C9-5082A7ACF60C`。loaded paths・lsof・scroll-readyが一致し、誤記訂正はSHA/load一致と別に記録した。Face ID初回許可は未回答のため許可せず、permissionBlocked/LAError -6で失敗。本物の認証成功は未確認。未確認11件は先取りして減らさず、物理SE3追加確認も未実施。unit cache 7件/約2.66 GiBは対応表つきでTrashへ移動済み。検証用26 simulatorはboot中、所有18 simulatorはshutdown済み、現在使用中のbuildは保持。過去のPhloxKit 1,062件や31ad/c070 fullは当時のsource/runとしてのみ扱う。


前回unit結果（r6履歴）: PhloxKit 398 XCTest + 662 Swift Testing / 108 suites、1,060 pass、exit 0、warning/error 0。468対象fileの実行前後source SHAは `fdd4a181fdc03430fc06ae0fe5e26733b41c58a751c445f622ba7973c14f3f19` で一致。記録は `.verification/ios-redesign-stage8b/remaining/unit-attempt5/`。

前回unit結果（r8、履歴）: PhloxKit 400 XCTest + 662 Swift Testing / 108 suites、1,062 pass（`.verification/ios-redesign-stage8b/logs/remaining-phloxkit-unit-r8.log`）。

### 最新r10/r11結果（2026-10-19）

**時点区分:** このr10詳細と後続の31ad/c070正式full記録はr10以前の旧source時点の履歴。r11ではテスト専用差分が入り、iOS26 Offline 24条件を再実行して1条件失敗・exit65を記録した。現況は冒頭の「現況」およびこの節のr11結果を正とし、r10 runを現source全体の合格として扱わない。

r10のPhloxKitは400 XCTest + 662 Swift Testing /108 suites=1,062 pass、exit0・warning/error0。generic app+embedded Widget build、独立Widget scheme、analyze、lint、Snapshot BFT 509対象も成功（`remaining/logs/ios-final-phloxkit-unit-r10.log`, `ios-final-generic-app-widget-r10.log`, `ios-final-widget-scheme-r10.log`, `ios-final-analyze-r10.log`, `ios-final-lint-r10.log`, `ios-final-gate-bft-r10.log`）。Gate関連のsource fingerprintはLaunchGate `0349a1b6…`、AppShell `142b7270…`、DSPlatform `17b225…`、Gate/snapshot tests `34f0ff65…` / `a4333ec1…`。iOS26 Gate AX5実操作は2ケースpass（`ios-final-gate-ax5-ios26-r10.log`）、親CUAは5 ACK（428幅retry/footer各2、375幅failure body/retry/footer各3）。loaded app payload `cae1a728…` とtest executable `89a7c4ce…` SHAはbuild成果物と一致。

r10 Offlineはnative slot実表示のclip 18条件を確認し、製品natural inset修正へ戻した。旧検査は23/24 pass・1失敗だが、前景文言は可視でOCRが隣接glass列の「あり」を混ぜた誤判定と判明。raw OCRと厳密全文条件を保持し、テスト専用geometry列結合を行った。旧compact run 6 pass/18 failは履歴維持。新検査で保存された24passは画面外検査で、実UI passではない。

r11はBFT 509 source対象で成功し、製品source manifestは前後一致、後続のOffline test-only source SHAは `b819bdd99c00ba10ca51f386ee2c42e237e11f12217ff87ddec4d15b116d828f`。その前段のiOS26 Offline実UI24条件は1条件失敗・exit65を保持する。失敗は `host-size2-428-retrytrue` の再接続文言visible検査で、記録は `remaining/logs/ios-offline-spatial-acceptance-ios26-r11.log:53` と `OfflineAccessoryAcceptanceTests.swift:97:29`。保存画像の72条件OCR分析はr10/r11各24/24 pass、pass画像の独立全文検査もexit0でfalse greenなしだが、test/UIを再実行した結果ではない。RootInteractive iOS26は初回5件中4件pass。初回RootListは親CUA期限切れで未ACK。その後のtargeted rerunは3 ACKとSettings/Sessions到達を観測した後、誤った `tabBar.items.count == 2` assertionが実値3で失敗した。採用仕様はnavigation tab 2件と独立search-role項目であり、製品欠陥とは未判定。正式full、Gate18、Offline両OSは未実施。RealBio失敗とUsage18 strict offset失敗は保留する。

追加motion、Thinking補足/最大文字、D5送信失敗fixture、native popover AX5 trait、および追加font sourceを統合した。最新統合sourceのPhloxKitはXCTest 391 + Swift Testing 656 / 108 suites、1,047件pass、warning/error 0（`motion-disclosure-fix/logs/phloxkit-caption-final.log`）。iOS lintもexit0。generic app/Widget build、Widget scheme build、analyze、新しいSnapshot `build-for-testing` は担当ログ上exit0。最新test binary SHAは `c070ee79874dd56729ffc5bee0d6c5f7ec86b6df6e20181cc0842d575fe6422c`。以前の読み取り専用環境値への書き込みによるcompile失敗は修正済み。独立最終小差分reviewもpass。

正式fullはiOS26・18ともsource `31ad` / test binary `c070ee79874dd56729ffc5bee0d6c5f7ec86b6df6e20181cc0842d575fe6422c` で完了。両OSとも10/10 pass、0 fail/skip、202 PNG、loaded SHA一致。各OSでUsage 4場面はAX proof validated、menu 2場面はpresented。ObjC重複・appearance・通常warning/errorは0。26のOS診断はUnknownAX 1、IOSurface 1、fopen 2。18はCGGStackRestore 274、UnknownAX 1（旧a2の272件とは別run）。詳細は両OSの `result-bundles/final-accessibility-ios*.xcresult` と対応ログ。

iOS26の画像比較は177カテゴリ、SHA一致52・変更150、Glance 4枚一致。iOS18は179カテゴリ（list 34 / pair 30 / composer 38 / chat 34 / cards 43）、旧画像からSHA一致70・変更132、追加欠落0。18のカテゴリ別確認状況は `visual-*-final-accessibility-ios18.md` に記録し、各カテゴリの詳細はvisual-*-final-accessibility-ios18.mdに記録。26は `visual-*-final-accessibility-ios26.md` を参照。画像比較は操作確認を意味しない。

UsagePopDTのスクロール原因調査ではviewport 739 / content 1530.667 / `scrollEnabled=true`、前後offset 0を取得。finite-height不足説は反証されたが、入力原因は未特定で、末尾までの実操作も未検証。診断初回は親timeout後9 pass/1 fail、同条件r2は10 pass。診断用2呼出しとhelperだけを除いたソースを正確に `31ad` へ復元し、保存 `c070` とBFT artifactのSHA完全一致を確認。診断source/patch/JSONは `.verification/ios-redesign-stage8b/diagnostic-source-archive/usage-scroll/` に保存。製品変更がないため正式26再実行は不要。appearance警告3件は不要な測定window由来と特定し、test-only画面外hostへ移して解消、独立review pass。wrong-prefix runの10 passは描画未実行・PNG0のため正式成功に含めない。

C1の3チェックリストは既存採用記録に従う（`0028-ios-redesign-stage8-worklog.md:66`）。F2も同記録の「PhloxError.unreachableは接続先を持たないため例のIPを出さない」という採用理由（`:49`）に従う。stage8bでの新規不具合指摘は採用済み判断を再確認して撤回した。台帳は133件中122件に静的な実装根拠あり、11件未確認。実操作まで検証したという意味ではない。`ios/docs/specs/ui-feature-inventory.md` はstatus=supersededの再設計前資料であり、現行仕様の根拠として扱わない。不要な自作端末は残存0件で、画面検証時だけ1台ずつ起動する。

一覧、会話、新規チャットと入力欄、接続と設定、承認と質問、撮影データ、添付受理の差分を統合した。写真選択の成功・失敗は選択順を維持。新規チャットは作成待ちから発言・進捗を表示し、処理中の下書きを保護する。追加差分の独立レビューはpass。追加コミット・devマージは未実施。

旧a2 executableのiOS18/26正式描画は追加motion/Thinking/D5/native AX5 source統合前の履歴結果。統合直後のcompile失敗は修正済み。現source31ad/c070ではPhloxKit1047、関連build/lint/analyze/BFT、および両OS formal fullが完了（詳細は現況）。古い結果を現sourceの成功へ読み替えない。途中失敗と診断残件は `.verification/ios-redesign-stage8b/OWNER.md` と `logs/` に記録する。

追加motion/Thinking/D5/native AX5統合前の最終撮影構成（test binary a2e91）のiOS18.3.1・26.2正式描画は各6 tests / 2 suites、失敗・skipなし、exit0、各202枚。これらa2画像は統合前の履歴結果。現在source31ad/c070でiOS18/26正式fullを完了（現況に記載）。比較記録中のChatSub/Darkは廃止された見本で受入対象外。SE端末タイプのシミュレーターによる実寸補完は各OSで6枚（製品Swiftが同一の旧リンク構成で実行）。先行18の2回の全体実行は親の操作が60秒以内に間に合わず失敗し、不完全な各191枚は正式比較に使わない。

現sourceの正式18ログでは通常warning/error・ObjC重複・appearance警告は0、CGGStackRestore 274件とUnknownAX 1が残る。現sourceの正式26ログでは通常warning/error・ObjC重複・appearance・CGGは0、OS診断UnknownAX 1 / IOSurface 1 / fopen 2。旧a2ログの18 CGG 272は別runの履歴値である。Cursor素材のmask除去は18でも警告0になるが、36枚比較で画素差が事前閾値を超えた。alpha mask案は画素一致でも警告が残る。製品素材は原本を保持する。

26のSE補完で見つかったAgentDomainクラス二重実装のobjc警告は、テスト側依存宣言を保ち `link: false` でアプリ所有シンボルに統一。両OSの現source正式fullでObjC重複0を確認した。製品Swift・共有パッケージの製品定義はこの修正では変更していない。

AC台帳は定義133件と同数・重複なし。122件は静的な実装根拠あり、11件は未確認。これは新source gates完了を意味しない。実機、VoiceOver、IME入力、カメラ・push・スクロール操作、未撮影のOSメニューやキーボード、ChatLongの同文折り返しなどは検証範囲外。XCUITestは実行していない。

### AC-11 静的対応の更新（2026-10-19、過去集計）

現行sourceを追加追跡し、Pair 17状態のView/state条件を全件対応付けた（scene 14件、未登録3件: GateAuth/PairScan/PairRescan）。Error catalog 32 IDとuser-facing callersも対応し、D3失敗/F3 neutral/D6 retryの現登録testを反映した。AC台帳の静的状態は当時124件の根拠あり・9件未確認へ更新。これは全画面/OS操作の検証を意味しない。Pairの正式画像はiOS18 r22bで14状態、iOS26 r14 formalも別generationの9/9・204 PNGを確認済み（app `cae1…` / test `b6c013bb…`, PID22565、`remaining/OWNER.md`）。Face ID/カメラ経路、429の最終色、D6失敗alertのOS描画は未確認。詳細は `.verification/ios-redesign-stage8b/ac11-pair-error-current-audit.md` と更新済みAC台帳を参照。

旧test bundleの誤起動は実load先で特定し、自作hostの削除と専用端末の正規再起動後に最新SHAを確認した。使い終わった今回作成の26専用147CDA82と18専用00F26565はnative shutdown後に個別削除。親のsimctl確認でstage8b端末残存0件、記録対象の検証PIDも全終了。他作業の端末と通常開発cacheは保持。最終xcresult・照合用実行ファイル・画像・ログを保存し、所有cache4件は`.env*`不在確認後にTrashへ移動。詳細はOWNERとxcresult-archiveに記録。実装と自動検証は終了したが未確認事項と診断残件があり、追加コミット/devマージ/公開は未実施で承認待ち。

### 現行状況への入口

AC分類、r34品質ゲートとAX5 targeted画像、r33 Gate/formal結果、未確認範囲は [stage8b/NEXT.md](../../../.verification/ios-redesign-stage8b/NEXT.md) を参照。以下の記録は過去のrunであり、現runへ読み替えない。

## 描画テストの修正

初回のiOS 18.3描画テストは、撮影用APIが別型のprivateエラーを参照してコンパイル失敗した（exit 65、画像0枚）。エラー型を同一ファイル内で共有できる範囲へ移し、撮影ターゲットのImageAttachmentKit直接依存も明示した。撮影の期待値や製品の挙動は変更していない。プロジェクト再生成後、18.3から再実行する。

再実行は撮影本体へ到達したが、UsagePopのアクセシビリティ経由のボタン探索で失敗した（exit 65、5 tests / 2 suites / 1 issue）。途中画像178枚は不完全なセットとして扱う。状態更新警告98回、CGGStackRestore警告218回も検出し、sceneと描画処理の対応を `snapshots/ios18/warnings-by-scene.md` に集計した。成功扱いせず、該当画面を限定して原因を切り分ける。iOS 26.2はこの時点では未実行。

## 途中画像の監査で追加した修正対象

カテゴリ別に画像を実際に開き、一覧34・接続30・入力/使用量16・会話34・承認/質問43の見本との比較を記録した。途中集合157比較であり、未生成画面や実操作まで確認したとは扱わない。

- 承認の「許可」が小画面/大きな文字で横に潰れ、ラベルが見えない。DetailDT、ReplyDT/SE、ReplyApprovalDiffDT/SEで確認した。操作種類の意図した文言差とは区別し、4操作を読める配置へ直す。
- 添付エラーと権限エラーの1行省略で、画像の切り出しやフォルダ再選択の案内が消える。AC-6-18とAC-6-11に従い、対処の文を読めるようにする。
- ReplySendingの添付番号重複は撮影データが本文へ番号を書いた後、通常の添付追加が再び番号を挿入していた。撮影データを通常の手順に合わせる。製品の通常フローの不具合とは判定しない。

標準タブのOS差、Errorsカタログの説明、折り畳み行のエラー件数、会話本文のデータ差は実装・既存決定で再判定した。スクロール末尾への操作到達性は静止画だけでは未確認。ReplyMoreの開状態も撮影範囲外として残す。

## 使用量ポップアップと入力欄の警告

物理画面が428×926ptの14 Plusでも、撮影内部の公開アクセシビリティ探索はSwiftUIの子を取得できなかった。専用シミュレーターを表示し、外部のCUAから本物の使用量操作を押すと、実popoverの存在を検査して画像を生成できた。`UsagePop-external-ready.json` の `awaitingTap`→`presented`、PNGとログを `snapshots/ios18-usagepop-external-14plus/` に保存した。親と検証担当が実画像を開き、3サービスの表示が画面内に収まることを確認した。全描画の成功とは扱わない。

診断マーカーで、状態更新警告がDSInputBarのTextSelection用Binding setter内で発生すると確認した。選択通知は最新のものを次のMainActor実行機会へ送り、本文変更や外部カーソル変更時の古い通知を破棄する。登録テスト3件と独立した静的レビューを追加した。修正後のUsagePop単独実行では状態更新警告0件。CGGStackRestoreは3件、実タップ後のAXRuntimeCommon Unknown clientは1件残り、別の警告として記録した。IMEを使った実入力は未検証。

## 一時作業環境の整理

今回作成した7担当のworktreeは、差分・未追跡ファイル・検証記録を主worktreeの `.verification/ios-redesign-stage8b/worker-archives/` へ保存した。自作の不要物はゴミ箱へ移し、各作業ツリーがクリーンになったことを確認して正式なcleanupスクリプトで削除した。主worktreeの統合済み差分は未コミットで保持する。引継ぎ前から存在するレビュー用worktreeと通常の開発キャッシュは残した。

## 仕様の説明の補正

- Codexのモデル選択は実装済みのため、API契約と概要の「非対応」を修正した。
- 対応待ちだけになったプロジェクトの見出しは、採用見本 `ListAllAttention` どおり表示しない。仕様の常時「＋」は表示中の欄へ適用する。
- 一覧取得失敗・作成失敗・送信失敗・承認応答失敗は、段階8aで採用した `Errors` カタログの原因・次の操作・技術値の形式を維持する。古い1行表示の説明を更新した。HTTP番号は見出しと本文へ混ぜず技術脚注へ置く。
- 履歴はADR0037の既存決定どおり表示ブロック単位で数える。ツール呼出件数へ戻さず、仕様の「50件」の単位を明記した。
- 前景復帰時の使用量取得は `AppRoot.swift` に存在した。欠落という監査の仮説は反証され、重複呼出しを追加しない。

## 検証基盤の補正

この作業ブランチの `macos/scripts/run-swift-tests.sh` は、共通ルールが指定する `SWIFT_TEST_SCRATCH_ROOT` に未対応だった。`dev` に実装済みの正式な対応を限定して取り込み、`swift test`・素材の事前ビルド・`--show-bin-path` の出力先を同じpackage別ディレクトリへ揃えた。空白を含む絶対パスと相対パス拒否の既存回帰検査も取り込んだ。無関係な素材キャッシュ判定変更は含めていない。

初回のプロジェクト生成は `xcodegen` のPATH不足でexit 2。既存の `/opt/homebrew/bin` を指定した再実行は成功した。独自のPATH shimや検証の回避はしていない。

### 引継ぎ継続: ブランド診断のリンク失敗と進捗表示修正

- `make -C ios generate` は成功。DesignSystem直接依存追加後のSnapshotTestsリンクでAgentDomainシンボル未解決、exit 65。画像0枚、承認arming未確認。AppIntents metadata skipped/CoreAudioTypes・UIUtilities unavailable/SwiftUICore not allowed client警告も記録し、原因調査を実装担当へ戻した。診断を省略して成功扱いにはしない。
- AC5-12の3行同時表示は見本どおりと訂正。spawn応答待ち中の吹き出し・進捗不足を別worktree `feature/ios-redesign-progress` で修正中。主のNewChat3ファイルをseedしSHAを `.verification/ios-redesign-stage8b/progress-worker/seed-manifest.json` に保存。コミットなし。
- 比較用補助スクリプトへ正式snapshot入力/outputの明示指定と重複拒否を追加。古い撮影画像を自動で正式候補として選ばないため。製品変更ではなく、実行は正式撮影後。

### 追加検証: 承認arming・Cursor最小再現・host分離

- AgentDomain直接link依存補正後、ReplyDT/ReplyCodexの6 tests /2 suitesが成功、2画像を生成。両カードの実readiness→0.6秒arming begin/endと有効な4操作を確認。state警告0、CGG警告6（2/4）は残る。
- ブランド単体ではClaude/CodexのCGG0、Cursorだけ1と再現。元SVGが不正とは未確定。幾何学的に冗長なmask/clipを1属性ずつ外す診断比較を準備し、製品素材はまだ変更しない。
- Snapshot hostへ既存-UITestingを明示し、起動時require/証拠markerを追加。BrandClaude、BrandCursorで通常hostのlocalhost接続/Push登録失敗は消失。CursorのCGG1はhost分離後も再現。destination arch=arm64明示で候補重複warningも解消。
- NewChat追加独立レビューで、送信中の追加入力が作成成功時に消える既存リスクを確認。今回差分起因とは扱わず、ユーザー依頼の細部修正として進捗workerへ追加対応を戻した。
- CUAで自作SE3端末に残った通知許可dialogを確認し「許可しない」で閉じた。通知アクセス追加なし。他者端末は未操作。

### 最新NewChat単体・診断比較の途中結果

- NewChat修正4fileはseed/最終SHA照合と独立レビューpass後に主へ統合。PhloxKitの初回全実行はXCTest391＋Swift Testing652/107 suites（合計1,043）、exit0、warning/error0。lintもexit0。初回PIDは未記録であり、PID補完だけの不要な再実行が発生した。再実行後の外側記録shellはzsh予約変数statusへの代入でexit1、テスト結果と記録処理の失敗を区別してOWNERへ記録。追加反復は止めた。
- DraftSpawning/Sending限定描画は6tests/2suites pass、2画像を実見しphaseの本文/進捗表示を確認。CGG4は残る。
- test bundleのCursor原本/NoMask/NoInnerClip/NoOuterClipは各6/2 pass。CGGは1/0/1/1。NoMaskの22pt/2x/lightは差分5pixel・最大channel差7で、事前の厳密閾値(max1)には未適合。見た目一致と断定せず製品素材変更は保留。複数条件比較と、白maskのluminance→alphaの独立variantを準備中。

### r12時点の途中結果（後続r14–r18追記を参照）

- iOS26 UsagePopover fresh CUAで末尾「残り95%」までscrollし、先頭「Claude Code」へ戻った。strict offset bottom 792.6667/792.6667、top 0/0で1 test pass（`.verification/ios-redesign-stage8b/remaining/logs/ios-remaining-usage-interactive-ios26-r11-extracted.json`）。確認したのはpopoverの実scroll到達。iOS18のstrict bottom/topは12pt/20pt差のfailを維持する。
- RootList rerunではscroll、Settings tap、Sessions復帰の3 CUA ACKとSettings到達を観測したが、`RootTransitionTests.swift:221` のUIKit内部 `tabBar.items?.count == 2` assertionが実値3で失敗し、1 test/1 suite・exit65（`.verification/ios-redesign-stage8b/remaining/logs/ios-root-list-scroll-ios26-rerun-r11.log`）。これはACK期限切れではない。採用仕様はnavigation tab 2件＋独立search-role新規チャットで、UIKit内部items数2は仕様条件ではない。2→3だけに期待値を書換えず、役割を検査するtest-only修正を依頼済み。失敗は製品バグと断定しない。56pt縮小/アクセサリ位置は別途未確認。
- Offline26はtest SHA `b819bdd9…` で実UI24条件を再実行中。r12 BFT509の前後一致、製品source `cae1…` 不変を確認。結果未着のため合否未確定。Offline18、Gate18、正式full両OSも未実施。

### r14–r18結果の訂正追記（2026-10-19）

- Offline26 r12は24/24 pass、Offline18 r16も24/24 pass。18の出力先は `.verification/ios-redesign-stage8b/remaining/offline-runtime/` の24 UUIDで、PID78054の記録により特定。26のrunはtest SHA `b819…`、当該短いrunのlive lsofは未採取。旧r11 OCR failは旧test SHAの履歴として保持する。
- iOS26 formal r14は9登録定義・9 pass・0 fail/skip、204 PNG、当時の製品debug payload `cae1…` とlive SHA一致。「10定義」の記録は誤り。iOS18の現source formal fullは新しい一次実行結果を確認していない。
- Usage26 r11はstrict末尾/先頭を実scrollしoffset一致でpass。Usage18のstrict値はbottom 12pt・top 20pt不足failのまま。
- Gate26旧2ケースはpass。Gate18旧host428はpass、synthetic375はOCR assertion failだが実PNGの全文は見える。新Gate `6ac…` の2ケースはBFT passのみでiOS実走なし。
- Root r17bの7操作/ACK後はrouterDepth 1・tab hiddenのままtimeout。r17d direct push→native pop controlは1 test passだが、物理的な画面Backを立証しない。AppRoot候補446e…のr18も7操作後に同じ状態で1 failし、候補はarchive後に戻され、現在のAppRootは `98c4…`。根本原因は未確定。r18 live-load JSONのUDID欄は誤記だが、loaded paths・PID 30290のlsof・scroll-readyが示す正値は `4372E22F-0235-49F5-90C9-5082A7ACF60C`。原JSONは保持し、訂正記録を別保存した。r19元製品native-pop controlは準備中で結果なし。
- Face ID初回許可は未回答のため許可せず、permissionBlocked/LAError -6で失敗。本物の認証成功は未確認。物理SE3追加確認、VoiceOver/IME等の残件も完了扱いにしない。unit cache 7件/約2.66 GiBはTrashへ移動済み、現在使用中buildは保持、所有26 simulatorはboot中・18はshutdown済み。
