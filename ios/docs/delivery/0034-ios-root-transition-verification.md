# AppRoot とネイティブ確認画面の結合検査

## 実装前の契約

本物の `AppRoot` を `UIHostingController` に載せ、認証ゲートと接続中・失敗表示の切り替え、通知保留とルート置換を検査する。依存は本番の既定値を保った初期化引数から注入する。UIを複製せず、テスト対象の状態とルーターを保持する。

削除の確認・失敗は本物の `DeleteConfirmationView` と `UIAlertController` を使う。操作は公開の UIKit / accessibility API に限り、応答したAPIの呼び出し記録を検査する。公開操作が受理されなければ失敗として報告し、非公開 action handler 呼び出しや成功への読み替えはしない。

実行ターゲットは `PhloxMobileSnapshots` の `PhloxMobileSnapshotTests/RootTransitionTests`。`-UITesting` が必要。XCUITest は使わない。新規ソース確定後、親担当の一元実行までビルド・Simulator起動を行わない。

## 確認の境界

状態を注入したゲートの検査は実Face ID成功やOSバックグラウンド移行の証拠ではない。通知入力は `PushCoordinator.handleSessionURL` の公開入口を使い、実APNs配送の証拠とは区別する。動的な画像は検査時のwindowから採取する。

強権限メニュー、C1 timeout、429最終色は、必要な公開操作と依存注入の契約が成立する範囲で追加する。未実行の検査は完了と扱わない。

## 追加した検査（実走前）

- `RootTransitionTests`: connecting / failure の2状態でロック時にoverlayが消え、状態を保ったまま解除後に再表示する。保持した model を通す状態遷移であり、OS背景通知の検査ではない。
- `lockedPushWaitsForUnlockAndFreshListThenReplacesOldRoute`: 公開session URL入口から通知要求を積み、ロック中の保留、解除・fresh list取得後の消費、深さ2から1への置換、保留modal解除、本物詳細の見出しを検査する。
- 一覧40件を本物rootに渡し、親CUAの実スクロール後にnative offsetが増えることを検査する。実UITabBarの位置・項目数、実タップによる設定画面への切替、セッション一覧への復帰とrouter深さ0を確認する。iOS26タブ縮小の視覚判定とは区別する。
- 本物native delete alertのキャンセル時API0回、confirm後の503失敗alert本文、再試行API2回、閉じるのcallbackを検査する。技術値の文字列順を確認し、OSの最終等幅表示は取得画像で別確認する。
- `RootInteractiveTransitionTests/strongPermissionNativeAlertCancelThenConfirmInvokesRealViewModelAPI`: 本物 `SessionDetailView` / view-model / composerをhostし、親CUAが権限menu→「全部許可」→実alertのcancelとconfirmを操作する。cancel後API0回・permission nil、confirm後API1回・`bypassPermissions`を検査する。
- `realRootTimeoutProducesC1AndRetryReturnsToSessions`: 実overlayの再試行から `connectAfterPairing` を通す。テストだけtimeoutを0にし、本番既定20秒と採用copyを保つ。C1の20秒案内・注入endpoint・3確認項目をassertし、repositoryが空一覧取得へ回復した後の実再試行でoverlayが閉じることを確認する。
- `rateLimitedRepositoryErrorReachesRealRootCatalogCard`: repositoryの429から本物root/list cardへ到達し、見出し・HTTP 429詳細をAXで確認して最終window PNGを保存する。無彩色かは保存画像で別途確認する。この追加は詳細・新規チャットの429画面を撮影するものではない。

強権限は別suiteとして `-only-testing:PhloxMobileSnapshotTests/RootInteractiveTransitionTests` で直列実行する。各stepのready JSONと、nonce/pid/udid/scene/stepが一致するackを介して実クリックを結び付ける。`cancel-ready.json` の操作は「権限」menu→「全部許可」→「キャンセル」、`confirm-ready.json` は同menu→「全部許可」→「全部許可 にする」。ackの `phase=reviewed` / `confirmed=true` / `capturedAt` が必要。180秒で未応答なら失敗する。

