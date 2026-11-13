---
status: accepted
date: 2026-11-12
---

# 0233: 子プロセスの寿命を保持するholderと、更新できる実行サービスを分ける

実装済み（フェイクCLIを使った新旧ホスト入れ替えの受入まで。実CLIでの無停止更新は未検証）。作業記録は[0233](../delivery/0233-runtime-logic-update-worklog.md)。この版はPM裁定（採用失敗時に生存実行を終了・再生成しない等）を反映した改訂で、初版の「採用失敗→従来の再生成」は撤回した。

## 問題

常駐実行サービス（`SessionRuntimeHost`、以下ホスト）は、イベント解釈・セッション制御・カード組立・索引・iOS投影に加え、子CLIの`Process`と入出力パイプまで所有する。画面だけが更新でき、ホストのコードは稼働中のセッションがすべて終わるまで古いまま残る。

- `SessionRuntimeLauncher.connect`は`host.lock`の所有者が居れば必ずそれへ接続する。
- `requestShutdown`は全チャットとPTYを終了する。再起動後の復元は、PTYを記録PIDで回収して再生成し、チャットは新しいCLIを起動して`thread resume`する。
- `LineDelimitedProcessTransport`が`Process`と3本のパイプを所有する。親が死ぬとパイプが閉じる。
- 通信状態はメモリにある（`JSONRPCClient`の要求番号と未応答、Claudeの承認・質問・ターン、GUI操作台帳は世代ごと）。
- 子の環境にhook/Control URLとトークンが固定される。ポートは保存値を優先するが、使用中ならランダムへ黙って切り替わる。トークン（`PHLOX_TOKEN`。Control APIとhookの両方の認証）は、ホストのメモリ（`SessionTokenStore`）にだけあり、`sessions.json`へは書かない（`PersistedSessionDescriptor.encode`が意図的に省く）。再起動後の復元は新しいトークンを発行する（`SessionRestoreCoordinator.restoreSession`）。`hook-dispatcher.sh`は失敗時にイベントを捨てる。子が参照するスクリプトはホスト自身のバンドルコピー内にある。
- 旧1.14.xのホストはholderも切り離し操作も持たない。後付けで使えない。

## 制約

1. 子CLIの親とstdioの所有者は、その子が生きている間は入れ替えない。ほかは再起動できる。
2. 旧新が同じ子へ同時に書けない（単一の書込権、世代つき）。
3. 確認前の出力は捨てない（データ損失になるため）。保持量が上限（既定64MiB）に達したら、holderは子の出力の読み取りを止める。子はパイプが満杯になった時点で書き込みに詰まり、進行が止まる（意図した停止。常駐側の確認が進むと再開する）。この状態は`backpressured`として公開し、計画的更新はゲートで延期する。
4. 送信は識別子つき。結果不明は自動再送しない。
5. 承認・質問は、未応答の要求を再接続後に再構成し、同じ要求へ一度だけ応答する。
6. 生存または生存不明のholderと子を、更新の失敗で終了・再生成しない。「生存を確認できない」は「不存在」ではない。
7. 計画的更新の確定点（処理済み受信番号・会話ログ・クライアント状態・送信結果）を一つに揃え、チェックポイントを永続化してから切り替える。holderの保持枠は、常駐側が行を内部状態へ反映した時点で確認済み番号を進めて解放する（解放しないと上限で子が止まる）。このため、常駐側が計画外に落ちた場合の再生は保証しない（`recoveryNeeded`で残す。限界として明記）。計画的更新では確定点の反映済み番号以降の行を必ず保持している（確認は反映済み番号を超えない）。
8. 未対応の経路（PTY、Cursor、holderを使わない子）が稼働中なら、止めずに更新を延期して理由を返す。

## 決定

### 1. 子ごとのholder

各構造化チャット（Codex app-server、Claude stream-json）の子ごとに、小さな専用プロセス（holder、同じ署名済みアプリの`--session-holder`モード）を置く。holderがその子の親でstdioを持つ。holderはプロトコルを解釈せず、既存の`LineDelimitedProcessTransport`を内部に使う。

