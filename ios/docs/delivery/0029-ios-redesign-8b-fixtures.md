# 段階8b 撮影fixture

## 計画・範囲

### 追加依頼（同担当で継続）

- 前段の未コミット差分を保持し、一覧の展開・Shellデータ、pair比較NEW-2/5/7/8/17/27、特殊入力・使用量、DraftMore、FlowNext、windowImageの診断ログを撮影専用コードで扱う。
- 特殊状態は公開操作と制御可能なfixture応答を使用する。本番setter/APIは増やさない。送信・更新の待機Taskは撮影終了時に解除・キャンセルして終了を待つ。
- 248対応表を更新する。ビルド・テスト・描画は今回も専任へ引き継ぎ、実行しない。

- 担当: fixtures。既存の `DesignSnapshotRenderTests.swift` と撮影専用の `App/UITesting*` に限定する。本番ビュー・共通0020/0028は変更しない。
- 比較記録の指摘を見本HTML・8a画像・現fixtureで照合し、承認のエージェント、入力中、完了/失敗、質問、Flowの状態と会話を直す。
- 手組みのReply/Usage会話を本物のSessionDetailView経路へ移す。既存名を維持し、見本名との全数対応と未撮影を記録する。
- 品質設定: `ios/Makefile`、`ios/project.yml`、`ios/scripts/lint-raw-values.sh` を確認。追跡中のGitHub workflowはPages用のみ。スナップショットはUIテストを使わないunit-testターゲット。
- この担当はコード確認・`git diff --check` のみ。ビルド・テスト・描画・lint実走は専任検証担当へ引き継ぐ。XCUITestは禁止。

## 検証物

- 出力先: 自worktree `.verification/ios-redesign-stage8b/`。セッション: fixtures（2026-10-18）。この担当ではアプリ・サーバ・シミュレーターを起動しない。

## 前段の修正・反証・残り（追加依頼前の記録）

以下は前段の記録を保持したもの。現在状態は後述の「追加依頼の結果」を参照。行番号も前段時点。

変更ファイルは本記録、`ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift`、`ios/App/AppEnvironment+UITesting.swift` の3つ。本番ビュー、API契約、共通0020/0028は変更していない。

| 指摘 | 状態・根拠 |
| --- | --- |
| cards NEW-6: 承認Dark/SEDarkのエージェント | fixture修正。`DesignSnapshotRenderTests.swift:1045` の派生元をClaudeのReplyに変更。見本 `ReplyApprovalDark.dc.html:17` と見本/8aのReplyApprovalDark実画像で取り違えを確認。 |
| cards NEW-4: ReplySEDark | fixture修正。同ファイル:1052 を入力中のReplyTypingから派生。見本 `ReplySEDark.dc.html:17` の `state="typing"` と見本/8aの実画像を照合。キーボード自体は未撮影。 |
| cards NEW-7: ReplyDone/Error | fixture修正。同ファイル:1008 の短い会話・コスト行・API Errorを独立定義。見本 `Reply.dc.html:680` 以降のtailMapに合わせた。 |
| A2: FlowApprove/Next | fixture修正。同ファイル:1015。Approveはgit rmとDetailの長い会話。Nextはrunning・末尾git rm・3秒。見本FlowNextと8a実画像を照合。送信結果カードの名前・状態・レイアウトは本番側の担当。 |
| A2/NEW-8: ReplyQuestion/Fail/Plain | fixture修正。同ファイル:940 の成功コマンドと短い本文、:944 のCHECKS、:851 の回答キーを修正。ChatQuestion用のTESTを保持。単一/複数選択の意味と未回答を維持。 |
| A1/A2: RunEmpty/Text・Empty/Typing/Haiku | fixture修正。同ファイル:1001 以降。本物のSessionDetailViewとViewModelを使用（専用Destinationは:1963）。RunEmptyの8a実画像が白背景・上部なし・完了会話であることを確認。Haikuは入力文あり・思考強度なし。 |
| A1: その他通常入力/添付/権限・通常/low/na Usage | fixture修正。同ファイル:565 の分岐から本物の詳細画面へ。初期入力は公開操作で設定し、本番の撮影用API追加なし。読み込み完了を待って描画。 |
| A2: UsageLow/Na | fixture修正。`AppEnvironment+UITesting.swift:561`。lowはClaude5hとCursor APIだけ残量少、naはClaude2枠・Codex5hを保持し週次だけ欠落、Cursor取得不可。見本 `Reply.dc.html:529` のCMP_USE_DATAと照合。回帰テスト `DesignSnapshotRenderTests.swift:666` を追加したが未実行。 |
| A2: DraftCreated/モデル一覧 | fixture修正。同ファイル:991 のLotus・初回入力・Manual、NewChatSnapshotAPIのHaiku/miniを追加。DraftModelNa自体は未撮影。 |
| chat D2/NEW-5・添付 | fixture修正。同ファイル:766 のリンク・4列表、:987 のMarkdown箇条書き、:1809 の502/LOGプレビュー。実データの切り詰め警告は、巨大なダミー本文を追加して再現していない。 |
| pair-settings NEW-27 | fixture修正。同ファイル:1249。screen引数がempty環境を上書きし対応待ち2件を作っていたため、emptyをそのまま使用。専用設定fixtureの見出し余白・区間余白も修正。 |
| cards NEW-13: ReplyStarting | 反証・維持。本番 `SessionDetailView.swift:818` は最後の項目だけ実行中。本文がコマンドの後にある現fixtureはこの規則に一致。 |
| A3: Codex説明 | 範囲外・データなし。`PhloxNetworking/DTOs.swift:76` のApprovalDTOに説明欄なし、`Features/SessionDetail/ReplyApproval.swift:88` はnil。fixtureだけで説明を捏造しない。 |
| 新規シナリオ | ReplyModel（Sonnet既定）・ChatRename。公開操作で実際のモデルシート/名前変更アラートを表示する定義を追加。撮影は未実行。 |