出力は `PHLOX_REMAINING_OUTPUT`（`TEST_RUNNER_`付きにも対応）、既定は `.verification/ios-redesign-stage8b/remaining/`。`PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE` で親が実Simulator窓名を渡す（同じく `TEST_RUNNER_`対応）。controller titleはscene識別として別記録する。取得したwindow画像とAX labelsは各一意ディレクトリの `window.png` / `record.json` に保存する。テストはkey windowを元に戻して自身のwindowだけを閉じる。

## 診断で判明した操作APIの境界と訂正

2026-10-18のiOS18.3.1診断（旧source `04b884…1964f`、build products `dcc03d…07ab53`、ログ `remaining-native-root-transition-ios18.log`）では、本物native delete alertの公開 `accessibilityActivate` / UIButton操作対象が得られず、cancelとconfirmは `publicActionUnavailable` で失敗した。一覧は `isScrollEnabled=true`、content height 4417.33、viewport 796だったが `UIScrollView.accessibilityScroll(.down)` がfalseを返した。これらの公開APIなら本物UI操作を実行できる、という新規テストの仮定が誤っていた。製品のalertやscroll自体が使えないという証拠ではない。

失敗した3件は、本物View・window・view-model・APIを保持したまま `RootInteractiveTransitionTests` へ移し、親CUAの実入力をnonce付きready/ackで待つ。公開APIのfalseを成功に変えたり、offset・action handlerを直接設定したりしない。元のAPI呼出回数・失敗本文・再試行・close・実offsetのassertは維持する。既存製品テストは変更しない。

自動suiteは gate（2入力）、push、C1 retry、429の4定義。対話suiteは次の4定義であり、各scene/step/nonceは独立する。

| scene | stepと実操作 | ack後にテストが必須確認する値 |
|---|---|---|
| `RootListScrollAndSettings` | `scroll` 一覧を下へスクロール → `settings` 設定タブ → `sessions` セッションタブ | native offset増、UITabBarの可視領域との交差、通常の移動タブ2つ（26は独立新規操作も1つ）、selectedItemが設定→セッション、router深さ0、設定本文 |
| `NativeDeleteCancel` | `cancel` キャンセル | API削除0回、cancel callback1回、idle |
| `NativeDeleteFailureRetry` | `confirm` 3 件を削除 → `retry` もう一度削除 → `close` 閉じる | API削除1→2回、実503失敗alert本文、close callback1回 |
| `StrongPermission` | `cancel` 全部許可→キャンセル → `confirm` 全部許可→全部許可 にする | settings API0→1回、permission nil→bypassPermissions |

各readyは操作直前の `state` と `screenshotFile` も持つ。各nonceのackは `*-reviewed.json` に保存し、一覧offset・削除結果は `*-state.json` に記録する。新ソースのビルド・再実走は親のsource freeze後に一元実行する。旧診断の失敗を修正後の成功証拠へ読み替えない。

## 画像の更新待ちの訂正（再実走前）

旧診断画像の独立レビューで、`connecting-before-lock` と `connecting-locked` のPNGが同一なのに後者AXはgateだけを示す不一致が見つかった。C1 retry成功画像にも古い失敗overlayが残っていた。旧captureはAX/state更新直後の `drawHierarchy(afterScreenUpdates: true)` だけでフレーム反映を待っておらず、これらの画像を表示成功の根拠にはできない。

新captureは状態側のassert後、実 `CADisplayLink` callbackを3回、有限Core Animationの終了、layout/displayの反映、追加のdisplay callbackを待ってから `afterScreenUpdates: true` で採取する。固定時間だけを待つ処理にはしない。観測前後のAX labels、display timestamp、capture phaseを記録する。gateの前後とC1 timeout→retryにはPNG差異のassertも追加する。画像の差異だけで正しい表示とは断定せず、新画像は独立目視レビューで確認する。

C1 retry成功はmodelの完了に加え、失敗見出し・接続中・再試行のAX消失と、本物の「セッションがありません」表示を待つ。C1 timeoutの全文が大きな文字で切れている可能性は、新captureと追加の `RootInteractiveTransitionTests/realC1TimeoutChecklistAndEndpointAreReachableByExternalScroll` で分ける。同じ実timeout経路のnative scrollを親が操作し、実offset増と技術行の実AX frameがvisible viewport内へ到達したことを検査する（scene `C1TimeoutBodyScroll` / step `body-scroll`）。スクロールが不要な高さなら、技術行が初期viewport内に収まることを検査する。到達不能ならclipを成功扱いせず、viewport/content/offsetと条件をAppRoot担当へ報告する。