| 値 | 意味 |
|---|---|
| 受信シーケンス番号 | 子の標準出力の各行の通し番号（1から）。確認前の行は捨てず、保持量が上限に達したら子の出力の読み取りを止める（`backpressured`） |
| 送信ID | 常駐側の書込要求の識別子。`accepted`→`written`/`failed`を記録する。結果が返らなかった送信は、再接続後も`unknown`のまま返し、再送しない |
| 書込権の世代（epoch） | 接続（attach）のたびに増える。最大世代の接続だけが書込・割込・終了を行える。古い世代は拒否される |
| 確認済み番号 | 常駐側が確定点で通知する。それ以下の保持分だけ破棄できる |

holderは子の標準入力を閉じず、ホストの切断・入れ替えで子を終了しない。通常の更新はholderを終了しない。holderの停止は子の終了後か明示停止に限る。holderのプロセス自身が死ぬとパイプが閉じる。そのためSIGTERMを子へ伝播しないことでは継続を保証しない（holderは小さく固定し、SIGHUP/SIGPIPEを無視して`setsid`する）。保持はメモリのみ（ディスクへ出力を書かない）。holderのクラッシュ、OS再起動は対象外。

holderの版は子の寿命と一致する。新しい子には最新のバンドルのholderを使い、旧holderは子の終了後に自分で終了する。holderのプロトコルは`HolderProtocol.version`で固定し、能力は`hello`の応答で広げる。接続は`/tmp/phlox-holders-<uid>-<保存先パスのハッシュ>/`（0700）のUnixドメインソケット（0600、同一ユーザー確認）。`holder.json`（セッションID・子PID・holder版・バンドル版・起動時刻）は`session-runtime/holders/`へ原子的に書く。

### 2. 所有と移送の契約

| 状態 | 所有者 | 更新時の扱い |
|---|---|---|
| 子プロセス、stdin/out/err、終了状態 | holder | 移さない |
| 受信行と番号、送信IDの結果、書込権の世代 | holder | 移さない。確認済み番号までを確定後に破棄 |
| Codex通信状態（要求番号、スレッドID、有効なターンID、未応答のサーバー要求の原文） | ホストの`JSONRPCClient`/`CodexAppServerClient`/`CodexStructuredAgentClient` | チェックポイントへ直列化 |
| Claude通信状態（セッションID、起動引数、モデル・権限、ターン開閉、未応答の制御要求の原文） | `ClaudeChatClient` | チェックポイントへ直列化 |
| 会話ログ、セッション記述子 | 既存の永続層 | 確定点の前に確定的に保存 |
| 子の認証トークン（`PHLOX_TOKEN`。Control API・hook） | ホストの`SessionTokenStore`（メモリのみ。`sessions.json`には書かない） | チェックポイントの項目（`HandoverSession.token`）へ。新ホストが同じセッションへ再登録し、全項目の消費時に外す |
| ターン実行状態（実行中か、ターンID、開始時刻） | `ChatSessionViewModel` | チェックポイントのクライアント状態（Claudeはターン開閉、Codexは有効なターンID）へ。VM専用の`ChatAdoptionState`型は作らず、採用後の実行状態はクライアントの再注入で戻す |
| 画面表示用の一時状態（スクロール、下書きのフォーカス、停滞監視の計時など） | 画面/VM | 移さない（再計算または初期化）。保証しない |
| GUI操作台帳 | ホストのメモリ（世代ごと） | 移さない。世代が変わると未完了操作は`staleGeneration`→結果不明（自動再送しない）。送信の二重実行はholderの送信IDで防ぐ |
| hook/Controlの受付口、ポート、トークン | ホスト | 下記4 |
| バンドルコピー、スクリプト | `session-runtime-bundles/<hash>.app` | 削除しない（生存holderまたは子が参照する版は保持。整理は未実装のままとし、導入時に参照中の版を除外する） |

### 3. 計画的ホスト更新

ホストの入れ替えは、確定点を作ってから行う。ターンの完了は待たない。進行中のターン、未応答の承認・質問を保ったまま行う。

**ゲート（旧ホストが判定。不適合なら何も変えず`deferred(理由)`を返す）**
- 生存するPTY、Cursorの実行、holderを使わない構造化チャットの子が無い。
- holderが`backpressured`（保持量が上限に達して子が停止中）でない。結果不明の送信は記録として持ち越すが、ゲートの対象にはしない。
- 新バンドルが署名検証を通り、`PhloxHandoverFormat`（Info.plist。整数。範囲ではなく完全一致）が旧ホストの書くチェックポイント形式と等しい。holderプロトコル版を新ホストが扱える。
- 旧ホストの概要が空であることだけでは停止安全とみなさない（旧1.14.x等の`supportsHandover`を持たないホストは移送対象外で、接続を維持する）。

