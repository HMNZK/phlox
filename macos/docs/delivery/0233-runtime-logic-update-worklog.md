---
status: active
date: 2026-11-12
---

# 0233: 実行サービスのコード更新と実行中CLIの継続（作業記録）

作業ブランチは`runtime-independent-update-20261112`。設計は[ADR 0233](../adr/0233-runtime-logic-update-with-process-holder.md)、現行仕様は[independent-session-runtime](../specs/independent-session-runtime.md)。

## 状態

段階0（旧サービス由来のCodex思考を画面で描画前に除く）を実装済み。変更は`SessionFeature`の`AgentStatusCardRouting.hidesReasoning`、`SessionRuntimeChatReadModel.swift`の判定拡張、`RuntimeChatTranscriptView`（ブロック）、`RuntimeStatusCardPresentation`（カード行・項目）。テストは`RuntimeReadCacheHostedTests`へ追加。段階1以降（holder・確定点・採用・新旧ホスト入れ替え、Codexを含む）も実装済みで、フェイクCLIの受入まで検査した。実CLIでの無停止更新は未検証。ユーザー環境への導入は今回の権限に含まれない。

## 調査で確認した事実（コード根拠）

| 事実 | 場所 |
|---|---|
| ホストがCompositionRoot・Dashboard・PTY・Hook/Control・カード・配信を所有 | `App/SessionRuntimeHost.swift` `start()` |
| 既存所有者があれば必ず再利用。新規起動は所有者が無いときだけ | `SessionRuntimeLauncher.connect` |
| 停止処理は全セッションとPTYを終了する | `SessionRuntimeHost.requestShutdown` |
| 起動時の復元はPTYを`reconcileOrphan`で回収して再生成、チャットは再起動して`thread resume` | `SessionRestoreCoordinator.restorePersistedSessions`/`restoreChatSession` |
| 子のパイプと`Process`は`LineDelimitedProcessTransport`。`LineDelimitedTransport`プロトコルが差し替えの継ぎ目 | `StructuredChatKit` |
| Codexは`defaultStructuredClientFactory`、Claudeは`ClaudeChatClient`の`transportFactory`で生成。Cursorはターンごとの`OneShotProcessRunner` | `AppEnvironment.swift`、`ClaudeChatClient.swift`、`CursorChatClient.swift` |
| JSON-RPCの要求番号は1から、応答待ちはメモリ。Claudeの承認・質問もメモリ | `JSONRPCClient`、`ClaudeChatClient` |
| 操作の重複排除は世代ごとのメモリ台帳。世代違いは`staleGeneration` | `SessionRuntimeOperationLedger`（`SessionRuntimeTransport.swift`） |
| ポートは保存値を優先し、使用中ならランダムへ黙って切替 | `HookServer.start(preferredPort:)`、`ControlServer` |
| トークンは記述子に永続化し、復元時にメモリのストアへ再登録 | `SessionRestoreCoordinator.restoreSession` |
| hook配送は失敗時に捨てる（`|| true`、5秒） | `scripts/hook-dispatcher.sh` |
| 子が参照するスクリプトはホスト自身のバンドルコピー内。コピーの整理は現状なし | `CompositionRoot.scriptPath`、`SessionRuntimeBundleStore` |
| プロトコル版は1。能力はhandshakeのフラグで増やしている | `SessionRuntimeHandshake` |
| GUIの本文は旧サービス組立済みのカード・ページ（`.inline`/`.deferred`の項目参照とカード要約） | `SessionRuntimeChatReadModel.swift`、`RuntimeChatTranscriptView`、`RuntimeStatusCardPresentation` |
| Codexに`app-server --listen unix://`、`daemon`、`proxy`がある（0.167.2）。Claudeに`--bg`/`attach`/`logs`/`stop`（2.1.322）。再接続時の承認保持は未確認 | CLIの`--help`のみ確認 |

## P0の解消: チェックポイントの項目別消費（PM裁定）

契約違反: 採用に失敗したセッションが残るのに、復元が一巡したらチェックポイント全体をconsumed化していた。次の通常起動で`reconcileOrphan`が生存している子を終了させ得た。

- 裁定: チェックポイントは採用に成功した項目だけを消費する。失敗・不明の項目は残して再試行できるようにし、残る項目のセッションは孤児回収の対象にしない。全体の削除は全項目が成功または明示的な放棄で外れたときだけ。失敗したセッションは`recoveryNeeded`として公開し、`resume`で子を再生成しない。
- 実装: `HandoverCheckpointStore.consume(sessionIDs:directory:)`（残りがあれば原子的に書き直し、無くなればconsumed化）、`SessionRestoreCoordinator`が採用成功・失敗（`recoveryNeeded`）のセッションIDを記録し`DashboardViewModel`が公開、`CompositionRoot.finishHandoverAdoption`は成功したIDだけを`consume`、`resumeChat`は`recoveryNeeded`を拒否。残る項目は次の起動で`handoverAdoptions`に再び載るので、`reconcileOrphan`は呼ばれない（既存の`adoption == nil`の分岐）。
- 追加した単体テスト: `HandoverCheckpointTests`（部分消費・全消費・未知ID）、`DashboardFeatureTests/HandoverRecoveryRestoreTests`（失敗した採用は孤児回収せず`recoveryNeeded`、成功した採用は消費対象）。
- 未対応（後続）: 放棄の画面操作、holderと子が無くなった項目の自動的な後始末。（Codexの確定点/採用・scripts再試行はその後に実装した。）

## holderの不安定性の修正（fdの再利用競合）

`retentionLimit…`が`ProcessHolderTests`全体の並走で失敗する（5.84秒＝握手の期限切れ、0.85秒＝即切断）。根拠と修正は`.verification/runtime-independent-update/claude-pm-resume-report.md`。要点: 接続のfdを、読み取りスレッドが読む途中で別スレッドが`close`していた（番号が再利用されて他の接続のデータを横取り・誤書込みする）。fdは読み取りスレッドの終了後に最後の利用者が閉じる構造へ変更。受信の取消し競合（待機前に取消されると永久に待つ）も修正。

## scripts の接続拒否の再試行（実装済み・未検証）

- `macos/scripts/hook-dispatcher.sh`と`macos/scripts/phlox`: curl終了コード7（接続できない）だけを0.2秒間隔で最大25回（約5秒）再試行する。28（タイムアウト）・22（`-f`のHTTPエラー）・2xx以外の応答・応答の途中の失敗は再試行しない。`phlox`は途中の失敗のstderrを出さず、最後の結果だけを従来どおり出す。環境変数`PHLOX_CONNECT_RETRY_ATTEMPTS`/`PHLOX_CONNECT_RETRY_INTERVAL`で上書きできる（テスト用）。
- 配線: 常駐プロセスは`Bundle.main.resourceURL/scripts/`（管理されたバンドルコピー内）を`hookDispatcherPath`/`cliPath`にする（`CompositionRoot.scriptPath`）。子の`PHLOX_CLI`・`PHLOX_API_URL`・Claudeの`--settings`のhookコマンドがそれを指す（`AgentLaunchPlanner`、`writeClaudeSettings`）。新ホストが開始した子から新しい版になり、更新前の子は旧版のまま（ADR 0233「hook/Controlの受付」）。
- テスト: `macos/scripts/tests/hook-dispatcher.test.sh`と`phlox.test.sh`に追加（拒否→成功で再試行、拒否が続くと上限で止まる、28・22・HTTP 500は再試行しない、認証つきでも再試行）。実行は`bash macos/scripts/tests/hook-dispatcher.test.sh`と`bash macos/scripts/tests/phlox.test.sh`（checker）。

## Codexの確定点・採用の設計メモ（実装は設計確認後）

ADR 0233「7. Codexの確定点と採用」が設計。ここは読んだ根拠・実装順序・リスク・テスト計画。