### 残る範囲と判断事項

- **A1は部分修正**。`ReplyAttachErr*`・`ReplyPermFail`・`ReplySending`・`UsageStale*`・`UsageRefresh`・`UsagePop*` は状態を弱めず専用fixtureを維持。上部・本物のコマンドカード・Markdown・コスト行を共通化し、Sendingには本物のユーザーバブルと添付2枚を追加したが、詳細画面全体を経由していない。
- 本番 `SessionDetailViewModel.swift:72`（sendState）、:102（attachmentError）、:113（settingsChangeError）は外部から設定不可。全ケース移行のためだけに本番APIを拡張しない。残りを本物画面で再現する場合は、専用fixture APIが送信待機や各境界エラーを実際の公開操作から発生させる方式の設計が必要。
- `ReplyMore` は既存名を維持したが、メニューが開いた状態は未撮影。`DSInputBar.swift:916` のMenuは初期表示を外部指定できない。権限/思考メニュー、コピー選択、削除確認、OS通知・キーボードも同様に未撮影として下表へ記載した。
- `DraftSuggest` はfixtureが本番 `NewChatViewModel.swift:131` のsuggestionsを使用している。見本文言との差をfixtureの上書きで隠さず、本番ビュー担当の判断事項とする。
- `ChatExpandCmd` の出力は既に48件の成功/失敗行を持つ（同ファイル:720付近）。比較メモの「各1行」には該当しないため、出力増量はしない。

### 検証範囲

- 実行: コードと見本ソースの照合、上記の見本/8a画像の閲覧、`git diff --check`（終了コード0）。
- 未実行: lint、型チェック、静的解析、ビルド/リンク、単体テスト（追加した回帰テストを含む）、描画テスト、シミュレーター。専任検証担当による統合後の実走待ち。新しいPNGは作成していない。
- コミット・マージ・pushなし。検証プロセス/一時ファイルの起動・作成なし（本記録以外の検証用ファイルもなし）。

## 追加依頼の結果

変更は前段の3ファイルと `ios/App/UITestingNavigator.swift` の計4ファイル。後者はShell詳細のfixture ID変更への追従。本番ビュー・setter・DEBUG本番API、共通0020/0028は変更していない。