新capture・追加対話検査は未実行。ビルドとSimulatorは親の次の一元実行を待つ。

画像のbyte差はspinner回転だけでも生じるため、それだけを状態変化の証拠にしない。独立レビュアーと合意し、保存する同じPNGへVisionの日本語/英語OCRを適用する必須assertを追加した。lockedはgate固有文言（ロック中または認証失敗）とFace IDがあり、直前のoverlay主文がないこと、connectingの前後は接続主文があること、C1復帰は空一覧の見出しがあり失敗見出しがないことを検査する。正規化は空白と省略記号に限る。OCR結果・要求語句・禁止語句を画像と同じrecordへ保存し、認識失敗は検査失敗とする。AX/modelのassertも残す。C1初期画像に本文全体を要求せず、実scroll後の画像でendpointを要求する。親の原寸画像による独立目視確認も必要である。

## r4の待機条件の訂正（次回実走前）

source `db8a1ae…f982` のiOS18 r4実走は、自動4定義のうちpushが成功、gateの2入力・C1・429がtimeoutで失敗した。ログ `remaining-native-r4-root-ios18.log` に記録がある。出力先には各 `*-before-lock` / C1 / 429 capture用の空ディレクトリが生成されており、初期AX待ちを通過してcaptureの待機へ入ったことを確認した。旧実装は診断情報を保存しておらず、その時点のdisplay callback数や具体的なCAanimationの値は確認できない。

コード上の問題は、window全体にduration付き有限CAanimationが一つでも存在すれば「未終了」とした待機条件である。終了後も保持されるanimationや別の常駐演出を区別できず、局所画面の更新確認として成立しない。この全window停止条件を削除した。新しい描画手順は実display callback、対象windowのlayout/displayとtransaction flush、追加display callback、`afterScreenUpdates: true` の描画であり、鮮度の本体は同じPNGの状態固有OCRと既存AX/model assertionで判定する。timeout延長やOCR条件の緩和は行わない。

次回captureは、待機前・display callback観測後・commit後の追加frame観測後、またはtimeout時にraw JSONを保存する。各recordにdisplay timestamp、layer path/type、animation key、beginTime/duration/repeatCount/repeatDuration/speed/timeOffset/isRemovedOnCompletion/fillMode、layer local time、AX labelsを記録する。過去のraw値を後から推測して確定とは書かず、新実走の証拠で待機と描画を照合する。新ソースはまだビルド・実走していない。

## r5で確定した認証fixtureの修正契約（実装前）

r5はC1・429・pushが成功し、gateの2入力だけ画像OCRで失敗した。`AppRoot` はlocked分岐で自動認証を既定有効にした本物 `LaunchGateView` を作る。同viewの `.task` は `authenticate()` を呼び、view-modelは直ちに `.authenticating`、返答falseで `.failed` へ進む。旧fixtureの `StubAuthenticator(allows: false)` は認証失敗を即時生成するため、静止した「ロック中」の期待とは一致していなかった。AX5の失敗見出しの末尾省略にOCR期待を合わせて通す修正は行わない。

AC3-9の対象は非unlocked中にgateを優先し、connecting/failure情報を保持して解除後に再表示すること。fixtureを制御可能なauthenticatorへ変更し、実自動認証呼出しが1回で応答待ち、AppModelがlocked、本物gateの「認証しています」とFace IDが画像にありoverlay主文がない状態を必須にする。その後fixtureがtrueを応答し、本物の `authenticate`→`onUnlocked`→AppModel.unlocked経路でoverlayが復帰することを検査する。直接unlockedを代入しない。待機は終了可能なAsyncStreamで保持し、成功後に完了を確認、失敗時もstreamをfinishして未解放continuationを残さない。元のisConnecting/failure保持assertとOCR/AX検査は維持する。

## r6 C1初期画像の修正契約

独立レビューでr6の自動C1初期画像に旧「接続の再試行待ち」と新見出しの重なりを確認した。このcaptureには状態固有OCR要求がなく、画像内容が未検証だった。実C1本文は別の親CUA操作で正常に表示・scroll到達が確認されており、初期viewportに全文が入らないこと自体を製品欠陥とは扱わない。自動初期captureは新見出しと本文冒頭「接続先は保存しました」を画像へ必須要求し、旧見出しを禁止する。3確認項目やendpoint全文は初期画像に要求せず、既存の実scroll検査を維持する。

