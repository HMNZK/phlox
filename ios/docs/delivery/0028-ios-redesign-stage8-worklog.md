---
status: active
last-verified: 2026-10-18
---

# 0028: iOS 再設計 段階8a — 起動・接続・設定・エラーと描画場面（作業記録）

> **役割**: [計画書0020](0020-ios-redesign-plan.md) 段階8のうち、仕様11章と描画テストの不足を扱う。
> **仕様**: [再設計仕様11章](../specs/redesign-2026-10.md)、ADR [0046](../adr/0046-align-ios-with-mac.md)・[0047](../adr/0047-replace-xcuitest-with-render-tests.md)。

## 1. 変更

- 起動ゲート、初回 QR 接続、QR 再接続、スキャン不可・処理中・成功・読取失敗、接続中・20秒失敗、疎通テスト、再接続の見出し・説明・操作を各 `Pair*` 盤面へ揃えた。初回接続は名前・接続先・経過秒数を表示し、一覧取得成功で閉じる。20秒で応答がない場合は確認項目と「再試行」「閉じる」を出す。
- 設定を「接続 → 通知 → セキュリティ → 外観 → このアプリについて」に並べた。Face ID / Touch ID の端末名を使い、DotGothic16 のライセンス行を保った。使用量用の設定区画は置かない。
- `ErrorPresentation` に原因・次の操作・等幅の技術値・無彩色指定を持たせ、F1〜F8、U1〜U3、P1〜P6、Q1、C1、T1、G1、K1、D1、D3〜D6 の画面を整えた。429（F3）は赤色にしない。D1 は HTTP 応答ならステータスだけ、通信失敗なら `NSURLError` 等を最後に表示する。削除失敗 D6 の技術値もアラート内で最後に等幅表示する。
- `phlox://pair` が起動復元・ロック解除より前に処理される経路を修正し、両方の完了まで保留する。通知の解除後処理は既存の保留経路を維持した。`testPairingURLWaitsForBootstrapAndUnlock` を追加した。
- `DesignSnapshotRenderTests.swift` に不足する盤面名の場面を追加した。名前・サイズ・ダーク／Dynamic Type 条件に応じた2倍 PNG を出す。`PairNoCam` の記号はシンボル未描画を確認したため、カメラ輪郭と斜線を SwiftUI の図形で描いた。
- 接続失敗カードと再スキャン操作が重なっていた表示を縦に積み、原因・次の手順・技術値が隠れないようにした。接続欄のアイコンと通知・Face ID スイッチの色も盤面に合わせた。
- 使われなくなった `DSConnectingIndicator.swift` を削除し、接続中画面の描画を見本に合わせた。仕様11章、ADRの追記、`architecture/overview.md`、delivery 索引を更新した。

## 2. 消したもの・テストの変更

- 削除ファイル: `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Molecules/DSConnectingIndicator.swift`。呼び出し元は無く、この部品だけを対象とするテストも無かった。
- 独立テストの削除・skip 化・期待値の緩和は無い。
- 名称と確認内容を更新した既存テスト:

| 前 | 今 |
|---|---|
| `testUnreachableHostShowsEndpointAndNoResponse` | `testUnreachableHostShowsEndpointAndLastFetchInTechnicalLine`。接続先と最終取得時刻を技術行で確認 |
| `testAuthenticatingStatusMatchesCamp` | `testLockAndAuthenticationCopyMatchesCamp`。ロック中と認証中の文言を確認 |
| `testFaceIDFrameMetricsMatchCamp` | `testUnlockButtonMetricsMatchCamp`。解除ボタンの寸法を確認 |
| `successMessage は name あり/なしで文言が変わる` | `成功の見出しは name を含み、再接続の案内は接続先を保つ` |
| `testFailedDeleteShowsError` | 原因・次の操作・`HTTP 403 許可が必要です` の順を確認し、D6 の表示項目の確認を追加 |
| QR の P5 期待文言 | `Errors.dc.html` の「64 桁の小文字 16 進ではない」を確認。`Pair.dc.html` は「小文字」が無く見本どうしが食い違うが、判定（`PairingPayload` は `[0-9a-f]{64}` だけを通す）と合う Errors を正とした（2026-10-18 ユーザー決定） |
| `commitRenameKeepsNameOnFailure` | Mac の理由 `boom` を確認 → 技術行 `HTTP 500 boom` を確認（理由を消さず catalog の技術行の形にした） |
| 承認の応答失敗（拒否） | 旧文言 → D4 の文言で、選んだ操作名「拒否」が入ることを確認 |