**手順**
1. 新版の画面が、旧ホストの`supportsHandover`を確認して`handover`操作を送る。新版とは、画面のビルド番号（CFBundleVersion）がホストの`runtimeBuild`より数値で大きいもの（`.`区切りの各要素を整数として前から比べ、足りない要素は0とみなす。`HostBuildOrder`）。同じ版・古い版の画面、どちらかの版が空・数値でない場合は要求しない（古い画面がホストを古い版へ戻さない）。旧ホストは受付を止める（新規セッション・新規ターンは`busy`、停止・承認応答は受ける）。
2. 各セッションを安全な確定点へ進める: 送信中のRPCを応答まで（期限つき）待つ → holderからの配送を一時停止 → クライアントの受信ループが配送済みの全行を処理し終えるまで待つ（pull型の受信で「次の行を要求した」ことを処理完了とみなす）→ VMにフェンス（順序つきの空イベント）を流し、全イベントがVMで適用されたことを確認 → 会話ログとセッション記述子を保存 → チェックポイントを原子的に書いてfsync → holderへ確認済み番号を通知。いずれかが期限内に済まなければ**取消し**（配送を再開し、何も変えず`deferred`を返す）。取消し可能なのはここまで。
3. 確定後（不可逆）: ホストはholderの書込権を手放し、hook/Control/デスクトップ通信の受付を閉じる（処理中の要求は終えてから）、`host.lock`を解放し、既存のランチャーで新バンドルのホストを起動し、準備完了を待つ。子とholderは終了しない。
4. 新ホストは`host.lock`を取得し、保存済みポートを厳密に束縛する（束縛できなければ起動失敗にし、ランダムポートへ切り替えない）。`restorePersistedSessions`より前に、生存holderを探して**採用**する。採用はチェックポイントを読み、新しい世代で書込権を取り、クライアントに状態を注入し、`initialize`/`thread resume`/`turnStart`/起動引数を再発行せず、確認済みの次の番号から通常どおり受信する。未応答の承認・質問は、保存した要求の原文を通常の受信経路へ再投入して再構成する（応答は新ホストが一度だけ返す）。
5. 採用に失敗した、またはholderの生存を確認できないセッションは、`recoveryNeeded`として残す。`resume`の再生成も終了もしない。復旧は同じ採用を再試行する（GUIの再接続または次の起動）。生存holderが無いと確定でき（ソケットなし・子PIDが無い）、かつチェックポイントも無い場合に限り、従来の復元（再生成）を使う。
   - **チェックポイントは項目ごとに消費する（PM裁定）。** 新ホストは、採用に成功したセッションの項目だけをチェックポイントから外す（残りは原子的に書き直す）。失敗・不明（採用の例外、子の起動準備の失敗、記述子が無い等）の項目は残すので、次の起動が同じ採用を再試行する。残っている項目のセッションは、通常の復元でも孤児回収（`reconcileOrphan`）の対象にせず、生きている子を終了も再生成もしない。チェックポイント全体の削除（consumed化）は、全項目が採用成功または利用者の明示的な放棄で外れたときだけ。放棄した項目の外し方は`HandoverCheckpointStore.consume`（採用成功と同じ経路）。放棄の画面操作は未実装（後続）。
   - 新ホストは、採用に失敗したセッションを`recoveryNeeded`として画面側へ公開する（`DashboardViewModel.handoverRecoveryNeededSessionIDs`）。このセッションの`resume`（開き直し）は子を再生成するので拒否し、復旧待ちが残る間は次の計画的更新も延期する（新しい確定点で残した項目を失わないため）。
   - 項目の書き直しに失敗したときは、チェックポイント全体を残す（子を終了させるより、残った項目を再度採用しようとする方を許容する。ただし採用済みの項目は、新ホストが確認済みにした行がholderから破棄されているので、採用時の番号の連続性の検査（`firstRetainedSeq`が反映済み番号+1以下、`lastSeq`が反映済み番号以上）に失敗し、`adoptionFailed`（復旧待ち）になる。重複行を受けて整合する、のではなく、欠落・重複を検出して安全に失敗する）。
6. 手順3の後に新ホストが起動しなくても、子とholderは生き、チェックポイントは残る。次のホスト起動が手順4で採用する。

### 4. hook/Controlの受付