## 削除再試行の失敗箇所の記録（実装前）

r6対話suiteは4成功・削除再試行1失敗だった。retryのackがありclose-readyがないため、API2回目の待機と次の失敗alert待機を既存ログだけで区別できない。両待機の前後・timeout時に、実API呼出数・view-model state・本物presented controller/alertの公開情報をphase別JSONへ保存する。元のAPI2回・本文・callbackのassertと5秒の状態待ち/180秒のCUA応答期限は変えない。製品の修正はAppRoot/統合担当の所有とする。

## タブの役割の契約訂正（実装前）

iOS26のRootList再走はscroll/設定/一覧の3ackを完了したが、「UITabBarは合計2項目」のassertで失敗した。AC-3-2と `DSPlatformTabView.iOS26Tabs` は、セッション・設定の移動タブ2つに加え、`Tab(value: nil, role: .search)` による右独立の新規チャット操作を定義している。iOS18は移動タブ2つだけである。この仕様を読まず合計2とした新規テストの契約を訂正する。

当初は実UITabBarを所有する公開 `UITabBarController.tabs` と `UISearchTab` を検査する契約を追加したが、r13でSwiftUI bridgeの `tabs` が空であることが判明した。この表現は製品から取得できるとは限らないため、次の契約へ訂正する。過去の失敗ログは保全し、26の56pt縮小はこの検査の成功から推定しない。

## r13の公開タブ表現と実機能の検査（実装前）

取得できる本物 `UITabBar.items` のtitleから、セッション・設定がそれぞれ厳密に1つであること、残りの操作itemが26だけ1つ、18では0であることを検査する。`UITabBarController.tabs` は取得できた値を記録し、空そのものは失敗にしない。新規操作の意味は、既存ソースの `.search` 宣言と、独立した右circleの実CUA操作で確認する。

26では設定とセッションそれぞれからcircleを押し、本物routerのdepth1と `newChat.screen` の表示を必須確認する。製品の `openNewChat` はsheetではなくsessionsタブへの切替とpushであり、back後はdepth0/sessionsへ戻る。設定ケースは親が設定を再tapして継続できることを確認する。未確認の「設定タブへ自動復帰」を要求しない。元のscroll/settings/sessionsの3stepに、`settings-compose` / `settings-compose-back` / `sessions-compose` / `sessions-compose-back` の4stepを追加し、18には追加しない。ready/ack識別・180秒期限と実offset検査は維持する。

## r14の親AX container依存の訂正（実装前）

r14はcircle実操作で新規チャットの見出し・提案・入力欄が表示されたが、親containerの `newChat.screen` が公開AXに出ず、複合待機がtimeoutとなった。実画面に存在しない親AX識別子を要求せず、depth1と、公開される `newChat.greeting` のcanonical見出し全文（製品がランダムに選ぶ正規一覧の一つ）、提案または入力/添付の子要素1種を、有限でwindowと交差するframeとともに確認する。正規文字列の変換や書換えは行わない。

compose ack直後、depth待機の前後とtimeout、子画面待機の前後とtimeoutをphase別JSONへ記録する。depthとAXを区別し、検証windowのkey/hidden/levelと同じsceneのwindow一覧も記録する。通常appのbaseRootと検証用Rootが別windowに併存する現設計を無断で変更しない。7step・180秒期限・実操作・root navigationの検査は維持し、製品は編集しない。r14以前の失敗証拠も保全する。

## r15の観測APIの訂正（実装前・最終harness変更）

r15ではcompose後の実router.depth1・検証windowのkeyを確認した。UIKit列挙は入力/添付を取得できたがgreetingを取得できず、一方fresh CUAの仮想AX原文にはgreeting ID・正規全文・提案・入力が存在した。UIView階層とSwiftUI仮想AX木が同じというテストの前提が誤りであり、製品の遷移失敗ではない。

composeの2ackだけに、親が同じnonceで実取得した `rawAXTree` と `windowTitle` を必須とする。own Simulator window header、番号付き実要素行のgreeting IDと同じ行のcanonical全文、入力または提案/添付要素を厳密に検査する。nonce/pid/udid/scene/step/capturedAtの既存条件と実router.depth1は維持する。UIKit列挙は診断として保存し、greetingが取れないことを失敗条件や成功根拠には使わない。原文の人工生成・文字列書換えはしない。7step/180秒とその他の契約を維持し、このcase以外のharnessを広げない。