- 追加したテスト:
  - XCTest 6件: `testPairingURLWaitsForBootstrapAndUnlock`、`testImagePreparationFailureUsesA5CopyAndKeepsDraft`、`testRateLimitedSendKeepsNeutralCatalogColorAndTechnicalDetail`、`testF1ThroughF8UseCatalogCopyAndOrder`、`testServerFailureUsesCatalogOrderAndMonospaceDetail`、`testTransportFailureUsesCatalogCopy`。
  - Swift Testing 4件: NewChat の A5、QR の P1〜P5、P6/K1、D1 通信失敗の技術値順を確認。

## 3. エラー文言の対応

変更前は `PhloxError` の汎用タイトル／本文、画面ごとの短文、通信エラーの `localizedDescription` が混在していた。下表は変更前の表示と現在の対応である。技術値はカタログ例または実際に得た値を末尾へ置く。

| ID | 変更前の表示 | 現在の対応 |
|---|---|---|
| F1 | 「認証が必要です」「トークンが無効か期限切れです」 | 「Mac に接続を断られました」→保存鍵の状態→QR 再読込→HTTP 401 |
| F2 | 「Mac に接続できません」／圏外かスリープ | 「Mac に届きません」→スリープ・Tailscale→起動して再試行→技術行「Mac から応答がありません」。`PhloxError.unreachable` は接続先を持たないため、カタログ例の `100.64.0.1:8765 · 接続がタイムアウト` は出さない |
| F3 | 「混雑しています」「リクエストが多すぎます」 | 「Mac が混み合っています」→Retry-After と再試行時刻。`isNeutral` で無彩色 |
| F4 | 「サーバエラー (status)」と生の応答文 | 「Mac の Phlox でエラーが起きました」→再試行・再起動→HTTP status と応答文 |
| F5 | 「Mac の更新が必要です」または decode 説明を本文へ連結 | 「Mac の応答を読めません」→両アプリ更新→未対応機能または decode 値 |
| F6 | 「通信エラー」＋通信理由 | 「通信が途中で切れました」→通信回復後に再試行→`NSURLError` |
| F7 | 「セッションを開始できません」＋理由だけ | 「セッションを作れませんでした」→未作成であること→入力へ戻した指示を再送→Mac の拒否理由 |
| F8 | 「見つかりません」「削除されたか存在しません」 | 「このセッションは見つかりません」→一覧へ戻る→HTTP 404。`PhloxError.notFound` に ID が無いため session ID は出さない |
| U1 | 圏外・機内モードと自動再接続を一文で表示 | 見出し「インターネットにつながっていません」→通信復帰後の自動再接続を別行で表示 |
| U2 | スリープ・Tailscale と自動再接続を一文で表示 | 見出し「Mac に届きません」→起動後の自動再接続／手動操作→接続先・最終取得時刻 |
| U3 | 応答待ちの説明だけ | 「接続を確かめています」→最大20秒待つ→待機を別行で表示 |
| P1 | 「ペアリング用の QR コードではありません」 | Phlox 用でない理由→Mac の QR を読む→読み取った URL を等幅表示 |
| P2 | 「未対応の QR バージョンです」 | 対応外版の理由→両アプリ更新・QR再表示→`phlox://pair` 値 |
| P3 | 「ホスト情報が見つかりません」 | 接続先が無い理由→QR再表示→欠けた URL 値 |
| P4 | 「ポート番号が不正です」 | 有効範囲外の理由→Mac の設定確認→`port=99999` |
| P5 | 「トークンが不正です」 | トークン形式の理由→QR再表示→「64 桁の小文字 16 進ではない」 |
| P6 | 「画像から QR コードを読み取れませんでした」 | 「画像から QR を見つけられません」→QR が写っていない理由→読みやすい画像を選ぶ。「写真から読み取る」を維持 |
| Q1 | 「Mac に接続できませんでした」＋Tailscale／QR再表示 | 保存済み接続先から応答が無い理由→Tailscale確認とQR再読込→`GET /sessions · 無応答` |
| C1 | 20秒待機後も接続できない旨の一文 | 接続先を保存した状態→3つの確認項目→再試行／閉じる→実際の endpoint と20秒無応答 |
| T1 | 「到達不可 · Mac がスリープ中の可能性」 | 「Mac に届きません」→スリープ・Tailscale→確認後に再テスト→`GET /sessions · 無応答` |
| G1 | 「認証に失敗しました。もう一度お試しください。」 | 「認証できませんでした」→Face ID が本人確認できなかった理由→Face ID 再試行またはパスコード |
| K1 | シミュレータ向けの長いカメラ利用不可案内 | 「カメラを使えません」→許可されていない状態→QR画像を写真から読む。無彩色 |
| D1 | 見出しと「メッセージの取得に失敗しました」を連結 | 「会話を読み込めませんでした」→Mac から受け取れない／3秒ごとに再取得→HTTP status または `NSURLError` を等幅の末尾行へ |
| D2 | 対応するアプリ文言なし | `Errors.dc.html` に D2 の項目が無い。新しい文言や機能は作らず未解決として記録 |
| D3 | `PhloxError` 本文または「承認情報の取得に失敗しました」 | 承認内容を受け取れない理由→読み直し中は承認・却下不可→技術値 |
| D4 | 「承認を送信できませんでした（Mac に接続できません）」 | 「応答を送れませんでした」→「（選んだ操作名）」は未達→再選択→送信失敗の技術値。カタログの「許可」は例なので、拒否・このセッション中は許可・キャンセルではその名前を出す |
| D5 | 「送信に失敗しました · title」 | 「送信できませんでした」→本文・添付は入力欄に戻る→送信ボタンで再送→技術値 |
| D6 | 「削除に失敗しました」または `PhloxError` の一般本文 | 「削除できませんでした」→対象と子孫が残る→閉じる／再削除→技術値。アラート内で技術行を等幅表示 |
| A1 | 枚数上限の文言 | カタログどおり「画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。」 |
| A2 | 1枚のサイズ超過 | カタログどおり「画像は1枚あたり20MBまでです」 |
| A3 | 合計サイズ超過 | カタログどおり「画像は合計80MBまでです」 |
| A4 | 寸法超過 | カタログどおり「画像は各辺8000ピクセルまでです。必要な部分を切り出してください」 |
| A5 | `localizedDescription` 由来の可変文言 | 「画像を読み込めませんでした」に統一し、本文と添付を残す |