| 依頼 | 結果・根拠 |
| --- | --- |
| 一覧の展開 | 修正。`DesignSnapshotRenderTests.swift:131,278,380`。Shell/List/Multi/SE/DTはrefactor、Manyはmany-refactorを展開。CollapsedはSimpleBudgetのみ開き子は閉じる。見本 `List.dc.html:345,377,383` とListCollapsed実画像を照合。AllAttentionは同HTML:390の通りrefactor自体がない。 |
| Shellデータ | 修正。`AppEnvironment+UITesting.swift:53` からListと同じ採用データを使用。`UITestingNavigator.swift:36` と撮影側詳細IDも追従。Design polish等を除去。待ち規則は変更しない。 |
| ListCollapsed内訳 | 統合時に撮影データを調整。閉じたPhloxのwrite-unit-testsとadr-0044を完了未読とし、実行中2・未読3を実ドメインで作る。C-19により対応待ちのRose（エラー）は内訳へ数えない。見本の「エラー1」はこの決定と両立しないため除外を維持する。 |
| pair NEW-2 | 修正。同撮影ファイル:1236。PairGateDarkを認証失敗へ。見本HTMLと見本実画像の失敗カードを確認。 |
| pair NEW-5 | 修正。同:1362。SetDisc/SetDiscDarkのresolveへunreachableHostを渡し、対応待ちデータは空にした。接続先は保存済み。見本SetDiscと8a実画像を照合。 |
| pair NEW-7 | 修正。同:1278。ライトはv=1・hostなし（P3）、ダークはv=1・不正token（P5）を実パーサーへ渡す。見本 `PairParseErr.dc.html:17` / `PairParseErrDark.dc.html:17` に一致。秘密値除去・小文字16進の本番仕様や技術値の固定期待値は変更しない。 |
| pair NEW-8 | 修正。同:1379付近。SetDarkだけダーク選択、SetDiscDark/SetSEDarkはシステム選択でダーク環境。各ラッパーHTMLとSetDisc見本画像を確認。 |
| pair NEW-17 | 原因未確認。SEの安全領域（上20・下0）と `DSPlatformTabView.swift:66,100` のiOS18標準TabView/アクセサリを照合。撮影データの取り違えは見つからず、レイアウト実走禁止のため原因を断定しない。推測の安全領域補正はしない。 |
| pair NEW-27 | 前段のempty環境・見出し/余白修正を維持。PairSettings/Test系がemptyでバッジを作らないことをコードで再確認。バー本体は本番側の範囲。 |
| A1特殊状態 | 修正。同:532以降。本物SessionDetailViewへpreparedModelを渡す。送信はsendMessage→未完了fixture応答、権限はselectPermission→APIエラー、添付枚数/サイズは実際の追加失敗、読込失敗は公開attachmentLoadFailed。状態の直接代入なし。成功・例外とも待機を解除/キャンセルしTask終了をawait。 |
| A1使用量 | 修正。同:564以降・SnapshotUsageSource。初回load成功後、次の公開loadで失敗/未完了応答を作る。Stale/Refresh/Popも本物詳細画面。Popは実際のUsageRingRow.buttonをAXで開く。実走未検証。 |
| DraftMoreDT/SE | 手組みの固定51pt高メニューと重ね合わせを削除。本物NewChatViewの「思考の強さと権限を変更」をAXで開く。同:1622付近。見本 `Draft.dc.html:158,371` と見本/8aのDraftMoreDT実画像を照合。OSメニューをソースで偽造しない。展開・描画は未検証。 |
| FlowNext | 修正。同:1054にnextSessionName=Tulip/nextIsQuestion=trueを指定。cards担当の本番変更統合が前提。同担当worktreeの `SessionDetailViewModel.swift:841,851` に既定引数付き追加があることを読み取り確認。現worktree単独の旧enumには引数がない。 |
| iOS18警告 | 同:1667のwindowImageに全呼出元の盤面ID、作成・レイアウト・drawHierarchy前後・破棄のstderrマーカーを追加。失敗時defer解放と成功時解放を維持。警告抑制なし。実ログなしのため原因は未特定。 |