## r16最終back待機の診断追加（実装前）

r16はcomposeのfresh外部AX検査と7操作を完了し、親が検証用40件一覧へのbackを視認したが、最後の `router.depth == 0 && 保存済みtabBar.selectedItem.title == セッション` がtimeoutした。back後の内部値を保存していなかったため、path同期と保存済みbar参照の寿命を区別できない。既存待機の直前・timeout・成功後だけに、router depth、旧barのwindow/superview/descendant/selected item、検証window内のhiddenも含む全UITabBarの同一性・frame・window・選択item・items、検証fixtureラベルを記録する。非有限frameはJSON数値へ入れずfiniteフラグと文字列で保存する。合否条件・参照・待機時間・step・外部AX証拠の条件は変えない。

## 検索タブ同時更新を外す対照1本（実装前）

r17bと同Productsでの座標backも実path1・bar hiddenが残った。nilは既に保存前にaction処理されており、検索タブのselection setter内で同時にpushすることが原因かは未確定である。製品を変更する前に `RootTransitionTests/directPushNativePopControlSynchronizesTheActualRootPath` を1本だけ追加する。同じ本物AppRoot・NavigationRouter・40件fixture環境を使い、rootの描画安定後にrouter.push(.newChat)を行う。owned/selected UINavigationControllerの実stackが2以上になったことを確認し、公開popViewController(animated:true)の後にnative stack1とrouter.depth0を両方5秒以内に要求する。router.popで置き換えず、UIKit AX greetingも要求しない。

controller class/title/count、path、frame/window、選択controllerをphase記録する。これは公開UIKit popによる方向同期の対照で、物理tapの証明ではない。失敗なら「検索タブの同時更新だけが原因」という仮説を棄却する材料とし、成功でもそれだけで原因確定とはしない。既存7stepとred判定は維持する。

## 同じ7step履歴で最後の入力だけを変える対照（実装前）

製品の通知分離候補でもredが残ったため、元製品へ戻して最後の入力だけを対照する。専用opt-in `PHLOX_ROOT_FINAL_PUBLIC_POP_CONTROL=1`（`TEST_RUNNER_`対応）時だけ、既存 `sessions-compose-back` は親にBackを押させず、待機解除のack後に検証用sessionsのowned UINavigationControllerへ公開 `popViewController(animated: true)` を送る。前6stepと履歴、最後の `depth0 && selectedSessions` の5秒条件は同じである。通常modeのBack操作・guardは変更しない。

modeを明記し、直前・直後・同期待機後/timeoutのcontroller identity/class/title/stack/delegate/navigationBar.delegate/root back item target/action/ownedwindow/pathを保存する。別stackをpopせず、router.popへ置き換えない。このmodeの成功を通常Back成功と報告しない。変更前1b73 sourceは `.verification/ios-redesign-stage8b/remaining/root-final-public-pop-control/` に保存する。

## 繰返しと空path再代入の自動対照2case（実装前）

r19は検索を含む同7stepの最後を公開popへ置き換えてもnative2→1に対しpath1が残った。nil受理候補も通常7stepで同じ不整合が残り、製品は元へ戻す。元のdirectcontrol初回成功と、検索/タブ履歴との違いを分けるため、別の `RootTransitionTests/repeatedDirectPushNativePopControl(resetEmptyPathBeforePush:)` をfalse/trueの2caseだけ追加する。

同じ本物AppRoot・40件fixture・owned sessions navigationを使い、検索とタブ切替を一切せず、安定rootでpush→実native2/path1→公開pop→native1/path0を2回連続で検査する。trueだけ各push直前に空rootへ `router.popToRoot()` を再代入する。各同期条件は5秒のままとし、loop間は実navigation transitionの終了とframe反映を待つ。各loopの前後・pop直後・同期後/timeoutに既存診断でcontroller/delegate/path/barを保存する。元directcontrol・通常7step・guardは変更しない。これは物理Backの検査ではなく、reset/repeat/tab履歴を分ける自動対照である。製品は変更しない。

## 同じ7stepの2回目composeだけを直接pushする対照（実装前）