カタログ外の文言は次の理由で残す。

- セッション作成の応答を受け取れず、作成済みか判断できない場合は「作成結果を確認できませんでした」とする。F7 は明示的な作成拒否なので同じ扱いにすると重複作成を招く。
- モデル・権限・推論強度の保存失敗や名前変更の入力エラーは、API取得／送信・接続・QR のエラー分類ではない。選択値の未変更または入力保持を説明する局所文言を使う。
- 接続先未設定、入力検証、読み込み中、成功、削除確認はエラーではなく状態・確認の文言。

## 4. 描画テストの場面

盤面は `.verification/ios-redesign/design-boards/`、出力は `.verification/ios-redesign-stage8a/snapshots/`。iOS 26.2 と iOS 18.3 それぞれ198 PNG、合計396 PNGを出力した。サイズは盤面どおりの2倍。既存の場面名と出力内容は維持し、段階7の93場面に対して今回105場面を追加した。

追加した場面名（見本名と同じ）:

- Pair（23）: `Pair`, `PairApplying`, `PairConnectFail`, `PairConnectFailDT`, `PairConnectFailDark`, `PairConnecting`, `PairDT`, `PairDark`, `PairGate`, `PairGateDark`, `PairGateFail`, `PairNoCam`, `PairParseErr`, `PairParseErrDark`, `PairRescanDone`, `PairSE`, `PairSEDark`, `PairSettings`, `PairTestFail`, `PairTestFailDark`, `PairTestOk`, `PairTesting`, `PairUnreach`。
- Settings（7）: `SetDT`, `SetDark`, `SetDisc`, `SetDiscDark`, `SetSE`, `SetSEDark`, `SetUse`。`FlowUsage` も追加。
- Shell（6）: `Shell`, `Shell18`, `ShellDT`, `ShellDark`, `ShellOffline`, `ShellSE`。
- Detail（3）: `DetailDT`, `DetailDark`, `DetailSE`。
- Chat（19）: `ChatDT`, `ChatDark`, `ChatErrorDark`, `ChatExpandCmdDT`, `ChatExpandCmdDark`, `ChatExpandDiffDark`, `ChatFetchErrDark`, `ChatIdleDark`, `ChatLong`, `ChatQuestionDark`, `ChatSE`, `ChatSEDark`, `ChatSendFailDark`, `ChatStallDT`, `ChatStallDark`, `ChatSub`, `ChatSubDark`, `ChatThinkingDark`, `ChatUnsupportedDark`。
- Draft（5）: `DraftCreated`, `DraftCreatingDark`, `DraftMoreDT`, `DraftPermDangerCodex`, `DraftSEDark`。
- List（9）: `ListDark`, `ListEmptyDark`, `ListLoadingDark`, `ListManyScrolled`, `ListManyTop`, `ListMultiDark`, `ListOffHostDark`, `ListSEDark`, `ListTapDetail`。
- Reply（20）: `ReplyApprovalDark`, `ReplyApprovalDiffDT`, `ReplyApprovalDiffDark`, `ReplyApprovalDiffSE`, `ReplyApprovalFailDark`, `ReplyApprovalSEDark`, `ReplyAttachDark`, `ReplyAttachErrDim`, `ReplyAttachErrDimDark`, `ReplyAttachErrDimSE`, `ReplyAttachErrLoad`, `ReplyAttachErrSize`, `ReplyAttachErrTotal`, `ReplyDone`, `ReplyError`, `ReplyQuestionDT`, `ReplyQuestionDark`, `ReplyQuestionSE`, `ReplySE`, `ReplySEDark`。
- Usage（12）: `UsageLowDT`, `UsageLowDark`, `UsageLowSE`, `UsageNaDT`, `UsageNaDark`, `UsageNaSE`, `UsageNormalSE`, `UsagePopDT`, `UsagePopSE`, `UsageStaleDT`, `UsageStaleDark`, `UsageStaleSE`。