以下はfixtures担当の旧基点での調査結果。統合後の添付実装で解消した（下の追記参照）:

- Dim3盤面: `SessionDetailViewModel.swift:1033,1040` は寸法超過も「画像を読み込めませんでした」へまとめる。`macos/Packages/AgentDomain/Sources/ImageAttachmentKit/ImageAttachmentPreparer.swift:125` は寸法超過を検出するが、見本の専用文言への公開経路がない。
- Total: `macos/Packages/AgentDomain/Sources/AgentDomain/ImageAttachmentLimits.swift:5` は4枚・各20,000,000B・合計80,000,000B。`SessionDetailViewModel.swift:299,303,321` の順では、前2条件を通って合計超過になる入力は存在しない。
- 上記4場面は撮影不可の理由をログに出し、PNGを作らない。専用偽画面は削除。既存の単体テスト・アサーションの削除/skip化はしていない。以前の手組みPNGを新しい本番状態の根拠に流用しない。

統合担当の追記: 上記4場面の除外を撤去し、元の名前のまま本物のSessionDetailViewを撮る構成へ戻した。Dim3場面はscale=1の8001×1 PNGを公開addAttachmentsへ渡してA4を発生させる。Totalは既存AttachmentIntakeTestsと同じ正式なSessionDetailRecoveryへ70MBの元PNGと小画像2枚・各プレビューを復元し、20MBの有効PNG追加でA3を発生させる。追加前のattachmentErrorがnil、拒否後の添付が元どおりであることも検査する。通常入力の4枚×各20MBでは80MBを超えないため、この場面は復元状態への防御ケースである。本文・プレビュー・元画像は保持し、状態setter・本番画面の模造は使わない。旧attachmentLoadFailed呼出は選択順Resultを受ける公開APIへ追従した。再描画は未実走。

SEの最小確認計画: 現行windowImageはconnected UIWindowSceneに375×667のwindow.frameと上20/下0のsafe areaを指定する。実際のsimulatorがiPhone16の場合、scene/screenの物理的な幅と仮想window幅が異なる。原因は未確定のため補正せず、iOS18のListSE/SetSE/Shell狭幅sceneで、実デバイス名・screen/scene/windowのbounds・hostのsafeAreaInsets・標準TabViewの可視範囲をまず記録する。同じ375×667のSE3 simulatorが利用可能なら同sceneだけ再描画して差を比較する。この計画を専任検証担当へ共有済み。OS内部ビューの幅や制約は操作しない。

回帰テスト `specialFixturesUsePublicTransitionsAndFinishPendingRequests` を追加（同:660、未実行）。公開操作での権限/添付エラー、送信待機とキャンセル後の終了、使用量の成功→失敗→更新中→成功を検査する。

実行はコード・見本ソース・既存PNGの照合、248見本名と対応表の照合、`git diff --check` のみ。lint・型チェック・静的解析・ビルド/リンク・単体/描画テスト・シミュレーターは未実行。AXでのネイティブMenu/Popover展開、iOS18警告/SEタブ切れ、統合後のFlowNextは専任の確認待ち。アプリ・検証プロセスの起動、入力ソース変更、XCUITest、コミット・マージ・pushはない。

## 見本名との全数対応（追加依頼後）

`ios/docs/specs/ClaudeDesign/*.dc.html` の248ファイルをファイル名で照合。8a画像の存在は過去記録であり、8bの描画成功を意味しない。既存PNG名は維持し、`ReplyModel` と `ChatRename` を追加した。`Detail` はiOS18で既存名 `Detail18` を用いる。