r21はno-searchの反復false/true・各2loopが成功した。push直後のanimation完了を待っていない点は実CUA履歴との条件差として保持し、その成功だけでsearchを原因確定とはしない。

次の一因子対照は `PHLOX_ROOT_DIRECT_COMPOSE_CONTROL=1`（`TEST_RUNNER_`対応）時だけ、2回目の `sessions-compose` をcircle入力から直接 `router.push(.newChat(emptyDraft))` へ替える。先行settings側は通常操作を維持する。privateなselectedTabの操作や新hookは作らず、既存sessions実tapで選択済み・depth0を確認した後だけpushする。直接push後、同じcompose-ready/nonce付きrawAX証拠を待ち、親はcircleを押さずfresh AX観測だけをackする。前5step、最後の実Back、元guard、7step/180秒は維持する。最後のpublic-pop対照envは0で実行する。通常modeは一切変えない。

変更前d799 sourceを `.verification/ios-redesign-stage8b/remaining/root-direct-compose-control/` に保全する。これはsearch入力を外す対照modeで、通常circleとBackの成功証拠には読み替えない。

## 全search排除modeの適用契約

親のGO後、保存済み `direct-all-eight.patch` を元d799へ適用する。最終対照は2回目だけでなく、両composeでcircleを押さずdirectpushする8stepである。設定側のcompose前に `settings-select-sessions-for-direct-control` を追加し、親の実sessionsタブtapと選択/depth0確認を経てpushする。private状態へのhookは追加しない。

controlの順序は scroll → settings → settings-select-sessions-for-direct-control → settings-compose（観測のみ）→ settings-compose-back（実Back＋設定再tap）→ sessions → sessions-compose（観測のみ）→ sessions-compose-back（実Back）。composeの2ackには従来どおりfresh CUA rawAXTreeが必要。最後は `PHLOX_ROOT_FINAL_PUBLIC_POP_CONTROL=0`。通常modeは7stepのままであり、判定・timeout・製品Rootは変えない。適用後の構文parse/lintはSwift型検査や実走の代わりにはせず、次の合同BFTとnative実走を親/composerが行う。

## search要求なしの再appear回帰1本（実装前）

`RootTransitionTests/noSearchRequestAtStartupOrGateReentryDoesNotPushNewChat` を1本追加する。検索操作を一度も行わず、本物Rootの一覧表示・owned native stack1を待ち、AppModel.lockedへの遷移から本物gateの自動認証をcontrolled authenticatorで保留する。pending1回と実「認証しています」を確認してからtrue応答し、本物 `onUnlocked` によるsessions再表示・native root・frame反映後にrouter.depth0を再確認する。任意delayやonAppearの直接呼出しは行わない。

通常7step/対照8stepと元guardは変更しない。設定router保持・一瞬だけ保留された要求の取消は、このautoでは実証しない。既存通常操作と製品のstatic reviewがカバーする範囲・限界を明示し、そのための複雑な追加harnessは作らない。

## ListManyの初期展開後に撮影する待機契約

ListManyTop/Scrolledだけで既存prepareWindowを使い、検証window内の可視UIScrollViewと実content hostの有限・正寸法、viewportを超える本文を確認する。CADisplayLinkごとにcontentSize/bounds/insets/offset/body frameを採り、同一scrollの安定開始値からの差0.5pt以内が3frame以上かつ250ms以上続いた後に撮影する。250msは製品DSMotion.disclosureの展開時間に対応し、経過時間だけでは成功にしない。10秒deadlineで未安定なら失敗し、成功・timeout・中断のgeometry traceを出力先へ保存する。

固定sleepの延長、全animation停止、製品初期展開の変更は行わない。既存9selector・scene/filterは維持する。構文parseとraw値lintを行った後、Swift型検査・実走・原寸画像レビューは次の合同BFT以降で行い、それまでは未検証とする。

## 手動hostのscenePhase読取probe

検索circle後の白画面について、製品のbackground拒否条件と手動UIHostingController内の実scenePhaseの関係は未確定である。既存withRootWindowに透明・非操作のoverlayを付け、SwiftUI scenePhaseのonAppear/onChangeとowned UIWindowScene.activationStateを同じ時刻に記録する。operation前後・失敗時にJSON保存し、callbackでは標準出力にも記録する。環境値、Root/router/selectionへの書込や新しい合否条件・テストは追加しない。既存no-search起動/gate試験を同じhostで実行して実値を測り、UIKit foregroundとSwiftUI activeを同一と仮定しない。