### 読んだ根拠
| 事実 | 場所 |
|---|---|
| Codexの子もholder経由（`holder != nil`のとき`holder.transport(...)`を`try transport.start()`で起動）。`HolderTransport`は既に`AppServerTransport`に適合 | `AppEnvironment.defaultStructuredClientFactory`、`AppServerTransport.swift` |
| `JSONRPCClient`は`transport.receivedLines`をpull型で消費（`for await line … await handle(line:)`）。通知は`notificationContinuation`（無制限バッファ）へ流す。サーバ要求は`Task`へ切り離してハンドラを呼ぶ（ハンドラは承認で長く待つ） | `JSONRPCClient.start/handle` |
| クライアント→サーバの未応答は`pending[id]`（継続）。運べないのでゲートにする。`nextRequestID`は単調増加 | `JSONRPCClient` |
| サーバ要求の応答送信が失敗すると、同じIDへエラー応答を送り直す（`try? sendErrorResponse`）。結果不明の送信でこれをすると二重応答 | `JSONRPCClient.handleServerRequest` |
| turn状態（`activeTurnId`・`closedTurnIds`・`pendingStartGeneration`・`hasObservedLifecycle`）がイベントの採否を決める。復元では`seedRestoredTurnIdentity`が`thread/read`から作る | `CodexAppServerClient.updateActiveTurns/acceptTurnEvent` |
| `CodexStructuredAgentClient`がthread identity（`currentThreadId`等）で旧threadの遅延イベントを遮断する。`close()`は`client.close()`→`rpc.close()`→`transport.close()`（子を終了） | `CodexStructuredAgentClient.yield/close` |
| 画面は`orderedEvents`を消費し、承認は別ストリーム（`ChatApprovalBroker.requests`）。承認は`serverRequestHandler`の継続をブローカーが保持する | `ChatSessionViewModel.startEventTasks`、`ChatApprovalBroker` |
| `initialize`/`thread/start`/`thread/resume`は画面（VM）が呼ぶ。復元でも`restore`が呼ぶ。採用はこれらを呼ばない | `ChatSessionViewModel.restore/startNewCodexThread` |
| `adoptHandover`は現状`loadSpawnAgentSettings`を`completeAdoption`より前に呼ぶ（Claudeでは通信しないので問題なし。Codexでは`listModels`等がRPCで、受信開始前は失敗する） | `ChatSessionViewModel.adoptHandover` |

### 「Claude縦と同じ型で足りるか」の判断
足りる。`HandoverCapableClient`（5メソッド）・`HandoverPreparation`（holder記録・反映済み番号・状態`Data`・フェンス）・`HandoverSession`・チェックポイント・`NormalizedChatEvent.handoverFence`・`HandoverGate`・`DashboardViewModel+Handover`・`SessionRestoreCoordinator`の採用経路は変更なしで使える。Codex固有なのは (1) 3層に状態が分かれるのでフェンスを各層が通るたびに状態を採取すること、(2) 承認要求の原文を`JSONRPCClient`が受信時に記録すること、(3) `adoptHandover`の順序（Codexでは`completeAdoption`を`loadSpawnAgentSettings`の前に）。新しいプロトコルや確定点の形式版は不要（`stateVersion`は状態の中）。

### 実装ファイルと順序（最小）
1. `CodexAppServerKit/JSONRPCClient.swift`: 未応答サーバ要求の原文記録（要求ID・状態: 保留/応答書き込み中/結果不明）、結果不明のときエラー応答を送り直さない、`nextRequestID`の取得・適用、`pending`が空かの問い合わせ、受信ループの取消し（`transport.close()`なし）、フェンスを通知ストリームへ流す口。
2. `CodexAppServerKit/CodexAppServerClient.swift`（＋`ThreadEvent.handoverFence`の追加と、`threadId(of:)`/`turnId(of:)`/`normalizedEvent`等の網羅switchの追従）: `turnStates`の採取・適用、フェンス通過時の状態採取、`closeRequested`を立てて切り離す口。
3. 新規`CodexAppServerKit/CodexStructuredAgentClient+Handover.swift`: `CodexHandoverState`（`stateVersion`つき）、`HandoverCapableClient`適合（ゲート・`prepareHandover`＝quiesce→フェンス→最上層到達待ち→状態を束ねる、`cancelHandover`、`commitHandover`、`completeAdoption`）、`prepareAdoption(state:transport:)`。
4. `DashboardFeature/AppEnvironment.swift`: `defaultAdoptClientFactory`に`.codex`（`HolderTransport(.adopt)`で`CodexAppServerClient`を作り`prepareAdoption`）。
5. `SessionFeature/ChatSessionViewModel.swift`: `adoptHandover`でCodexは`completeAdoption`を設定読込の前に、`appServerUserAgent`等を記述子から戻す。
6. テスト（下記）と、ADR・worklogの更新。
合計: 変更4（Kit 2、Dashboard 1、SessionFeature 1）、新規1、テスト新規2〜3。ClaudeのPRと違い、1と2を先にして既存のCodexテスト（`JSONRPCClientTests`等）が緑のままであることを確認してから3以降へ進める。

### リスク
- R1（高）: 3層のフェンス。採取時刻の誤りは、反映されていない行の状態を確定点に含める／含めないという静かな不整合になる。フェンス通過を順序の根拠にし、各層の採取はフェンスの処理の中だけで行う。
- R2（高）: 二重応答。結果不明を再投入も再送もしない規則を`JSONRPCClient`に集約し、単体で固定する。
- R3（中）: VMの設定復元（`syncSettings(from: response)`が`thread/resume`の応答に依存）。記述子の`codexSettings`だけで足りるかは未確認。足りなければ`thread/read`（読み取りのみ。再発行禁止の対象外）で補う案を検討する。
- R4（中）: 画像の一時ディレクトリの削除責任（採用後に誰が消すか）。状態にパスを載せ、新ホストの`close`で消す。
- R5（低）: Codex側のapp-serverが、接続を保つ限りサーバ要求を保持するか（stdioの1接続でholderが標準入力を閉じない前提）。実CLIでの確認は未実施。

### テスト計画（偽transport/holder。実CLI・課金なし）
- 単体（`CodexAppServerKitTests`、既存`MockTransport`）: ①未応答サーバ要求の原文が記録され、応答の送信後に消える。②応答の送信が`sendResultUnknown`のとき、エラー応答を送り直さず「結果不明」になり、採取対象から外れる。③`nextRequestID`が採取→適用で続きの番号になる。④`turnStates`の採取・適用（閉じたturnの遅延イベントを採用後も遮断）。⑤フェンスが全ホップを順に通った後に状態が採取される（フェンスの前に流したイベントの影響が状態に入る）。⑥`CodexHandoverState`のJSON往復（全フィールド、未知の`stateVersion`の拒否）。
- 結合（`ProcessHolder`＋`/bin/sh`の偽app-server。`ProcessHolderTests`と同じ方法）: ホストA（`HolderTransport`）で`initialize`/`thread/start`/`turn/start`→偽サーバが承認要求を送る→`prepareHandover`→`commit`→ホストB（`.adopt`）で`completeAdoption`→承認が1回だけ再提示され、応答が同じIDで子へ1回だけ届く／偽サーバの受信ログに`initialize`・`thread/resume`・`turn/start`が増えない／`nextRequestID`が続く／Aのcommit後に子が生きている（`kill -0`）。結果不明の送信があるとゲートが延期する。`unknownSendIDs`があると採用が失敗する。
- 受入（後続）: 既存`session-runtime-lifecycle.test.py`＋`session-runtime-fake-agent.py`（Codex側フェイク）をホスト入れ替え対応にする。

## Codex実装（PM承認済み。設計はADR 0233「7」）

実装順序は設計メモどおり。各工程の前にこの節を更新する。ビルド・テストは実行していない（checkerの担当）。

### 工程1: `JSONRPCClient`（応答送信失敗の同ID再送の廃止 → 状態の採取・適用）
- **既存挙動の変更（先に単独で）**: `handleServerRequest`は、承認などのサーバ要求への応答の送信が失敗すると、同じIDへ「エラー応答」を送り直していた（`do { send(結果) } catch { try? send(エラー) }`）。送信の失敗が「書き込めなかった」でなく「書き込めたか不明」（holder経由の`HolderError.sendResultUnknown`）のとき、同じIDへ2回目の応答になり、プロトコル違反になる。送信に失敗した・結果不明のときは、**同じIDへ再送しない**。ハンドラの結果（成功・未対応・エラー）で応答を1つ決め、それを送るのを1回だけにする。送信に失敗したら`JSONRPCClientError.responseNotDelivered`を`errors`へ流す。
- 既存テスト（`approvalRequestUsesHandlerAndRepliesWithDecision`・`unknownServerRequestReceivesUnsupportedError`・`serverRequestApprovalDoesNotBlockSubsequentResponses`）の期待は変えていない（正常系は応答が1つ）。追加: 応答の送信が失敗したとき、同じIDの応答が追加で送られないテスト。
- **状態の採取・適用**: 受信ループで未応答のサーバ要求の原文を同期的に記録する（`serverRequests`。ハンドラの起動を待たない）。応答の書き込み中は`.responding`、完了・失敗で記録を消す。`captureHandoverState()`は`nextRequestID`と、`.pending`の原文（受信順）を返す。`pending`（クライアントからの未応答）または`.responding`があればゲートで更新を延期する。採取は応答が決まる直前の極短い間（承認ブローカーがハンドラを返す前後）に重なり得るので、画面側は応答処理中の承認を持つ間は確定点を作らない（工程5）。
- `detachForHandover()`: 受信ループを止めるが、`transport.close()`を呼ばず、入力の途切れを子の終了として扱わない。