撮らない46盤面と理由:

- `ChatCopy`, `ChatCopyDark`, `ChatMenu`, `ChatRename`, `ChatDelete`: OS 標準の選択メニュー／コンテキストメニュー／入力付きアラート。
- `DraftEffort`, `DraftModel`, `DraftModelDark`, `DraftModelNa`, `DraftPerm`, `DraftPermCodex`, `DraftPermCursor`, `DraftProject`, `DraftProjectDark`, `DraftProjectSE`: OS の選択メニューまたはシートを開いた状態。
- `ReplyEffort`, `ReplyEffortDT`, `ReplyEffortDark`, `ReplyEffortSE`, `ReplyModel`, `ReplyPerm`, `ReplyPermDT`, `ReplyPermDark`, `ReplyPermSE`: OS 標準の選択メニュー／シート。
- `FlowMenu`: OS 標準メニュー。
- `ReplyKeyboard`, `ReplyKeyboardAppr`, `ReplyKeyboardApprDark`, `UsageKeyboard`: OS 標準キーボード。
- `ListPressed`, `ListPull`: 押下中と引っ張り中の操作状態。入力操作の合成をしないため撮らない。
- `PairGateAuth`: Face ID の OS 認証シート。`PairRescan`, `PairScan`, `PairScanSE`: カメラの読取画面。
- `Glance`, `GlanceHome`, `GlanceHomeDark`, `GlanceHomeEmpty`, `GlanceIsland`, `GlanceIslandExp`, `GlanceLockDark`, `GlanceNotifs`, `GlanceNotifsDark`: 段階7で確認済み。
- `DetailThumb`, `ShellThumb`: 注釈用の縮小図で、アプリ画面ではない。
- `*Spec`, `Review*`, `Mapping`, `Layers`, `Main`, `Launch`, `DS*`, `Errors`, `Dialogs*`: 説明用盤面。場面数223のアプリ画面盤面には含めない。

## 5. 見本との比較・残差

`Pair*` と `Set*` の出力を盤面画像と並べて開いた。`PairConnectFail` の下部操作が隠れていた問題は、上部の伸長を外してボタン前に余白を置き、2操作を画面内へ戻した。20秒失敗は盤面の3確認項目・接続先・再試行・閉じるを表示する。`PairNoCam` は K1 の原因と写真から読む案内を両方表示する。`PairGate` のロック印は輪郭線に揃えた。`PairUnreach` はカードと再スキャン操作の重なりを解消し、技術行まで表示する。接続設定ボタンのアイコン背景を外し、通知・Face ID スイッチを見本の緑にした。