r26ではprobeがbackground、owned UIKit sceneがforegroundActive、windowがkey/visibleだった。手動hostが実scene状態をSwiftUIへ伝えていなかったfixture欠陥であり、r23〜25のbackground拒否条件付き製品の失敗を実foreground環境の製品不具合と確定することはできない。実foregroundActive sceneを選び、そのactivationStateを初期値に、当該sceneのactivate/deactivate/background/foreground通知を動的に橋渡しする。Rootとprobeを同じ環境値の下へ置き、operation開始前にprobeと実scene由来の値の一致を要求する。固定active注入や製品guardの削除は行わない。通常7stepの操作・期待・guardは維持し、correct hostでの製品比較は別途実走が必要である。

## 不在セッション通知alertより認証gateを優先する回帰

`RootTransitionTests/relockDismissesMissingSessionNativeAlertBeforeGate` を追加する。本物Root/PushCoordinatorをconfigured・unlocked・onlineの取得済み一覧で起動し、不在IDの通知から本物UIAlertControllerが提示されることを確認する。lockedへ遷移しcontrolled認証を保留した後、認証gateのAXと本物controllerツリー上のalert消失を要求する。gateのPNGは固有OCRと旧alert文言不在で検査し、timeoutでも実PNGとcontroller診断を保存する。偽alert、private action、製品priorityの代替実装は使わない。既存操作・guardは維持する。現製品の結果は次BFT/実走まで未検証である。

r29はalert提示待ちでtimeoutし、lock優先の検査へ未到達だった。通知後の取得成功はpendingRequestedAt以降のlastFetchedAtを要求するため、同値一覧の再配信だけで前提成立を推測せず、通知直後の公開pending IDと通知後に異なる名前へ更新したSessionの実UIラベル、pending消費を順に確認する。初期画面・待機前stateと、前提timeout時のstate/PNGを保存する。製品のprivate timestampやcallbackは操作せず、alert後のlock条件も変更しない。

proper r30は初期一覧の判定でtimeoutし、通知前だった。行はSessionListViewでchildrenをignoreし、SessionListRowPresentationの名前・状態を含む完全labelとsessionRow IDを公開する。名前単体との配列完全一致は製品の契約と異なるため、初期/更新後とも同一要素の公開IDとpresentation由来の完全labelを厳密一致で要求する。初期待機前にもmodel/全label・ID/pending/scene/screenとPNG、timeout時にも同じ診断を保存する。部分一致への変更やalertの偽装は行わず、実alert表示後は何も押さずlockedへ移す条件を維持する。

r31の保存診断ではmodelはsessions、完全な行labelは実在する一方、UIKit列挙で取得したidentifierは全て空だった。SwiftUIが設定するIDと、この観測APIで取得可能な値は異なるため、ID取得を前提条件から外す。presentation由来の完全label、model.sessions、fixture repositoryの現在loaded値の完全一致を初期/更新後とも要求する。IDは診断に残すが合否根拠にせず、部分一致・待機時間延長・alert/lock条件変更は行わない。

## 実指dragによる下端操作配置の限定検査

`RootInteractiveTransitionTests/realRootFingerPanPreservesVisibleAttentionAndRecordsNativeTabGeometry` は本物Rootと計40件（承認待ち1件・通常39件）を使う。sceneはRootFingerPanAttention、scrollの1stepで既存180秒ACK契約を使い、親が指dragを1回行ってfresh AX/原寸画面を確認してからACKする。AXScrollToVisible/wheel/offset設定/privateAPI/XCUITestは使わない。

testは実offset増、可視一覧rowの有限frame、対応待ちのcanonical操作labelと有限・全可視frame、sessions状態を要求し、前後PNGとpublic AX/UIControl/UITabBar geometryを保存する。iOS26の56pt縮小・対応待ちとの配置やiOS18の非縮小をitems数やcontainer寸法だけで断定せず、fresh原寸画像の丸の実境界を別途確認する。通常7step・他testの期待・製品は変更しない。構文/lintと型検査/実走は分けて記録する。

## r38で追加する境界