### 工程2: `CodexAppServerClient`と`ThreadEvent.handoverFence`
- `ServerNotification.handoverFence(UUID)`と`ThreadEvent.handoverFence(UUID)`を追加（網羅switchの追従: `threadEvent(from:)`・`turnId(of:)`・`threadId(of:)`・`normalizedEvent(from:)`は`nil`/対象外）。フェンスは`JSONRPCClient`が通知ストリームの先頭へ流し、`CodexAppServerClient`の通知ループが前のイベントを全て`yield`した後に通過させる。通過時に`turnStates`と`JSONRPCClient`の状態を採取して`CodexClientHandoverState`にし、`ThreadEvent.handoverFence`を流す（上位は`takeFenceState(_:)`で受け取る）。
- 切り離し（`detachForHandover`）は`detached`を立て、通知ループの終了で`notificationStreamDidFinish`を走らせない（`exitedUnexpectedly`・`.error`・ストリームの終了を出さない）。`transport.close()`は呼ばない。
- ゲート: 子の終了済み・切り離し済み、`pendingStartGeneration`あり（`turn/start`の応答待ち）、`JSONRPCClient`のゲート。

### 工程3: `CodexStructuredAgentClient+Handover.swift`
- `CodexStructuredAgentClient`を`HandoverCapableClient`に適合させる（新しい型は作らない）。状態は`CodexHandoverState`（`stateVersion`=1、`CodexClientHandoverState`、thread identity一式、`lastThreadStartParams`、`pendingChildInterrupts`、画像入力の有効/ディレクトリ一覧）。拡張から触るため、メインファイルの`private`を一部外し、保持用の3つの変数（`pendingAdoption`・`fenceWaiters`・`handedOver`）を足す。
- `prepareHandover`: ゲート→`holder.quiesce()`→ゲート再確認→フェンスを流して最上層への到達を待つ（10秒。期限切れは配送を再開して`timedOut`）。状態は最上層のフェンス通過時に、上位ストリームへフェンスを出す前に採取（同じアクターの1メソッド内。採取の前に`await`を挟まない部分を先に取る）。
- `commitHandover`: 受信を止めて切り離し→確認→`releaseForHandover`。以後の`close()`は子にも画像ディレクトリにも触れない。
- `completeAdoption`: 状態の復号・版の確認（子へ接続する前）→holderへ接続→`unknownSendIDs`が空か→3層へ状態適用→所有権喪失ハンドラ→未応答要求の再投入→受信開始。`initialize`・`thread/*`・`turn/start`は呼ばない。いずれの失敗も`HandoverError.adoptionFailed`（復旧待ち）。進行中ターンの表示は発行しない（工程5で`thread/read`の状態から戻す）。

### 工程4・5: 採用ファクトリ`.codex`と画面側の採用
- `AppEnvironment.defaultAdoptClientFactory`に`.builtin(.codex)`: `HolderTransport(.adopt)`で`CodexAppServerClient`（承認ハンドラ・開発者指示つき）を作り、`CodexStructuredAgentClient.prepareAdoption`へ状態を預ける。接続は`completeAdoption`。
- `ChatSessionViewModel.adoptHandover`: Claudeの順序（transcript復元→設定→スレッドID→`completeAdoption`）は変えず、**`completeAdoption`の後**にCodex用の読み取りを足す: `loadAvailableSettings`（モデル一覧。RPCなので受信開始後）、`thread/read`（読み取りのみ。再発行禁止の対象外）で、進行中ターンのID（`codexEventTurnId`）と状態（`applyRestoredThreadStatus`）、transcriptが無いときの再構築を行う。`thread/resume`の応答が無いので、設定（モデル・権限・Plan）は記述子の永続値（`persistedSettings`）から戻す。`thread/read`の失敗は採用の失敗にしない（採用は済んでいる。失敗にすると次の起動で同じ行を再び受ける）。
- 応答処理中の承認がある間は確定点を作らない（`respondingApprovalCount`。承認ブローカーがハンドラを返す前後の極短い間に確定点が重なり、応答済みの要求を再提示する窓を、通常は塞ぐ。厳密な排除は未実装）。

### テスト（追加のみ。実行はcheckerの担当）
- `JSONRPCHandoverTests`（MockTransport系）: 応答送信失敗で同IDの応答が1回だけ・ハンドラ失敗のエラー応答は1回・失敗したエラー応答も再送しない、原文の記録と応答後の消去、`nextRequestID`の持ち越し、保留中のサーバ要求でのゲート、再投入した要求への応答が同じIDで1回、切り離しで`transport.close()`・通知ストリーム終了をしない。
- `CodexHandoverTests`: フェンスが前のイベントの後ろに届き状態へ影響が入る／閉じたturnの遅延イベントが採用後も遮断される／`CodexHandoverState`のJSON往復／未知の`stateVersion`・壊れた状態・接続不可はどれも`adoptionFailed`（子へは何もしない）／非holderのゲート理由／ProcessHolder＋`/bin/sh`の偽app-serverによる結合（承認の再提示1回・応答1回、`initialize`/`thread/start`/`turn/start`が各1回のまま`thread/resume`なし、コミット後と旧ホストの`close()`後も子が生存、採用後のリクエストIDが続き番号）。
- **初回実行の失敗（JSONRPCHandoverTests 5件・CodexHandoverTests フェンス2件・結合のハング）の原因はテストの前提不備で、本体の不具合ではない**: 共有ヘルパー`waitUntil { }`（`events:`なしの形）は条件を**1回しか評価しない**（条件を評価する子タスクと期限のsleepを競わせるだけで、ポーリングしない）。受信行は別タスクで処理されるので、`receive`の直後に評価すると必ず偽になる。既存テストは`events:`つきの形で使っていた。結合テストのハングも同根（承認要求が届く前に先へ進み、`initialize`等の応答を無期限に待つ呼び出しが残った）。直し: ①10msごとに期限（5秒）まで確かめる`eventually`を使う。②フェンスの試験では、受信行が最上層へ届いてからフェンスを流す（本番では`quiesce`が受信の消化を保証する。テストで行を入れた直後にフェンスを流すと、フェンスが行を追い越す）。③結合テストの`initialize`/`thread/start`/`turn/start`/`prepareHandover`/`commitHandover`/`completeAdoption`/`thread/read`/`close`は期限つきの`within`で包み、超過は`StepTimeout`で失敗させる（ハングさせない）。失敗メッセージに子の受信ログ・承認ハンドラ呼び出し回数を出す。④`ResponseFailingTransport.send`は、末尾の改行を除いてから復号する（`SentMessages`と同じ）。期待値は変えていない。
- **結合テストの残り1件（`旧ホストのthread/start`が10秒で終わらない）の原因も偽サーバ側の照合ミス**: `JSONEncoder`は`/`を`\/`にエスケープして送る（子の受信ログに`"method":"thread\/start"`と出ていた）ので、偽app-server(`/bin/sh`)の`case`パターン`*'"method":"thread/start"'*`（`thread/read`・`turn/start`も）が一致せず、応答しなかった。`initialize`は`/`を含まないので通っていた。直し: 偽サーバは受け取った行から`\/`を`/`へ戻してから、ログへの記録と照合を行う。テスト側のログ照合（`"method":"thread/start"`等の件数、`requestID`）も、正規化済みの行を見るので一致する。承認要求・`thread/read`の応答は、偽サーバが自分で書く行（エスケープなし）で、`id`の抽出（`{"id":N,`）は`/`を含まない先頭部分だけを見るので影響を受けない。期待値は変えていない。
- 未検査（意図的）: `unknownSendIDs`非空の採用失敗経路（結果不明の送信を作るには送信中の切断を再現する必要があり、既存の`HolderTransport`テストの範囲）、実CLI、`session-runtime-lifecycle.test.py`のホスト入れ替え拡張。

## 受入条件と検査の対応

ADR 0233の表（A1〜A11）が正本。検査の置き場:

| 検査 | 置き場・方針 |
|---|---|
| holderの順序・送信ID・書込権世代・保持上限での読み取り停止（捨てない） | 新しい単体テスト（`StructuredChatKitTests`）。実CLI・実ネットワークを使わない |
| 再生の決定性（全分割点） | 単体。フェイクCLIのトレースをfixture化 |
| ホスト入れ替えをまたぐPID・出力・承認・質問・送信・新規チャット | `macos/scripts/tests/session-runtime-handover.test.py`。`session-runtime-lifecycle.test.py`の隔離・所有確認・後片付けを継承し（新しいハーネスは作らない）、フェイク（`session-runtime-fake-agent.py`・`session-runtime-structured-fake-agent.py`）を後方互換で拡張。詳細は下の「新旧ホスト入れ替えの受入」 |
| 旧サービス向け思考フィルタ | `SessionFeatureTests`（`RuntimeSemanticChatProjectionTests`系）へ追加。旧サービス由来ページを入力に使う |
| 能力フラグ・旧接続の互換 | `AppBootstrapTests`（`SessionRuntimeTransportTests`等） |