| 見本名（.dc.html） | 対応／未撮影理由 |
| --- | --- |
| `Chat` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatCopy` | 未撮影: OS標準の選択メニュー |
| `ChatCopyDark` | 未撮影: OS標準の選択メニュー |
| `ChatDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatDelete` | 未撮影: 本番確認ダイアログに初期表示引数なし |
| `ChatDone` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatEmpty` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatError` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatErrorDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatExpandCmd` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatExpandCmdDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatExpandCmdDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatExpandDiff` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatExpandDiffDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatFetchErr` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatFetchErrDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatIdle` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatIdleDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatLoading` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatLong` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatMenu` | 未撮影: 本番Menuに初期表示引数なし |
| `ChatQuestion` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatQuestionDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatRename` | 同名シナリオ追加・未撮影 |
| `ChatSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatSEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatSendFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatSendFailDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatSpec` | 説明用・アプリ画面撮影の対象外 |
| `ChatStall` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatStallDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatStallDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatSub` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatSubDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatThinking` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatThinkingDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatUnsupported` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ChatUnsupportedDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DS` | 説明用・アプリ画面撮影の対象外 |
| `DSDark` | 説明用・アプリ画面撮影の対象外 |
| `Detail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Detail18` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DetailDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DetailDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DetailSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DetailThumb` | 未撮影: 注釈用縮小図 |
| `Dialogs` | 説明用・アプリ画面撮影の対象外 |
| `DialogsDark` | 説明用・アプリ画面撮影の対象外 |
| `DialogsSpec` | 説明用・アプリ画面撮影の対象外 |
| `Draft` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftCreated` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftCreating` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftCreatingDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftEffort` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftEntryEmpty` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftFailed` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftFromProject` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftModel` | 未撮影: 対応する同名の撮影経路なし |
| `DraftModelDark` | 未撮影: 対応する同名の撮影経路なし |
| `DraftModelNa` | 未撮影: 対応する同名の撮影経路なし |
| `DraftMoreDT` | 本物Menuを開く経路へ変更。AX展開・8b撮影は未検証 |
| `DraftMoreSE` | 本物Menuを開く経路へ変更。AX展開・8b撮影は未検証 |
| `DraftPerm` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftPermCodex` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftPermCursor` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftPermDanger` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftPermDangerCodex` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftProject` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftProjectDark` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftProjectSE` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `DraftSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftSEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `DraftSpec` | 説明用・アプリ画面撮影の対象外 |
| `DraftSuggest` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Errors` | 説明用・アプリ画面撮影の対象外 |
| `ErrorsDark` | 未撮影: 対応する同名の撮影経路なし |
| `FlowApprove` | 同名シナリオ（8a画像あり、8b未撮影） |
| `FlowMenu` | 未撮影: 本番Menuに初期表示引数なし |
| `FlowNext` | 同名シナリオ（8a画像あり、8b未撮影） |
| `FlowUsage` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Glance` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceCatalog` | 未撮影: 対応する同名の撮影経路なし |
| `GlanceCatalogDark` | 未撮影: 対応する同名の撮影経路なし |
| `GlanceHome` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceHomeDark` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceHomeEmpty` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceIsland` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceIslandExp` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceLockDark` | glanceWidgets / glanceLiveActivity の部品一覧で描画。見本と同じ配置は未撮影 |
| `GlanceNotifs` | 未撮影: 通知のOS表示 |
| `GlanceNotifsDark` | 未撮影: 通知のOS表示 |
| `GlanceSpec` | 説明用・アプリ画面撮影の対象外 |
| `Launch` | 説明用・アプリ画面撮影の対象外 |
| `Layers` | 説明用・アプリ画面撮影の対象外 |
| `List` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListAllAttention` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListCollapsed` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListEmpty` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListEmptyDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListError` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListError401` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListJudging` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListLoading` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListLoadingDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListManyScrolled` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListManyTop` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListMulti` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListMultiDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListOffHost` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListOffHostDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListOffNet` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListOffUnknown` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListPressed` | 未撮影: 押下中の操作 |
| `ListPull` | 未撮影: 引っ張り中の操作 |
| `ListSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListSEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ListSpec` | 説明用・アプリ画面撮影の対象外 |
| `ListTapDetail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Main` | 説明用・アプリ画面撮影の対象外 |
| `Mapping` | 説明用・アプリ画面撮影の対象外 |
| `Pair` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairApplying` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairConnectFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairConnectFailDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairConnectFailDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairConnecting` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairGate` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairGateAuth` | 未撮影: Face IDのOS認証 |
| `PairGateDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairGateFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairNoCam` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairParseErr` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairParseErrDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairRescan` | 未撮影: カメラ入力 |
| `PairRescanDone` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairSEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairScan` | 未撮影: カメラ入力 |
| `PairScanSE` | 未撮影: カメラ入力 |
| `PairSettings` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairSpec` | 説明用・アプリ画面撮影の対象外 |
| `PairTestFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairTestFailDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairTestOk` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairTesting` | 同名シナリオ（8a画像あり、8b未撮影） |
| `PairUnreach` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Reply` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalDiff` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalDiffDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalDiffDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalDiffSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalFailDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyApprovalSEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyAttach` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyAttachDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyAttachErr` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyAttachErrDim` | 同名シナリオ復元済み: 実8001px画像の受理失敗でA4、8b未撮影 |
| `ReplyAttachErrDimDark` | 同名シナリオ復元済み: 同じ公開操作、8b未撮影 |
| `ReplyAttachErrDimSE` | 同名シナリオ復元済み: 同じ公開操作、8b未撮影 |
| `ReplyAttachErrLoad` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyAttachErrSize` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyAttachErrTotal` | 同名シナリオ復元済み: 正式なrecoveryで過大な元画像を復元後、有効画像の追加でA3、8b未撮影 |
| `ReplyCodex` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyDone` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyEffort` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyEffortDT` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyEffortDark` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyEffortSE` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyEmpty` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyError` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyHaiku` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyKeyboard` | 未撮影: OSキーボード |
| `ReplyKeyboardAppr` | 未撮影: OSキーボード |
| `ReplyKeyboardApprDark` | 未撮影: OSキーボード |
| `ReplyModel` | 同名シナリオ追加・未撮影 |
| `ReplyMore` | 同名シナリオはあるが、メニューを開いた状態は未撮影 |
| `ReplyPerm` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyPermDT` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyPermDanger` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyPermDark` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyPermFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyPermSE` | 未撮影: OSメニュー／シートの初期表示経路なし |
| `ReplyQuestion` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyQuestionDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyQuestionDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyQuestionFail` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyQuestionPlain` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyQuestionSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyRunEmpty` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyRunText` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplySE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplySEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplySending` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplySpec` | 説明用・アプリ画面撮影の対象外 |
| `ReplyStarting` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ReplyTyping` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Review181` | 説明用・アプリ画面撮影の対象外 |
| `Review212` | 説明用・アプリ画面撮影の対象外 |
| `ReviewDiff` | 説明用・アプリ画面撮影の対象外 |
| `ReviewMap` | 説明用・アプリ画面撮影の対象外 |
| `Revision20261017` | 未撮影: 対応する同名の撮影経路なし |
| `SetDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetDisc` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetDiscDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetSEDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetUse` | 同名シナリオ（8a画像あり、8b未撮影） |
| `SetUseSpec` | 説明用・アプリ画面撮影の対象外 |
| `Shell` | 同名シナリオ（8a画像あり、8b未撮影） |
| `Shell18` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ShellDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ShellDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ShellOffline` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ShellSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `ShellThumb` | 未撮影: 注釈用縮小図 |
| `UsageKeyboard` | 未撮影: OSキーボード |
| `UsageLow` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageLowDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageLowDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageLowSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNa` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNaDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNaDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNaSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNormal` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNormalDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNormalDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageNormalSE` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsagePop` | 本物詳細画面のボタンから開く経路へ変更。AX展開・8b撮影は未検証 |
| `UsagePopDT` | 本物詳細画面のボタンから開く経路へ変更。AX展開・8b撮影は未検証 |
| `UsagePopDark` | 本物詳細画面のボタンから開く経路へ変更。AX展開・8b撮影は未検証 |
| `UsagePopSE` | 本物詳細画面のボタンから開く経路へ変更。AX展開・8b撮影は未検証 |
| `UsageRefresh` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageStale` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageStaleDT` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageStaleDark` | 同名シナリオ（8a画像あり、8b未撮影） |
| `UsageStaleSE` | 同名シナリオ（8a画像あり、8b未撮影） |