- Settings の盤面PNGでは再接続・疎通テストの2行が出ていない一方、`SetUseSpec.dc.html` と `SetUse.dc.html` は接続状態の下に両方を指定している。画面には仕様ソースどおり2行を表示したため、PNG と縦方向の内容量に差が残る。接続・通知・セキュリティ・外観・About の順とライセンス行は維持。
- `PairUnreach` の盤面には QR カメラ映像の見本があるが、iOS Simulator はカメラを提供しないため、出力は黒い背景になる。エラーカードは撮影し、カメラ背景は未検証。
- `PairUnreach` 盤面の技術行は `GET http://100.64.0.1:8765/sessions · 無応答`、Errors の Q1 は `GET /sessions · 無応答`。依頼のエラーカタログに従い、画面は Q1 の短い技術行を使う。
- `PairConnectFail` は iOS の日本語フォント幅により、盤面で末尾の「る」が折り返す3行目が1行に収まる。`PairNoCam` も案内文の折り返しと図形字形に差が残る。
- `PairConnectFailDT`（Dynamic Type 最大）は、説明文と下に固定したボタンが重なる。未修正で、段階 8b で直す。
- 段階7以前の既存画面の差は、全数の見比べをしないまま 8a を打ち切ったため一覧にしていない。段階 8b の見比べで扱う。見比べの途中で記録した差: `List` の盤面は対応待ち 3 件、アプリはエラー・無応答を含めて 5 件と数える（一覧の分類の差）。アプリの数え方のまま残す（2026-10-18 ユーザー決定）。

## 6. 検証

テストはすべて `~/.agents/scripts/compact-test` 経由。iOS 26.2 と iOS 18.3 の描画は同時に実行していない。iOS 26 は `bootstatus -b` 完了後20秒待ってから実行し、完了後に指定端末だけ shutdown した。

| 検証 | 結果 | exit | ログ |
|---|---|---:|---|
| 変更前 SwiftPM | stage7 の確認済み XCTest 371 + Swift Testing 619 = 990 | 0 | `.verification/ios-redesign-stage7/logs/unit-freshness-final.log` |
| 変更後 SwiftPM | XCTest 377 + Swift Testing 623（103 スイート）= 1000 成功・失敗 0 | 0 | `.verification/ios-redesign-stage8a/takeover/unit.log` |
| `make -C ios generate` | 生成成功 | 0 | 手元で実行 |
| 指定 `xcodebuild build` / PhloxMobile | `BUILD SUCCEEDED` | 0 | `.verification/ios-redesign-stage8a/takeover/build.log` |
| 指定 `make -C ios snapshot` / iOS26.2 | 3 テスト・2 スイート成功、`TEST SUCCEEDED` | 0 | `.verification/ios-redesign-stage8a/takeover/snap26.log` |
| 指定 `make -C ios snapshot` / iOS18.3 | 3 テスト・2 スイート成功、`TEST SUCCEEDED` | 0 | `.verification/ios-redesign-stage8a/takeover/snap18.log` |
| `make -C ios lint` | `lint-raw-values: OK` | 0 | 手元で実行 |
| `rg -n '#available\(iOS 26' ios --type swift` | 6箇所・3ファイル、すべて DesignSystemIOS 共通部品 | 0 | 手元で実行 |
| `git diff --check` | 指摘なし | 0 | 手元で実行 |

途中の失敗と修正:

- 初期のSwiftPMでは `DSRadius.xs` 未定義と catch の構文ミスでコンパイル失敗。既存トークンと正しい catch パターンへ直した。未使用 `error` 変数の警告も解消。
- `iter3-unit` では旧文言を固定していた承認・QR・名前変更テストが失敗したため、新カタログ文言に合わせた。保存・再送・失敗状態の検査は維持した。ただし名前変更は Mac の理由（`boom`）が消える形になっていたため、引き取り後に技術行へ理由を残す形へ直した（2 節）。
- 初期の追加 A5 テストは `#require` を含む throwing 呼び出しを async test で扱わずコンパイル失敗。`throws` を付けて修正。
- 初期アプリビルドは `UITestingNavigator` の追加列挙値未処理、次の試行は `Session` 初期化引数の順序で失敗。ケースと呼出引数を直した。
- 初期描画テストは `AppShellView`／画面Viewの引数不足と引数順の不一致でコンパイル失敗。呼出側を現行 initializer に合わせた。
- iOS26 の初期描画では `bodyDidNotRender` が発生。描画準備を修正した後の複数回の再実行は成功し、skip は追加していない。
- `unit-stage8a-final4` の新規A5テストは添付番号 `[Image #1]` が本文に保持される実挙動と期待値が食い違い失敗。本文保持を確認する期待値に修正。
- `unit-stage8a-final7` は SwiftPM の macOS ターゲットで `.navigationBar` が使用不可となり失敗。iOS 専用処理を `#if os(iOS)` で囲った。
- D1通信エラーを整えた初回テストは `HTTP 502 gateway` としてサーバ本文まで出し、既存の「HTTP 502」の契約に失敗。サーバ応答はステータスのみ、通信エラーは `NSURLError` と分岐し、最終は成功。
- iOS18の描画には `Modifying state during view update, this will cause undefined behavior.` と `CGGStackRestore: CG GState restored too many times` が残る。最終実行で前者 117 行・後者 201 行（原因は未調査）。iOS 26 は AppIntents のメタデータ省略の警告 2 行だけ。XCUITestと入力操作の合成は実行しない。