テスト方針（`~/.agents/docs/test-policy.md`）: 外から観測できる振る舞いを検査する。既存アサーションは弱めない。新規E2Eは「入れ替え中も同一PIDと進行が続く」の主要フローに絞る。

## 品質設定の列挙（コード変更前の確認）

- 標準入口: `python3 -B macos/scripts/verification-gate.py quality`（`gitflow.verifyCommand`）。内訳: ゲート単体、iOS単体、`run-swift-tests.sh`の標準入口回帰、`test_session_runtime_lifecycle_api.py`、`scripts/tests/hook-dispatcher.test.sh`・`phlox.test.sh`（フック・CLIの接続拒否の再試行。`runtime-api-retry`の次の段として`compact-test --full`経由で実行。要`jq`）、`MACOS_PACKAGES`全パッケージ、iOS lint/テスト/ビルド、フェイクE2E。
- `MACOS_PACKAGES`は新しいSwiftパッケージの追加で`validate_package_scope`が失敗する。holderは既存パッケージ（`StructuredChatKit`）内に置く方針の理由の一つ。
- `release/verification-scenarios.json`に受入シナリオがあり、`session-runtime-semantic-chat.test.py`を含む。`session-runtime-lifecycle.test.py`は標準品質入口に未登録（手元の受入）。登録の要否はPMの判断。
- `.swiftlint.yml`・Makefile（macos）は無い。`macos/project.yml`はアプリの対象定義（`--session-runtime`と同じ実行ファイルの別モードならproject.yml変更は不要の見込み）。
- ビルドは`managed-build`経由。テストは`compact-test`経由。

## ドキュメントとコードの不整合

- 仕様の「分離実装は作業ブランチに存在し」は、現在は統合済みの実装に対して古い記述。今回は修正していない。
- 仕様のlast-verifiedを2026-11-12へ更新したが、全文の再検証ではない（今回確認したのは対象外・復元・所有の節）。
- 仕様の「新しい永続ジャーナルは含めない」と、ADR 0233のholder記録は矛盾する。ADR採用まで仕様を維持し、採用時に置き換える（仕様に注記済み）。
- 検証スクリプト`session-runtime-lifecycle.test.py`の対象は旧ホスト単体の受入で、ホスト入れ替えは検査していない（入れ替えは`session-runtime-handover.test.py`）。
- `session-runtime-lifecycle.test.py`は「Codex/Claudeの子の親＝常駐サービス」を検査していたが、holder導入後の親はholder。役割ごとの所有の連鎖（PTY・Cursorは常駐サービスの子、Codex/Claudeは常駐サービスと同じ実行ファイルのholderの子で、holderの親が常駐サービス）へ直した。

## 未解決（PMへ）

ADR 0233「PMが決める事項」の4点。特に初回移行（案A/B）と段階0を先行するか。

## フレーム上限と1行64MiB上限の整合（実コード確認。不整合を修正）

- **不整合があった**。`LineDelimitedProcessTransport`は1行を最大64MiB（＋読み取り1回分の64KiB）まで通す。holderは各行を`HolderFrame.line(seq:data:)`としてJSONで送るが、`Data`は`JSONEncoder`の既定でbase64になり4/3に膨らむ。64MiBの行は約89.5MBのフレームになり、従来の上限`maximumFrameBytes`=72MiB（約75.5MB）を超える。生の行で約54MiB以上が該当する。
- **影響**: `ProcessHolder.Connection.send`は`try? HolderWire.encode(frame) else { return }`で、符号化に失敗したフレームを黙って捨てる。seqは進んでいるので、行が失われたまま常駐側からは番号の欠落として見え、データ損失（かつ確認の進行が止まる）になる。常駐側→holderの`write`（子への送信行。画像のbase64入りの長い行）も同じ上限で拒否される。
- **修正**: `HolderProtocol.maximumFrameBytes`を、1行の上限（64MiB＋読み取り1回分の余裕）のbase64長に、JSON外枠の余裕を足した値にする（`((64MiB + 64KiB + 2) / 3) * 4 + 256KiB`）。ソケットの読み取りは長さ先読みで上限まで一度にメモリへ載せるため、上限を上げる代償は、悪意ある/壊れた相手が約90MBを確保させられること（同じユーザーのソケット、0700のディレクトリなので脅威は増えない）。
- **テスト**: `ProcessHolderTests`に、64MiBの行のフレームが符号化に成功し（従来の上限なら`frameTooLarge`）、上限内に収まることを確かめるテストを追加（ソケットを通さない単体。大きな行を実際に子から流すと時間とメモリを使うため）。

## 延期した更新の自動再試行（設計。実装は`HostUpdateRetry`と`DesktopCompositionRoot`）

- **現状**: `DesktopCompositionRoot.requestHostUpdate`は画面の起動時に1回だけ更新を要求する。延期（動いている未対応の実行・Codexの応答待ち等）されると、案内（`updateNotice`）を出すだけで、利用者が画面を開き直すまで切り替わらない。
- **方針**: 延期されたときだけ、一定間隔で同じ要求を有限回だけ再送する。要求は`handoverDeferralReasons`の確認から始まる冪等な操作なので、再送で副作用は増えない（延期中は何も止めず、何も変えない）。
- **暴走防止（必須）**: 間隔の下限は30秒（呼び出し側が短い値を渡してもこの値に切り上げる）、最大40回（約20分）。上限に達したら止まり、案内（「しばらくの間は自動で再試行して切り替えます（画面を開き直しても切り替わります）」）は残る。
- **止まる条件**: ①延期でなくなった（切り替えを始めた・完了した・失敗した・対象外になった＝`requestHostUpdate`が延期以外を返した）。②接続先の世代が変わった（入れ替わって別の世代につないだ）。③`DesktopCompositionRoot`の解放（Taskのキャンセル）。④上限。
- **置き場**: 回数・間隔・キャンセルの規則は、画面から独立した小さな型`HostUpdateRetry`（`AppBootstrap`）に置き、`sleep`を注入して単体テストする（実時間を待たない）。`DesktopCompositionRoot`は、延期を返した初回の後に`Task`を1本だけ起動し、毎回`requestHostUpdate`を呼び、案内を更新する。
- **限界**: 画面を閉じている間（画面を持たない実行サービスだけが動いている間）は再試行しない（要求元が画面のため）。次に画面を開いた時に、従来どおり初回の要求が走る。

## 追加テスト（Codexの結果不明送信での採用失敗・採用成功VMの復元）

- `CodexHandoverTests.adoptionWithAnUnknownSendFailsAndLeavesTheChildAlone`（結合）: 子は最初の1KiBだけ読んで目印のファイルを作り、その後は標準入力を読まない（`dd bs=1024 count=1; : > "$1"; exec sleep 30`）。4MiBの送信の残りは書き切れず、holderには「受け付けたが結果不明」として残る。目印を待ってから別接続の取り付け情報（`unknownSendIDs`）で確認し、その状態で有効な状態を渡して`completeAdoption`すると`adoptionFailed`（「結果不明」）になり、子のPIDは生きたまま（終了も再生成もしない）。前提が作れなければ`#require`で失敗させ、素通りさせない。失敗メッセージに送信結果・`unknownSendIDs`・経過時間を出す。
- **初回の失敗（`accepted`が偽、10/10）の原因はテストの前提の作り方（本体の不具合ではない）**: 初版は`sleep 30`の子へ4MiBを送り、送信直後から別接続（probe）を取り付けて`unknownSendIDs`をポーリングしていた。`ProcessHolder.attach`は書込権を新しい接続へ移し、前の接続を`evicted`にして閉じる。最初のprobeの取り付けが、holderが4MiBのフレームを読んで`beginSend`で「受け付けた」と記録するより先に走るため、送信中の接続が閉じられ、送信は一度も受け付けられなかった（`write`は`notWriter`）。以後のポーリングでは何も残らない。直し: 送信がholderに受け付けられた後にしか起きない出来事（子が最初の入力を読む＝holderが`transport.send`を始めた）を目印のファイルで待ってから、別の接続を取り付ける。
- `HandoverRecoveryRestoreTests.successfulAdoption_restoresTheRunningTurnAndDoesNotReapTheLiveChild`（DashboardFeature）: 既存の失敗側テストと同じ構成で、採用ファクトリが最小の代役（`completeAdoption`で`turnStarted`を流す`HandoverCapableClient`）を返す。採用が成功し（`handoverAdoptedSessionIDs`・`restoreState == .restored`）、復旧待ちに入らず、記録PIDが生きていても`reconcileOrphan`（`reapedPIDs`）が呼ばれず、`running`が復元され、`resume`も`close`も呼ばれない。SessionFeature側の`adoptHandover`は、この結合を通して検査する（重いモックを作らない）。