compact承認カードは本物ReplyApprovalCardへisKeyboardVisible=trueを与える表示条件fixtureをAX5・428/375の2sceneで描画する。実キーボードの出現や閉鎖を実測したとは扱わない。全文AX、同font/実幅のText自然高参照、表示ボタン44pt、非交差、viewport到達を要求する。UsageStaleDTSEを1scene追加し、212→215枚を予定する。Usageはagent名を文字で描かずrowのAX childrenもignoreするため、statusがagent群より下かは自動測定できず、原寸画像の親/独立レビューとAX強制stackの静的確認で扱う。diff pathは省略許容のため新sceneを追加せず既存画像で末尾を確認する。

compactのviewportはcomponentを載せた合成windowのScrollViewであり、実SessionDetailのキーボード表示時の残り高さではない。自然高参照は測定専用の別Textへ適用し、実カードのframe/padding/lineLimitは改変しない。自然高・表示44pt・非交差のcomponent契約を検査する範囲に限定し、実keyboard＋SessionDetail統合の到達性は未検証とする。

Root regularflowは18だけ一覧topのlegacy-header-compose/legacy-header-compose-backを既存nonce/rawAXproof経路で追加する。実見出し右tapでdepth1/newChat、実Backで5秒内depth0/sessions一覧と見出し右操作の復帰を要求し、その後従来scroll/settings/sessionsを続ける（18計5step）。26通常7/対照8step・guardは変えない。Back後のscrollは現ownedwindowから再取得する。設定へのcompose追加や、スクロール後の見出しの代替入口は作らない。

## 失敗composerのAX5境界4scene

DraftFailedAX5/AX5SEとChatSendFailAX5/AX5SEを428×926・375×667に追加する。Draftは既存snapshot APIのspawn失敗をpublic sendで発生させ、同じspawnRejectedカタログと入力保持を確認する。既存DraftFailedの直接seedは変更しない。Chatは既存failedSendSnapshotModelのpublic send失敗を再用し入力保持を確認する。両方とも実viewへaccessibility5を適用し、製品・既存9定義・外部操作契約は変更しない。

既存SCREEN_SCENES（Draft）/DETAIL_SCENES（Chat）filterで部分描画する。4枚追加で全体は204→208枚を予定するが、実数は次の実走で確認する。新たな操作harnessは追加しないため、エラー全文・入力と送信の44pt最小領域・縦scroll到達性はsnapshotだけで操作保証せず、原寸画像レビューと必要な実操作の未確認範囲を親へ明示する。

r34の原寸画像でSE詳細の重なりと見出し省略が見つかったため、この4sceneだけprepareWindowで初期geometryを記録し、composerを包含する本物UIScrollViewを公開scrollRectToVisibleでエラー先頭rect、次に実content末尾へ移す。先頭rectと末尾はcontentの実frame/size/bounds/insetsから算出し、固定offsetは使わない。実offset、祖先viewportとwindow内の入力/送信各44pt・非交差、本文と公開toolbar要素の非交差、カタログ全文AXとそのframeのcontent内到達可能性を検査する。375×667は合成viewportであり実SE機種の操作証明ではない。AX全文だけでは字の描画・省略なしは保証しないため、見出し自然高とellipsisは親の原寸画像でも確認する。main4枚は下端、error-top4枚を追加し合計212枚を予定する（initialはgeometryのみで、defaultbottomを先頭画像と取り違えない）。公開scrollによる到達確認を指pan成功とは扱わず、Rootの別gesture probeと区別する。

## 2026-10-19 実操作結果の更新

- r45 Root run（iOS 18.3）は、画面に新規チャットが出た一方、test-owned router の `depth == 1` 待ちで timeout（exit 65）。tap がその router に届いたかは未確定のまま記録し、製品の遷移失敗とは断定しない。
- r46 の同 Root 実操作では、新規チャット表示と Back 後の一覧復帰を確認した。続く一覧スクロールは複数の操作後も AX 上の可視行が変わらず、`confirmed=false` で停止（exit 65）。offset assertion には到達していないため、製品のスクロール不具合とは判定しない。
- 独立診断では CUA の連続タッチ未成立、または複数 UIWindow 間の入力先不一致が候補だが、原因は未確定。追加の自動操作は止め、物理端末での一覧スクロールは未確認として残す。以前の timeout/失敗記録は履歴として保持する。