## 7. 打ち切りと引き取り

- 8a は Codex に委ねたが、見比べ→修正→両 OS の全場面の撮り直し（1 周約 10 分）を 4 時間半繰り返して収束しなかった。依頼に打ち切りの条件を入れていなかったのが原因。Codex の報告を書く前に停止し（`s8a.md` は空）、状態はログと作業ツリーから組み立て直した。
- 引き取り後に直したもの: (1) D4 の「許可」がカタログの例のまま固定され、拒否などを選んでも「許可」と出ていた。(2) F2 の技術行がカタログの例の接続先 `100.64.0.1:8765` のまま固定され、全利用者に架空の接続先を出していた。(3) 名前変更の失敗で Mac の理由が消えていた。
- 同じ種類（カタログの例の値を実値の代わりに書き込む）の残りは、`QRScanScreen.swift` の P3 技術行 `phlox://pair?v=1&port=8765&token=…`（読み取った値ではなく固定の例）。段階 8 のまとめのレビューで、他に無いかも含めて確かめる。

## 8. 変更ファイル

- App: `AppEnvironment+UITesting.swift`, `AppRoot.swift`, `SessionDetailDestination.swift`, `UITestingNavigator.swift`, `UITestingSupport.swift`。
- PhloxKit の表示／状態: `AppModel.swift`, `ConnectionSettings/ConnectionSettingsView.swift`, `ConnectionSettings/ConnectionSettingsViewModel.swift`, `LaunchGate/LaunchGateView.swift`, `NewChat/NewChatView.swift`, `NewChat/NewChatViewModel.swift`, `Pairing/PairingApplyViewModel.swift`, `Pairing/QRScanScreen.swift`, `SessionDetail/DeleteConfirmationView.swift`, `SessionDetail/DeleteConfirmationViewModel.swift`, `SessionDetail/SessionDetailView.swift`, `SessionDetail/SessionDetailViewModel.swift`, `SessionList/SessionListView.swift`, `SessionList/UnreachableView.swift`, `SessionList/UnreachableViewModel.swift`, `Settings/SettingsView.swift`, `PhloxCore/ErrorPresentation.swift`。
- 削除: `DesignSystemIOS/Molecules/DSConnectingIndicator.swift`。
- PhloxKit のテスト: `AppModelTests.swift`, `ConnectionSettingsViewModelTests.swift`, `ConnectionSettingsViewTests.swift`, `DeleteConfirmationViewModelTests.swift`, `ErrorRecoveryTests.swift`, `LaunchGateViewTests.swift`, `NewChatViewModelTests.swift`, `PairingApplyAcceptanceTests.swift`, `QRScanScreenTests.swift`, `SessionDetailLoadingWhiteboxTests.swift`, `SessionDetailReplyApprovalTests.swift`, `SessionDetailViewModelTests.swift`, `SessionRenameViewModelTests.swift`, `UnreachableViewModelTests.swift`, `PhloxErrorTests.swift`。
- 描画テスト: `ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift`。
- 資料: `ios/docs/adr/0046-align-ios-with-mac.md`, `ios/docs/adr/0047-replace-xcuitest-with-render-tests.md`, `ios/docs/architecture/overview.md`, `ios/docs/delivery/README.md`, `ios/docs/specs/redesign-2026-10.md`、本記録。

本記録の段階8aはユーザー承認後に `0c21a964` としてコミット済み。続きは [段階8bの記録](0029-ios-redesign-stage8b-worklog.md)。`.verification/ios-redesign-stage8a/` は比較の根拠としてログ・PNGを保持する。