## SIGPIPE の点検（子の標準入力への書き込み。本体を修正）

- **発端**: `adoptionWithAnUnknownSend…`が、テストプロセスごとSIGPIPE（シグナル13）で落ちた（10/10。全数実行でも同じ）。原因は、書き切れずに子の標準入力パイプでブロックしている`write`が、テストの後片付け（子の強制終了）で読み手を失い、EPIPEではなくSIGPIPEを受けたこと。
- **全経路の点検**: ①ホスト↔holderのソケット: 接続側（`HolderSocket.connect`）と受け付け側（`ProcessHolder`のaccept）の両方に`SO_NOSIGPIPE`が設定済みで、`HolderWire.writeAll`はEPIPEを`disconnected`として扱う。②holderプロセス（`--session-holder`）: `ProcessHolderMain.run`が`signal(SIGPIPE, SIG_IGN)`済み。③**子の標準入力パイプ（`LineDelimitedProcessTransport.send`の`FileHandle.write`）: 未設定だった**。holder経由でない実行（holder無効・`LineDelimitedProcessTransport`を直接使う経路）では、子が先に終了した瞬間の書き込みがSIGPIPEで本体プロセスを終了させ得る。holder経由でもholder内の書き込みは②で守られるが、holderを同一プロセスで動かすテストは守られない。他のSIGPIPE抑止（MobileProxyのソケット、SimulatorCatalogの標準入力）は別経路で設定済み。
- **修正**: `LineDelimitedProcessTransport.start`で、標準入力パイプの書き込み側に`F_SETNOSIGPIPE`を設定する（`process.run`の前。設定できなければ起動せず`processLaunchFailed`）。以後、読み手のいない書き込みはSIGPIPEでなくEPIPEを返し、既存の`catch`が`stdinClosed`として扱う。プロセス全体の`signal(SIGPIPE, SIG_IGN)`は、他のコードの意図を変えるので使わない。
- **テスト**（`StructuredChatKit`）: ①終了済みの子への書き込みが`stdinClosed`で失敗し、プロセスが落ちない。②パイプが満杯でブロックした書き込みが、子の終了で`stdinClosed`になり、プロセスが落ちない（今回の落ち方そのもの）。
- 結合テスト`adoptionWithAnUnknownSend…`は、後片付けで子を強制終了しても、ブロック中の書き込みがEPIPEで終わるので落ちなくなる（テスト側の期待は変えていない）。

## Appビルドエラー（`DesktopCompositionRoot`の再試行Task）

- `updateRetryTask = Task { [weak self] in await HostUpdateRetry.run { guard let self … } }`は、外側の`[weak self]`（可変の弱参照）を内側のSendableクロージャが捕まえるので、Swift 6で`reference to captured var 'self'`になる。直し: `self`がlet扱いの`startUpdateRetry`の中で、`[weak self]`のSendableクロージャ`step`を先に作り、`Task { await HostUpdateRetry.run(attempt: step) }`へ渡す（入れ子で弱参照を捕まえない）。同ファイルの他のTask（`reconnectTask`・`settingsTask`）は既存でビルドを通っており、入れ子のSendableクロージャで弱参照を捕まえる形は無い。

## 独立レビュー（needs_changes）の指摘への対応

各指摘は実コードで再確認した。順序は B1→M2→M3→M4→M5→M6→M7→Minor。この節は段ごとに追記する。

### B1 [Blocker] 採用に失敗したClaudeセッションへの送信で新しいCLIが起動する（事実と一致。二重に塞ぐ）

- **再確認した事実**: `ChatSessionViewModel.adoptHandover`の失敗は`status=.error`・`restoreState=.failed`にするが、①`isReadyForInput`は`.error`でも`true`（入力欄が有効）、②`sendText`は`restoreState`も復旧待ちも見ずに`client.turnStart`へ進み、③`ClaudeChatClient.turnStart`は`transport==nil`かつ`exitReportedGeneration != spawnGeneration`のとき`spawn`する。採用の失敗（`completeAdoption`が`transport`を代入する前に投げる）では、この条件を満たす。`completeAdoption`に入る前の失敗（`restoreTranscriptFromStore`が投げる等）でも同じ。これは「子を終了も再生成もしない」契約に反する（元の子は生きたまま、2つ目のCLIが同じ会話を`--resume`で起動する）。
- **直し（画面側）**: `ChatSessionViewModel.isHandoverRecoveryNeeded`を持ち、`adoptHandover`の失敗・非対応で立てる。立っている間、`isReadyForInput`は`false`（入力欄が無効）、`sendText`（Control API・phlox send・スマホを含む全送信経路。いずれも`sendText`を通る）・`setModel`・`applySpawnAgentSettings`・`startFromHistory`・`revert`は拒否する（`HandoverError.adoptionFailed`）。休止は既存の条件（`restoreState`が`restored`/`notRestored`のみ、`.error`は不可）で既に拒否されるのでそのまま。
- **直し（クライアント側。画面側が漏らしても新しい子を作らない）**: `ClaudeChatClient`に`spawnForbiddenReason`を持たせ、`prepareAdoption`で立て、`completeAdoption`の成功で下ろす。`spawn(sessionArgument:)`の入口（`start`/`resume`/`forkSession`/`resetConversation`/`turnStart`の再起動/自己修復の全てが通る）で、立っていれば`HandoverError.adoptionFailed`を投げる。所有権の喪失（`handleOwnershipLoss`）と手放し（`commitHandover`）でも立てる（手放した旧ホストが`resume`/リセットで子を作らない）。
- **Codex**: 構造上は元から安全。採用前の`HolderTransport`は未接続なので`send`は`notStarted`、失敗後に`releaseForHandover`した接続への`send`は切断で失敗する（holderへは書かない）。さらに`threadId`は成功時にだけ復元するので`turnStart`は`threadNotStarted`で止まる。これをテストで固定する。
- **テスト**: `ClaudeAgentKit`に、採用の準備だけ／失敗した採用／所有権の喪失の後に`turnStart`・`resume`・`resetConversation`しても`spawn`されない（子の起動コマンドが呼ばれない）こと。`SessionFeature`に、復旧待ちのVMが`sendText`を拒否し`isReadyForInput`が偽になること。`CodexHandoverTests`に、採用失敗後の`turnStart`が失敗すること。

### M2 確定点を書いた後の中止で確定点が残る（事実と一致）

- **再確認した事実**: `performHandover`は`HandoverCheckpointStore.write`の後に`guard !stopping else { await abort(...) }`で中止し得るが、`abort`は確定点を消さない。`requestShutdown`は`handingOver`を見ず、子を終了する。中止後に次のホストが起動すると、終了済み（または別の目的で再利用された）子を指す古い確定点を採用しようとする。
- **直し**: ①書く前にも`stopping`を確認する。②自分が書いた確定点は、中止時に`sourceGeneration`が自分の世代と一致する場合だけ消す（`HandoverCheckpointStore.discard(sourceGeneration:directory:)`。他の世代・読めない確定点には触れない）。App層の変更はこの呼び出しの追加だけで、判定そのものは単体テスト可能な`StructuredChatKit`側に置く。コミット後（不可逆）の失敗では消さない（次のホスト起動が確定点を採用する設計のまま）。
- **テスト**: `HandoverCheckpointTests`に、世代が一致すれば消える／一致しなければ残る／無ければ何もしない。

### M3 採用時の受信番号の欠落が未検査（事実と一致）

- **再確認した事実**: 両クライアントの`completeAdoption`は`transport.start()`の後に`unknownSendIDs`だけを検査し、`attach`が返す`firstRetainedSeq`・`lastSeq`を見ていない。反映済み番号`appliedSeq`より後の行がholderから既に破棄されていても（例: 採用済みの項目を、確定点の書き直しの失敗で再度採用する場合。新ホストが確認済みにした行は破棄済み）、そのまま受信を始め、欠落した行を知らずに続ける。ADR 0233の「再試行は保持行の番号で整合する」という記述は事実と違った（整合ではなく、検査が無かった）。
- **直し**: `HolderTransport.adoptionContinuityFault()`（`StructuredChatKit`）を足し、`firstRetainedSeq <= appliedSeq+1`かつ`lastSeq >= appliedSeq`を検査する。違反は、両クライアントの`completeAdoption`が（`unknownSendIDs`の検査より前に）`releaseForHandover()`（detachのみ。`confirm`は送らない。受信の消費を始める前なので自動の確認も出ない）して`adoptionFailed`にする。ADRの記述を、欠落・重複を検出して安全に失敗する、へ直した。
- **テスト**: 実holderで5行を出し、seq5まで確認（confirm）した後、`appliedSeq: 2`で採用すると、`HolderTransport`・Claude・Codexのいずれでも`adoptionFailed`になり、子は生存し、holderの保持（`firstRetainedSeq`）は変わらない（`confirm`が送られていない）。