- 子に埋め込まれたURLとトークンは変えない。ポートは更新前後で同じ値を使う（新ホストは厳密束縛）。トークンは確定点の項目（`HandoverSession.token`）で旧ホストから受け取り、新ホストが同じセッションへ再登録する（採用に失敗して復旧待ちになったセッションも、子が生きているので同じトークンを登録する）。確定点に項目の無いセッションは従来どおり新しいトークンを発行する。
- 受付が閉じている間は、新バンドルの`hook-dispatcher.sh`と`phlox`が接続拒否（要求が届いていない）に限り有限回再試行する。応答を受けた後は再送しない。旧バンドル由来の子は再試行を持たないので、この保証は新構成で開始した子に限る。
  - 再試行するのはcurl終了コード7（接続できない）だけ。0.2秒間隔で最大25回（約5秒。環境変数`PHLOX_CONNECT_RETRY_ATTEMPTS`/`PHLOX_CONNECT_RETRY_INTERVAL`で上書き。テスト用）。タイムアウト（28）・HTTPエラー応答（`-f`の22、`phlox`は2xx以外）・応答の途中の失敗は再試行しない（要求が届いた可能性があり、受付済みの操作を二重に実行しないため）。
  - 子が使う版: 常駐プロセスは`Bundle.main.resourceURL/scripts/`（管理されたバンドルコピーの中）を`hookDispatcherPath`/`cliPath`にし、子の`PHLOX_CLI`・`PHLOX_API_URL`とClaudeの`--settings`のhookコマンドがそれを指す（`CompositionRoot.scriptPath`、`AgentLaunchPlanner`）。ホスト更新後に開始した子から新しい版になる。更新前に開始した子は旧版のスクリプトのまま。
- 処理中のhook/Control要求は閉じる前に完了させる（結果を返してから閉じる）。

### 5. 初回の移行（旧1.14.x）

既存の1.14.xのホストは入れ替えられない。新版の画面は旧ホストへ互換接続したままにし、旧ホストを停止しない。旧ホストの生存セッションが終わるまで、新規チャットも旧ホストのコードで動く（これはPM裁定による移行制限。初回の移行は旧1.14.xの既存実行を保ち、対応前のホストを強制的に置き換えない。ユーザーの決定ではない）。新構成（holder対応のホスト）で起動した後の計画的更新から、手順3が働く。

### 6. 旧サービス由来のCodex思考（段階0）

実装済み。画面が描画の直前に旧サービスのページ・項目から除く。能力フラグは追加しない。画面側の互換であり、無停止更新ではない。

### 7. Codexの確定点と採用（実装済み。実CLIでの検証は未実施）

Codexの子もholder経由で起動し（`AppEnvironment.defaultStructuredClientFactory`）、Claudeと同じ契約（確定点→フェンス→コミット→採用）で引き継ぐ。`HandoverCapableClient`・`HandoverPreparation`・`HandoverSession`・`HandoverCheckpoint`・`NormalizedChatEvent.handoverFence`はそのまま足りる（クライアント状態は不透明な`Data`、エージェント別の版は状態の中に持つ）。

**確定点の中身**（Claudeは1つのactorだが、Codexは`JSONRPCClient`→`CodexAppServerClient`→`CodexStructuredAgentClient`の3層。各層の状態を、フェンスがその層を通った時点で採取して1つの`CodexHandoverState`にまとめる）:
- `JSONRPCClient`: `nextRequestID`（新ホストは続きの番号から。更新前の番号と衝突させない）、**未応答のサーバ要求の原文**（承認・質問。受信した行をそのまま、要求ID・状態つきで記録する。記録は受信ループで同期的に行い、ハンドラの起動を待たない）。`pending`（クライアントからの未応答リクエスト）は運べないので、空であることをゲートにする。
- `CodexAppServerClient`: `turnStates`（thread別の`activeTurnId`・`closedTurnIds`・`hasObservedLifecycle`。`pendingStartGeneration`はゲート）、`nextTurnStartGeneration`。
- `CodexStructuredAgentClient`: `currentThreadId`・`committedThreadId`・`hasEstablishedThread`・`threadIdentityGeneration`・`lastThreadStartParams`（再開始用）・`pendingChildInterrupts`・`nativeImageInputEnabled`・`materializedImageDirectories`（削除責任を引き継ぐためのパス一覧）。`pendingResumeRollback`・`imageTurnInFlight`・`modelChangeInFlight`はゲート。
- 画面側（`ChatSessionViewModel`）の`appServerUserAgent`・Codex設定・Plan状態は、既存の記述子（`appServerUserAgent`・`codexSettings`）の永続値から戻す（確定点に二重に持たない）。
- 状態の先頭に`stateVersion`を持つ。読めない版は採用失敗（復旧待ち）にする。

**フェンスの経路**: 受信行は`holder`→`JSONRPCClient.handle`→通知ストリーム→`CodexAppServerClient`→`ThreadEvent`ストリーム→`CodexStructuredAgentClient`→`orderedEvents`→画面、と非同期のホップを3回越える。ホルダーの配送停止（`quiesce`）だけでは、通知ストリームやイベントストリームの途中に未適用の行が残る。そこで`quiesce`後、**フェンスを通知ストリームの先頭から流し**（`ThreadEvent.handoverFence`を追加）、各層は自分の前にあった全イベントを処理した時点（フェンスが通った時点）で状態を採取する。最上層に届いたら`NormalizedChatEvent.handoverFence`として画面へ流す。`prepareHandover`は最上層への到達を期限つきで待つ（期限切れは取消し。無期限待ちにしない）。

**承認・質問の再投入と、結果不明の応答**:
- 確定点の時点で未応答のサーバ要求は、原文を保存する。新ホストは、受信を始める前に、原文を同じ受信経路（`JSONRPCClient.handle`）へ再投入する。承認ブローカーが新しい承認カードを作り、利用者の応答は新ホストが一度だけ、同じ要求IDで返す。
- Codexの質問カードの要求ID（画面・Control APIの`requestId`）は、要求の`threadId`・`turnId`・`itemId`から決まるUUID（SHA-256の先頭16バイト）にする。会話ログに保存された質問カードと、再投入で作り直したカードが同じIDになり、保存側のカードが置き換わる（1件だけ・元のIDのまま・未回答のまま）。この導出は新旧ホストの間の約束で、変えると更新をまたいだ質問が二重になる。同じ3つ組の質問が未回答のまま重ねて届いたときだけ、後の質問に従来どおりの乱数IDを使う（応答の取り違えを防ぐ）。Claudeは子が付けた`request_id`をそのまま使うので、もともと同じIDになる。
- 採用後の`thread/read`の状態（0.147.0のスキーマでは、質問待ちも`active`＋`waitingOnUserInput`。実CLIでは未確認）で、再投入した要求による待ち状態（質問待ち・承認待ち）を上書きしない。再投入と読み取りのどちらが先に画面へ届いても、未応答の要求が残っていれば待ち状態に収束する。
- 応答を書き込み中の要求（応答送信が未確定）がある間は、ゲートで更新を延期する。
- 応答の書き込み結果が不明（`HolderError.sendResultUnknown`）の要求は、**再投入も再送もしない**。現状の`JSONRPCClient.handleServerRequest`は応答の送信が失敗すると、同じIDへエラー応答を送り直す。結果不明のときにこれをすると二重応答（プロトコル違反）になるので、結果不明のときは送り直さず、要求を「結果不明」として記録する。`HolderTransport.hasUnknownSend`は既存のゲート。採用時に`unknownSendIDs`が空でなければ採用を失敗（復旧待ち）にする（Claudeと同じ）。この状態でCodex側の要求が宙に残り得るが、利用者の中断操作で解消する（自動では何もしない）。

**採用専用経路**（新しい子は作らない）: ファクトリが`HolderTransport(.adopt(record:, fromSeq:))`を持つCodexクライアントを作り、状態を預ける（`prepareAdoption(state:)`）。`completeAdoption()`は、(1)状態を復号（失敗は`adoptionFailed`）、(2)holderへ接続（書込権を取る。失敗しても子には何もしない）、(3)`unknownSendIDs`の確認、(4)3層へ状態を適用、(5)保存した要求の原文を再投入、(6)`rpc.start()`→`client.start()`→`start()`の順に受信を開始する。**`initialize`・`thread/start`・`thread/resume`・`turn/start`は再発行しない**（子のapp-serverは初期化済みで、スレッドもターンも動いている）。進行中のターンは`turnStates`で復元し、画面は更新後に届く通知で実行中表示へ戻る。画面側は`initialize`の戻り値が無いので、`appServerUserAgent`などを記述子から戻す。