### M4 Codex承認応答が0回になる競合（事実と一致）

- **再確認した事実**: `JSONRPCClient.handleServerRequest`は、応答の送信が失敗すると種類を問わず記録（`serverRequests`）を消す。確定点の準備中（`quiesce`で送信を止めた後）に承認が答えられると、`HolderTransport.send`は`handoverInProgress`で**確実に未送信のまま**失敗する。この要求は記録から消えるので、①更新が中止されても応答は再送されず（子は承認待ちのまま止まる）、②更新が確定しても確定点に載らず新ホストで再提示されない。応答が0回になる。
- **区別**: 確実に未送信（`HolderError.handoverInProgress`・`notWriter`）と、結果不明（`sendResultUnknown`）・書き込み失敗（`sendFailed`。子の入力が閉じている）を分ける。後者は従来どおり再送も再提示もしない（二重応答の防止。工程1の意図を保つ）。
- **直し**: 確実に未送信の失敗では、記録を`.pending`に戻し、決めた応答を記録へ保持する（`undelivered`）。①確定点が作られるなら、`.pending`として確定点に載る（新ホストが再提示し、利用者が答え直す。旧ホストは手放しており二重にならない）。②更新が中止されるなら、`cancelHandover`が`resendUndeliveredResponses`で保持した応答を同じIDで送り直す（利用者の答えを失わない）。再送が再び確実に未送信なら保持を続ける。
- **テスト**: 確実に未送信の失敗で記録が残り・確定点に載り、中止後の再送で応答が1回だけ届くこと。`sendResultUnknown`は従来どおり再送も保持もしないこと（既存テスト`failedResponseSendIsNotRetried…`は変更なし）。

### M5 中断したClaudeセッションで更新が延期され続ける（事実と一致）

- **再確認した事実**: `turnStart`→`interrupt`で、CLIはSIGINTで終わる（ADR 0083）。`ClaudeChatClient`は、中断で止めた終了を`processExited`として知らせず（`yieldProcessExited`の`interruptEndedGeneration`）、`transport=nil`にする。`interruptExitPendingGeneration`は次の送信が来るまで残る。この状態の`handoverGateReason`は、最初の判定（`transport`がholderでない）で「Claudeの子がholder経由ではありません」を返し続け、`handoverDeferralReasons`は永久に空にならない（更新が延期され続ける）。`processExit`も立たないので画面側は除外もしない。
- **直し**: クライアントが「子は既に終了している」と答えられるようにする。`HandoverCapableClient`に`handoverParticipation()`（`.participant`/`.childEnded`。既定は`.participant`なので既存の代役・Codexは変更不要）を足し、`ClaudeChatClient`は`transport==nil`・起動済み（`spawnGeneration>0`）・`spawn`禁止でない場合に`.childEnded`を返す。`DashboardViewModel`の延期理由・確定点の作成は`.childEnded`のセッションを対象外にする（延期理由にも確定点にも載せない）。新ホストは、確定点に無いセッションを通常の復元（`--resume`で再起動）で戻す。孤児の回収（`reconcileOrphan`）は、記録PIDが既に死んでいるので何も殺さない。生きている子を持つセッションは対象のままで、殺さない。
- **テスト**: `ClaudeAgentKit`で`turnStart`→`interrupt`→CLI終了の後に`handoverParticipation()==.childEnded`（動作中は`.participant`）。`DashboardFeature`で、`.childEnded`のセッションがあっても`handoverDeferralReasons()`が空で、`prepareHandoverEntries()`がそのセッションを準備しない。

### M6 起動途中のholderが確定点から漏れる（事実と一致）

- **再確認した事実**: 新しい子の起動を止める門`HandoverGate`は、`SessionSpawnService.prepareSessionLaunchAsync`の入口（計画時）で1回だけ確かめる。Codexは`AppEnvironment`の構造化クライアント生成の中の`transport.start()`、Claudeは`ClaudeChatClient.spawn`の中の`transport.start()`が、実際にholder（`HolderLauncher.spawn`）を起動する。計画時に門が開いていて、その後に門が閉じると、起動が最後まで進んでholderが生まれる。確定点の作成より後にholder.jsonが書かれると、`unmanagedHolderSessions`（holder.json頼み）にも映らず、新ホストが知らない子が残る。
- **直し**: 門に起動中の件数を持たせる（`beginLaunch()`は閉じていれば偽、開いていれば件数を足す。`endLaunch()`）。holderを起動する唯一の入口`HolderTransport.start()`（`.launch`）が`beginLaunch`/`endLaunch`で囲まれる（`ProcessHolderPolicy`が作るtransportに門を渡す。`AppEnvironment`が自分の門を方針へ結びつける）。閉じた後の起動は`handoverInProgress`で失敗し（何も起動しない）、閉じる前に始まった起動は、`closeAndDrain`が件数0になるまで待つ（期限あり。超えたら更新を中止）。確定点の作成の前に呼ぶ。さらに従来の`unmanagedHolderSessions`は、取りこぼしの最後の防波堤として残す。ドレインの後に、起動が終わってもまだ画面のノードに載っていない新しい実行は`unmanagedHolderSessions`に映り、更新は中止される（子は終了しない。延期の自動再試行が後でやり直す）。
- **テスト**: 門の単体（閉鎖後は`beginLaunch`が偽、件数、`closeAndDrain`が起動の終了を待つ／期限で偽を返す）。`HolderTransport`の`.launch`は、門が閉じていればholderを起動せず`handoverInProgress`で失敗する（存在しない実行ファイルを指定しても`launchFailed`でなく`handoverInProgress`になる）。

### この節の進捗（B1〜M6 完了。M7・Minor は次の依頼）

- 完了: B1・M2・M3・M4・M5・M6（上記）。各段の追加テストは、段ごとに記載した場所に置いた。
- 未着手（次の依頼で対応）: M7（`ClaudeChatClient+Handover`の準備・確定・未回答要求の再投入と一度だけの応答、VMの`prepareHandover`/`adoptHandover`のガード、Dashboardの延期・中止の取りまとめ、`performHandover`の順序の切り出しと単体テスト）、Minor 8（フレーム上限の`\/`エスケープの最悪ケース・符号化失敗を黙って捨てない）、9（`updateStatus`の古い案内）、10（`HolderTransport`のspec書き込みパイプの`F_SETNOSIGPIPE`）、13（docs不整合の整理）、11・12・14（限界の記載。12は固定ポート再束縛の確認）。

## checker(pm13) 対応: 重複宣言の修正・静的点検・M7・Minor
- **コンパイルエラー**: `HolderTransport.swift`の`attachInfo`が重複（159行目に先行宣言）。自分が足した側を削除した。
- **静的点検**: 今回編集したファイルの新規シンボルを検索して確認した。`ClaudeHandoverTests`が別ファイルの`private`な`TransportRecorder`/`MockTransport`を参照していたため、自前の`StartRecorder`/`IdleTransport`へ置き換えた。他に同名の重複宣言・ラベル不一致は見つからなかった（コンパイルは未実行のため断定はしない）。
- **M7（最小）**: `ClaudeHandoverIntegrationTests`（新規。フェイクtransportで準備・確定・採用・未回答要求の再投入と一度だけの応答）、VMの準備済み中は送信を拒否するテスト（`HandoverRecoveryGuardTests`）、Dashboardの延期・門・取消し調整のテスト（`HandoverRecoveryRestoreTests`）を追加。`performHandover`の順序の切り出しと単体テストは**未実施**（App層。ADRの制限に記載）。
- **Minor 8**: フレーム上限を`\/`なしの符号化＋base64の最悪ケースで見積もり直し（`HolderWire.encode`は`.withoutEscapingSlashes`）。`ProcessHolder.Connection.send`は符号化失敗時に接続を閉じ、黙って捨てない。テストは`ProcessHolderTests`。
- **Minor 9**: `SessionRuntimeHost.requestHandover`で`discovery.updateStatus = nil`、`DesktopCompositionRoot`は再接続時に`updateNotice = nil`。
- **Minor 10**: `HolderLauncher.spawn`と`LineDelimitedProcessTransport`の標準入力パイプに`F_SETNOSIGPIPE`。
- **Minor 12（最小）**: `LocalHTTPListener`でポート固定時のみ`allowLocalEndpointReuse`。テストは`ListenerReuseTests`。窓を超える遅れは未検証。
- **Minor 13**: `adr/README.md`、`specs/independent-session-runtime.md`、ADR 0233の7節見出し・`ChatAdoptionState`・`PhloxHandoverFormat`の記述を現状へ合わせた。
- **Minor 11・14・M7の一部**: ADR「未対応・制限」に限界として記載。