**コミット**: 受信ループを止め、`HolderTransport.confirm`・`releaseForHandover`を行い、**`transport.close()`を呼ばない**（`close`は子を終了する）。`CodexAppServerClient.closeRequested`を立てて、入力の途切れを「予期しない終了」として扱わない（`exitedUnexpectedly`・`.error`・`processExited`を出さない）。コミット後の`close()`は子へ触れない。

**`isHandoverParticipant`をtrueにする条件**: 型が`HandoverCapableClient`に適合することで`true`になる（`ownedClient is any HandoverCapableClient`）。holderを使わないCodex（GUI直起動・テスト）は、`handoverGateReason()`が「holder経由ではありません」を返して更新を延期する（現行と同じ結果）。ゲートは、holder生存・結果不明の送信なし・`rpc.pending`が空・`pendingStartGeneration`なし・`pendingResumeRollback`なし・画像/モデル変更の進行なし・応答書き込み中の承認なし・中断処理中でない、のとき通る。

**失敗時**: 採用の失敗（状態を読めない・holderへ接続できない・結果不明の送信がある）は、Claudeと同じ復旧待ち（`recoveryNeeded`。子は終了・再生成しない。確定点の項目は残る）。

**実装しないもの**: 新旧のCodexバージョン差の吸収（`stateVersion`不一致は復旧待ち）。実CLIでの検証は今回の範囲外（費用と環境はPMへ報告）。

## 比較した案

| 案 | 判断 |
|---|---|
| 子ごとのholder（採用） | holder間に共有状態が無く、新旧が共存し、子と共に終了する |
| 1つの共通keeper | 更新できない共有プロセスが残り、共有状態の理由も無い |
| 旧新ホストの二重起動 | 共有保存先の競合（ロック・復元・書込） |
| Codex `app-server --listen unix://`/`claude --bg`への再接続 | 承認の保持・スレッド共有は未確認。成立が確認できるまで依存しない |
| PTYのmaster fd引継ぎ | 対象外。ゲートで延期 |
| 全イベントの再生で状態を復元 | 副作用の抑止と決定性の保証が重い。計画的更新は確定点からの採用で足りる |

## 未対応・制限

- ホスト/holderのクラッシュ、OS再起動、ログアウトは対象外（holderが死ねば子のパイプが閉じる）。
- PTY、Cursor、構造化でないエージェントは移送しない。稼働中なら延期する。
- 画面の一時状態は保証しない。会話ログ・保留中の承認と質問・実行中ターン・送信識別は保証する。
- 旧バンドル由来の子は、hook/Controlの接続拒否の再試行を持たない。
- 採用に失敗して残った項目（`recoveryNeeded`）を利用者が放棄する画面操作は未実装。それまでは、holderと子が既に無くなった項目もチェックポイントに残り、次の起動で再び採用に失敗する（子は終了も再生成もされない）。
- `performHandover`（App層の手順全体）の順序を切り出した単体テストは無い。部品（門・確定点・クライアントの準備と採用・holder）ごとに検証し、全体の順序は手順の隔離したフェイクでの受入に委ねる。
- 固定ポートの再束縛（更新で旧ホストの終了直後に同じポートを束縛する）は、`allowLocalEndpointReuse`（ポート固定時のみ）と`HookServer.start(exactPort:)`の既存の再試行（5秒）に頼る。この窓を超える遅れや、実OSでの動作は未確認。束縛できなければ起動失敗にし、ランダムポートへ切り替えない。
- 確定点は子の認証トークンを含む（所有者だけが読める0600のファイル。子の環境変数にある値と同じ秘密）。全項目を採用し終えた時点で、トークンを外してから`consumed.json`へ改名する。採用に失敗して残った項目は、再試行のためにトークンを持ったまま`checkpoint.json`に残る。トークンの無い確定点（この変更より前の形式）から採用した子は、新ホストが別のトークンを発行するので、その子からのControl API・hookは401になる（子は止めず、採用は成功として扱う）。
- 結果不明の送信（応答の書き込み途中で接続が切れた等）は自動再送しない（二重実行より未実行を選ぶ）。
- 採用時の連続性検査は、holderの保持行がチェックポイントの適用済み番号の続きから始まらない（最古番号が適用済み+1より大きい）場合、または最新番号が適用済み番号より小さい場合に採用失敗にする。欠落したまま続行しない（子は終了も再生成もされない）。
- 実CLIでの検証は未実施。隔離したフェイクで成立を検証する。実CLIの確認が必要な場合の費用と環境はPMへ報告する。
- 終了していないPTY・Cursorのセッションがある間は、更新を延期し続ける。PTY・Cursorはholderを持たず、切り替えると止まるため（契約どおりの延期）。Cursorはターンの合間にプロセスが無くても、セッションが終了（`processExit`）していなければ延期理由に残る。
- 復旧待ちのID集合をsnapshot/overviewの`handoverRecoveryNeededSessionIDs`で公開し、画面に件数と自動更新の延期を表示する。記述子が欠落・不整合でセッション行を作れない場合も通知する。セッション行がある場合は`restoreState`（失敗）と`status`（エラー）も表示する。復旧待ちの開き直し（`resumeChat`）は拒否し、生きた子と確定点を保持する。
- 復旧待ちのセッションへの送信は、いったん受け付けた後で失敗（`sendFailure`）として公開する（受付の時点では拒否しない。子へは届けず、新しい子も起動しない）。
- 復旧待ちの「再試行で採用できる」は、隔離アプリの受入では検査していない（次の起動にはホストの停止が要り、明示停止が復旧待ちの子をどう扱うかを決めていないため）。単体では、失敗した項目が確定点に残ること（`HandoverCheckpointTests`の`consumingOnlyAdoptedSessionsKeepsTheFailedOnesForRetry`）と、失敗した採用が孤児回収しないこと（`HandoverRecoveryRestoreTests`）だけを確かめる。
- 確定点（`checkpoint.json`）が読めない・不正なときは、ホストは起動しない（通常の復元へ進むと、記録PIDの孤児回収で生きた子を終了させ得るため）。利用者への案内や、確定点を退避して起動する逃げ道は無い。
- Codexの承認カードのID（`pendingApprovals[].id`）は乱数のままで、更新をまたぐと変わる（承認カードは会話ログに保存されず、再投入で1件だけ作り直される）。更新前に取得したIDで新ホストへ応答すると何も起きない（子へは届かず、取り直せば答えられる）。
- 常駐側が落ちている間に子が終了すると、holderは終了を届ける相手が無いまま最長24時間残る（`ProcessHolder`の`orphanLinger`）。その間に子のPIDが別のプロセスに再利用されると、`unmanagedHolderSessions`が生きた未管理の実行と誤認し、更新を中止させ得る（何も止めず、延期と同じ扱い）。