## 新旧ホスト入れ替えの受入（`session-runtime-handover.test.py`）

一度も端から端まで動かしていなかった計画的な切り替えを、隔離した署名済みDebugアプリとフェイクCLIで検査する。実CLIは使わない。

- **入口（製品の変更なし）**: 利用者と同じ経路を使う。CFBundleVersionだけが違う、同じbundle IDのDebugビルドを2つ用意し（旧＝`--app`、新＝`--update-app`）、旧の画面で実行を始めてから画面を終え、新の画面を開く。新の画面は`requestHostUpdate`で旧ホストへ`handover`を送る。世代は`data/session-runtime/discovery.json`（`generation`・`pid`・`runtimeBuild`・`updateStatus`・`state`）で観測する。延期・中止の理由は`updateStatus`、起動失敗は`failure`にしか出ないので、待機はこれらで即座に失敗させる。
- **継承**: `session-runtime-lifecycle.test.py`の隔離（`PHLOX_DATA_DIR`・defaults suite・`CFFIXED_USER_HOME`・フェイクの実行パス）と後片付けを継承する。holderは`setsid`済みで旧ホストの終了後も残るので、後片付けの前に自分のストアの`discovery.json`と`holders/*/holder.json`、`fake-state/*.json`を読み直し、実行パスと開始時刻を照合したプロセスだけを終了対象に加える。
- **シナリオ**（1回の実行で1つ。`--scenario`）:
  - `planned`: PTY・Cursor・Codex・Claudeを動かす。Codexは承認に答えて質問待ち（ターン進行中で出力が続く）、Claudeはツール承認待ち。新の画面を開くと延期される（PTY・Cursor）。何も変わらないことを確かめ、画面を閉じてからCursorを完了させ、PTYとCursorのセッションを外し、新の画面を開き直すと切り替わる。
  - `adoption-failure`: CodexとClaudeを承認待ちにし、Claudeのholderのソケットだけを`chmod 000`にしてから切り替える（新ホストの接続がEACCESで失敗する。旧ホストは既存の接続を使うので確定点は作れる）。変えた権限は記録し、後片付けで戻す。
- **フェイクの拡張（後方互換）**: Codex側はターンごとにターンID・要求ID・項目IDを分け（1ターン目は従来の`runtime-turn-1`・7001・7002・`runtime-answer`のまま）、メソッドの受信回数（`methodCounts`）と、ターンごとに出力した連番（`streamed`）を記録する。連番の出力と状態の保存は同じロックの中で行う（ターン完了の後に出力が混ざらない）。Claude側はメソッドの受信回数と、制御ディレクトリの`control-check-<名前>`で、受け継いだ`PHLOX_API_URL`・`PHLOX_TOKEN`によるControl API（`GET /sessions`）の結果を記録する。

| 受入 | `planned`で確かめること | `adoption-failure`で確かめること |
|---|---|---|
| A1 | Codex/Claudeの子とholderが同じプロセス（PID・開始時刻・実行パス）。旧ホストは終了し、新ホストは別PID・別世代・新の`runtimeBuild`。Codexの出力が切り替え後も続く | Claude・Codexの子とholderが同じプロセス |
| A2 | Codexの1ターン目の出力の連番が、フェイクが出した順と完全に一致（欠落・重複なし。切り替えをまたぐ）。背圧（保持量の上限）は単体 | — |
| A3 | Codexの質問・Claudeの承認が、切り替え後に同じ要求IDで1件だけ再提示され、回答が子へ1回だけ届く（同じ操作の再送は同じ結果、新しい操作は`false`、フェイクの重複受信なし）。`initialize`・`thread/start`・`turn/start`の受信回数が増えず、`thread/resume`は0回 | Codexの承認が1件だけ再提示される |
| A4 | 切り替え前の送信操作を旧世代のまま新ホストへ送ると409で、子の受信は1回のまま。holderの結果不明の送信は単体（`CodexHandoverTests`・`ProcessHolderTests`） | — |
| A5 | 旧ホストのプロセスが終了し、旧世代の要求は新ホストで409。古い世代の書込・終了の拒否はholder単体（テストからholderへ接続すると書込権を奪うので、受入では接続しない） | — |
| A6 | 切り替え後に作ったCodexチャットの子は、新ホストと同じ実行ファイルのholderの子で、そのholderの親が新ホスト | — |
| A7 | 旧ホストで起動したClaudeの子が、受け継いだURL・トークンでControl APIに200で届く（ポートの固定と記述子のトークンの再登録）。切り替え後の送信（Codexの2ターン目、Claudeの2ターン目）が同じ子へ届く | — |
| A8 | 確定点は全項目を消費（`checkpoint.json`が無く`consumed.json`に両セッション） | Claudeの子とholderは生存、セッションは`restoreState`が失敗（`handover recovery needed`）、確定点にはClaudeの項目だけが残る（Codexは消費）。送信・`resumeChat`の後も新しいClaudeの子・holderが現れず、元の子の入力も増えない |
| A9 | PTY・Cursorが動く間の要求は延期され、`updateStatus`に理由が出て、世代・ホスト・全ての子・確定点が変わらない | — |
| A10 | 単体（`HandoverCheckpointTests`等） | — |
| A11 | 既存の互換テスト（`AppBootstrapTests`） | — |

- **受入で検査しないもの（理由）**: A8の「再試行で採用できる」（次の起動にはホストの停止が要るが、明示停止が復旧待ちの子をどう扱うかをADRが定めていない。PMの判断待ち）。hookの配送（構造化チャットのフェイクにはhookの観測点が無い。ポートの固定はControlと同じ仕組み）。iOS経路。背圧中の延期（64MiBの出力が要る。holder単体で検査）。
- **実行**: 2つのビルドの作り方・コマンド・期限・合格条件はテストファイルの先頭の説明。ビルドとテストの実行はchecker。
- **初回実行（pm16）**: `adoption-failure`は合格。`planned`は延期の確認までは通ったが、延期の後で閉じた新の画面を、切り替えの段でもう一度閉じようとして失敗した（テストの誤り。製品の不具合ではない）。開いている画面を1つの状態（`self.gui`。旧/新）として持ち、開く・閉じる操作がその状態を確かめる形に直した。延期の段より先は未実走。
- **隔離の穴（修正）**: lifecycle受入とその継承は、起動するプロセス（`open`・検査用の補助コマンド）へテストの環境をそのまま渡していた。実行中のPhloxのセッションから起動したシェルでは`PHLOX_API_URL`・`PHLOX_TOKEN`・`PHLOX_SESSION_ID`・`PHLOX_CLI`が利用者のPhloxを指す。継承環境から`PHLOX_`で始まる値を落とし、隔離用に自分で設定した値だけを渡す（`inherited_environment`）。
- **版の前提**: 画面は自分のビルド番号がホストより数値で大きいときだけ更新を要求する（`HostBuildOrder`）。`--update-app`のCFBundleVersionは`--app`より数値で大きくなければならず、テストは最初に確かめる。

## 古い版の画面がホストを古い版へ戻す問題（修正）

- **事実**: `DesktopCompositionRoot.requestHostUpdate`は、画面とホストのビルド番号が違えば（`hostBuild != ownBuild`）更新を要求していた。古い版の画面を開くと、新しいホストが古い版へ切り替わる。ADR 0233は「新版の画面が」要求すると定めている。
- **直し**: 比較を純粋関数`HostBuildOrder.isNewer(_:than:)`（`AppBootstrap/HostUpdateRetry.swift`）へ切り出し、画面のビルド番号がホストより数値で大きいときだけ要求する。`.`区切りの各要素を整数として前から比べ、足りない要素は0とみなす（`57`と`57.0`は同じ）。どちらかが空・数値でない要素を含む・符号つきなら要求しない（更新しない側に倒す。止めない）。
- **テスト**: `HostUpdateRetryTests`に、新しい版だけ真・同じ版と古い版は偽・桁数の違い（`9`と`10`）・要素数の違い・空や数値でない版は偽、を追加。

## 切り替え後にCodexの質問が2件になる問題（planned 2回目。修正）

- **症状**: 採用の段で「Codexの質問が同じ要求IDで1件」が期限切れ。診断ではCodexのセッションに未回答の質問が2件（切り替え前のID`82962875…`と、新しいID`DA69B44F…`）、`status`は`idle`。Claudeは1件で`awaitingUserQuestion`。
- **原因1（製品）**: Codexの質問カードの要求IDは、承認ブローカーが要求ごとに作る乱数UUID（`ChatApprovalBroker.makeUserInputRequest`の`id: UUID()`）だった。新ホストは会話ログから元のカード（未回答のまま保存）を戻し（`restoreTranscriptFromStore`）、続いて再投入した同じ要求（JSON-RPCのID 7002）からブローカーが別のIDで2枚目を作った。元のカードはブローカーの待ち（continuation）を持たず、答えても子へ届かない。Claudeは子が付けた`request_id`をカードのIDに使うので、再投入したカードが保存側のカードを同じIDで置き換え、1件になる。
- **原因2（製品）**: 採用後の`adoptCodexReadState`が`thread/read`の状態をそのまま`status`へ書いていた（`applyRestoredThreadStatus`）。再投入で質問待ちになった後に上書きされる。フェイクは`idle`を返したので`idle`になった。0.147.0のスキーマでは質問待ちは`active`（`waitingOnUserInput`）で、これは`running`へ写るので、本物でも質問待ちが失われると推定する（実CLIでは未確認）。
- **原因3（フェイクの前提）**: Codexのフェイクの`thread/read`は、ターン進行中でも`idle`・ターン0件を返していた。本物（0.147.0のスキーマ）は`active`と待ちの印（`waitingOnApproval`/`waitingOnUserInput`）、進行中のターンを返す。
- **保存ファイルの`expired`**: 失敗時の診断では2件とも未回答（`pending`）。保存ファイルで2件とも`expired`なのは、診断の後の後片付けでセッションを終了したとき（`terminate`→`expireAllPendingUserQuestions`）の書き込みと推定する（終了経路のコードで確認。実行で順序は確かめていない）。2件のタイムスタンプの差（約8.6秒）は作成時刻の差（2件目は新ホストが作り直した時刻）で、失効の時刻ではない。
- **直し**: (1) ブローカーは質問のIDを`threadId`・`turnId`・`itemId`から導く（SHA-256の先頭16バイト。プロセスごとに種が変わる`Hasher`は使わない）。同じ3つ組の質問が未回答のまま重なったときだけ乱数IDに戻す。(2) `adoptCodexReadState`は、`thread/read`を反映した後、再投入した要求が未応答のまま残っていれば、その待ち状態に戻す（読み取りが先なら、後から届く要求が待ち状態にする）。(3) フェイクの`thread/read`は、ターン進行中なら`active`と待ちの印、進行中のターンを返す。(4) 受入は、採用後のCodexの`status`が`awaitingUserQuestion`であることも確かめる。
- **テスト**: `HandoverQuestionReinjectionTests`（SessionFeature）。旧ホスト役の画面状態が質問を受けて会話ログに保存し、同じ保存先から新ホスト役が採用し、同じ要求の原文を新しいブローカーへ再投入する。`thread/read`は本物と同じ`active`＋`waitingOnUserInput`。未回答の質問が元のIDで1件、`awaitingUserQuestion`、失効していないこと、答えると再投入した要求が1回だけ回答で決着することを確かめる。ブローカー単体で、同じ3つ組は同じID・違えば違うID・未回答の重複は別IDを確かめる。
- **c（新ホストが起動した`model/list`だけのapp-server）**: 子のプロセスではない。ホストの起動時のモデル一覧の更新（`CompositionRoot`の`AgentModelCatalog.refresh()`→`LiveAgentModelProvider.runCodexModelList`）が、`codex app-server`を一時的に起動して`initialize`・`model/list`だけを送り、終える。旧ホスト（PID 47536）も起動時に同じものを起動している（PID 47675）。採用したセッションの子は作り直していない（引き継いだ子47556の`initialize`・`thread/start`・`turn/start`は増えていない）。
- **目録**: `runtime-host-handover`の`codePaths`に`ChatApprovalBroker.swift`、`testIDs`に`HandoverQuestionReinjectionTests`を足し、期待に「Codexは質問待ちのまま」を足した（未リリースの版1なので版は上げない）。
- **残り**: Codexの承認カードのIDは乱数のままで、更新をまたぐと変わる（ADRの未対応・制限）。同じ3つ組の質問が、前の質問の回答・失効の後に同じ画面状態へもう一度届くと、同じIDになりカードが出ない（本物のCodexでは1つの項目が2度質問しない前提。既存テストにこの使い方は無い）。共通の状態の写像（`ThreadStatus.sessionStatus`）は`waitingOnUserInput`を`running`へ写すので、採用後に届く`thread/status/changed`は質問待ちを`running`へ変え得る（今回の変更より前からある。範囲外）。

## 切り替え後に引き継いだ子のControl APIが401になる問題（planned 3回目。修正）

- **症状**: 採用後、旧ホストが起動したClaudeの子が、受け継いだ`PHLOX_API_URL`・`PHLOX_TOKEN`で`GET /sessions`を呼ぶと401（`fake-state/92153.json`の`controlChecks`）。ポートは確定点で引き継がれている（`consumed.json`の`controlPort` 54571＝新ホストの`controlURL`）。
- **原因（製品）**: 子の認証トークンはホストのメモリ（`SessionTokenStore`）にだけあり、`sessions.json`へは書かない（`PersistedSessionDescriptor.encode`がCWE-312対応で意図的に省く）。新ホストの復元（`SessionRestoreCoordinator.restoreSession`）は`descriptor.token ?? SessionSpawnService.makeToken()`で、`descriptor.token`は常にnilなので新しいトークンを登録する。子の環境のトークンは旧ホストのもののまま。ADRの「トークンは記述子に永続化され、復元時に再登録される」はコードと食い違っていた（ADRを直した）。
- **hook**: `HookServer`も同じ`SessionTokenStore`で`Authorization: Bearer`を照合する（`hook-dispatcher.sh`は`PHLOX_TOKEN`を送る）。ただし構造化チャット（引き継ぎの対象）はhookを使わない（`AgentLaunchPlanner`が`appServer`では`hookIntegration: .none`にし、`CLAUDE_HOOKS_URL`も`--settings`も渡さない）。hookを使うPTYは引き継がない（延期）ので、今回の経路でhookが401になる子は無い。トークンの再登録はhookにも同じく効く。
- **iOS（モバイル）**: 端末のトークンはKeychain（`KeychainDeviceTokenStore`）に保存され、ホストの起動ごとに作り直さないので、この問題は無い（新旧が同じ署名・bundle IDである前提。実機では未確認）。
- **直し**: 確定点の項目に`token`（任意）を足す。旧ホストは`SessionTokenStore`から各セッションのトークンを入れて書く。新ホストは確定点に項目のあるセッションへ、そのトークンを再登録する（無ければ従来どおり新しいトークン）。全項目を消費するときは、トークンを外して書き直してから`consumed.json`へ改名する。形式の版は上げない（任意の項目で、旧形式も読める）。
- **秘密の扱い**: 確定点は既存の0600・所有者確認つきのファイル。受入の診断は項目を選んで出す（トークンは出さない）。`discovery.json`は確定点を含まない。確定点の読み書きの失敗のログは中身を出さない。
- **テスト**: `HandoverCheckpointTests`（トークンの往復、消費後の`consumed.json`にトークンが無い、一部消費で残る項目はトークンを保つ、旧形式はトークン無しで読める）。`SessionRestoreCoordinator`の採用で、確定点のトークンで認証でき、別のトークンでは認証できないこと（`HandoverRecoveryRestoreTests`）。受入は、同じControl APIの検査を切り替えの前にも行い（前は200、後も200）、`consumed.json`にトークンが無いこと、`adoption-failure`で残る項目がトークンを保つこと（値は出さない）を確かめる。hookの検査は足さない（構造化チャットの子は`CLAUDE_HOOKS_URL`を持たない）。
- **他の「旧ホストの起動時の値」の点検（切り替え後の段）**: `PHLOX_API_URL`は確定点の`controlPort`で同じポートを厳密に束縛する。`PHLOX_SESSION_ID`は同じ。holderのソケットはholderの記録（確定点）で解決し、置き場はストアのパスから決まる（同じストアなので同じ）。`PHLOX_CLI`は旧バンドルのコピー（`session-runtime-bundles/<ハッシュ>.app/Contents/Resources/scripts/phlox`）を指す。コピーを消す処理は無い（`SessionRuntimeBundleStore`が消すのは作りかけの`staging`だけ）ので、旧バンドルのコピーは残り、パスは有効（planned-3でも両方のコピーが残り、記述子の`PHLOX_CLI`が存在することを確認）。ただし旧版の`phlox`は接続拒否の再試行を持たない（ADRの既知の制限）。hookの設定（`--settings`）と`CLAUDE_HOOKS_URL`は構造化チャットには無い。Codexの子も同じ`PHLOX_TOKEN`を持つので、今回の直しで同じく通る。