## 受入条件

| # | 条件 | 検査 |
|---|---|---|
| A1 | ホスト更新の前後でCodex/Claudeの同一CLI PIDが続き、進行中のターンの出力が続く | 隔離アプリ受入（フェイクCLI） |
| A2 | 更新中の出力に欠落・重複が無い（受信番号が連続）。保持量が上限に達しても捨てず、子の読み取りを止めて`backpressured`を公開し、確認が進むと再開する。背圧中の更新は延期される | holder単体＋受入 |
| A3 | 未応答の承認・質問が更新後も残り、同じ要求へ一度だけ応答する（子側の受信回数1） | 受入 |
| A4 | 送信受付の直後の切断・更新でも二重実行しない。結果不明の入力を再送しない | holder単体＋受入 |
| A5 | 権限のない旧writer（古い世代）の書込・終了が拒否される | holder単体 |
| A6 | 更新後に開始した新規チャットは新ホストの処理で動く | 受入 |
| A7 | GUI/iOS/Control API/hookが既存契約で動く。更新中の接続拒否は再試行で失われない | 受入＋既存テスト |
| A8 | 採用失敗・holder生存不明でも子を終了・再生成せず、`recoveryNeeded`で残る。チェックポイントの当該項目も残り（採用成功の項目だけ消費）、次の起動の通常復元は孤児回収しない。再試行で採用できる | 単体＋受入 |
| A9 | PTY/Cursor稼働中は更新が延期され、理由が返り、何も止まらない | 単体＋受入 |
| A10 | チェックポイント形式の不適合時は更新延期 | 単体 |
| A11 | 旧1.14.xのホストへは互換接続のまま、停止・移送を試みない | 既存互換テスト |

「隔離アプリ受入」「受入」は`macos/scripts/tests/session-runtime-handover.test.py`（CFBundleVersionだけが違う2つの署名済みDebugビルドとフェイクCLIで、計画的な切り替えと採用失敗を検査する）。各条件との対応と、受入で検査しない部分は[作業記録](../delivery/0233-runtime-logic-update-worklog.md)の「新旧ホスト入れ替えの受入」。
