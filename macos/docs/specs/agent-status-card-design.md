---
status: active
last-verified: 2026-11-07
---

# エージェント状態カード（設計書）

> **このファイルの役割**: [agent-status-card.md](agent-status-card.md)（要件）を満たす実装の設計。保存形式の変更、イベントの流れ、カードの組み立て規則、描画、テスト、実装の順番。
> **書かないもの**: 何を満たすべきか（→ 要件書）、なぜこの方式か（→ [ADR 0226](../adr/0226-agent-status-card-derived-from-transcript.md)・[ADR 0227](../adr/0227-status-card-icons-inside-card-only.md)）。実装後の構成は architecture/ へ移す。
> **状態**: 1 段目（Mac）を実装済み（2026-11-07、ブランチ `agent-status-card`）。2 段目（iOS）は未実装。行番号は 17cb2cae 時点のもので、実装後はずれている。実装で決めた規則は各節に反映した。

パスは `macos/Packages/` からの相対。略称:

| 略称 | パス |
|---|---|
| `SF/` | `SessionFeature/Sources/SessionFeature/` |
| `CAK/` | `ClaudeAgentKit/Sources/ClaudeAgentKit/` |
| `SCK/` | `StructuredChatKit/Sources/StructuredChatKit/` |
| `CVM` | `SF/ChatSessionViewModel.swift` |

## 1. 全体像

```
CLI のイベント
  Claude: tool_use / tool_result / TodoWrite・TaskCreate・TaskUpdate / result
  Codex : itemStarted / itemCompleted / planUpdated / turn/completed
        │ NormalizedChatEvent（.itemCompleted を新設。保存しない型なので互換の心配なし）
        ▼
CVM.handle
  - 作業の item に completedAt を書く
  - タスクの変化を .taskList のスナップショットとして「追記」する（今は 1 枚を上書き）
  - ターンの終わり方を、その入力の userMessage に書く（turnEnd）
        │ [ChatItem]（会話ログ。保存はこれだけ）
        ▼
AgentStatusCardBuilder.build(items:, liveState:)   ← 純粋関数。表示のたびに組み立てる
        │ [ChatTranscriptBlock]（.statusCard を新設。保存しない）
        ▼
ChatTranscriptView → AgentStatusCardView（新規の部品。DisclosureCard は使わない）
```

カード専用の保存データは作らない。カードは会話ログから毎回組み立てるので、保存した内容と表示が食い違わない（ADR 0226）。

## 2. 保存形式の変更（`SF/ChatItem.swift`）

### 2.1 方針: 新しい case を足さない

`ChatItem` に新しい case を足すと、古い版のアプリがその会話を読んだときに `dataCorrupted` を投げる。その結果、会話全体の読み込みに失敗し、以後は保存もされなくなる（`ChatItem.swift:~268`、`CVM:1334/1409`）。そこで、既存の case に省略可能なフィールドを足す。読み込みには `decodeIfPresent` を使う。古い版は知らないキーを無視するので、会話を読める（前例: `attachments`、`ChatUserQuestion.permission`）。

### 2.2 変更点

| case | 追加するフィールド | 意味 |
|---|---|---|
| `commandExecution` | `completedAt: Date?` | 作業の結果が届いた時刻。`nil` は実行中か、この機能より前の記録 |
| `commandExecution` | `intent: String?` | エージェントが付けた短い説明（Claude の Bash の `description`）。他は `nil` |
| `fileChange` | `completedAt: Date?` | 同上 |
| `userMessage` | `turnEnd: ChatTurnEnd?` | その入力の終わり方。`ChatTurnEnd { outcome: completed / interrupted / error / superseded, at: Date }` |
| `taskList` | （フィールドは足さない） | **id をスナップショットごとに一意にする**（`task-list-<UUID>`）。上書きせず追記する |

- `superseded` は、実行中に次の入力が送られたことを表す（要件 FR-3「次の入力へ続く」）。
- `turnEnd` を `userMessage` に置く理由は 2 つある。中断は今の会話ログに何の記録も残さない（`CVM:2754`）。またカードの起点は `userMessage` なので、カードの状態と所要時間を起点の item 1 つから読める。

### 2.3 追従が必要な箇所（新フィールドを入れ忘れると更新が落ちる）

`appendOrReplace` は、変更前と変更後の item が `==` で等しければ書き換えを捨てる（`CVM:3566`）。また、モバイル向けの差分取得は `contentFields` から作るハッシュで変化を見つける。そのため、新フィールドは次の全部に入れる。

- `ChatItem.swift`: `==` / `init(from:)` / `encode(to:)` / `withTimestamp`
- `SF/TranscriptDelta.swift` の `contentFields`
- `AppBootstrap/Sources/AppBootstrap/SessionRuntimeSnapshotUpdate.swift` の `sameChatItem`（別ウィンドウ・リモートへの差分配信。入れ忘れると新フィールドだけの変化を捨てる）
- `AppBootstrap/.../ControlActionHandler.swift:~1027` のモバイル DTO（2 段目で値を載せる。1 段目は今のまま送る）

### 2.4 互換

| 読む側 \ 書いた側 | 旧版 | 新版 |
|---|---|---|
| 旧版 | — | 読める。旧版には組み立てが無いので、タスクのカードは旧版の `TaskListCell` が更新の回数だけ並ぶ（要件 AC-12 で許容。新版では `TaskListCell` を削除した） |
| 新版 | 読める。固定 id `task-list` の 1 枚は、その位置にある最後の状態のスナップショットとして扱う。所要時間は出さない（FR-22） | — |

## 3. イベントの流れの変更

### 3.1 作業の終了時刻

- **Claude**:
  - `handleUserEvent`（`CAK/ClaudeChatClient+SubAgentContent.swift:~250-290`）は、tool_result を受けると今は `.commandExecution(command: nil, outputDelta)` だけを流している。ここで、さらに `.itemCompleted(itemId:)` を流すようにする。
  - Edit・Write の結果は今 `CVM:3503` で捨てられているが、`.itemCompleted` があるので終了時刻は取れる。
  - タスク系のツール（`taskListToolUseIds`）では流さない。
- **Codex**: `ThreadEvent.itemCompleted`（`CVM:3096-3126`）の処理で、内容を書き換えるときに `completedAt` も書く。
- **CVM**: `.itemCompleted` を受けたら、同じ id の item に `completedAt = eventDate` を書く。`appendOrReplace` は元の timestamp（開始時刻）を保つので、所要時間は `completedAt - timestamp` で求まる。
- **サブエージェントの作業**: 子のツールは `ChatSubAgentModel` 側にあり、メインの会話ログには出ない。1 段目では、カードに出すのはサブエージェント 1 件を 1 行にしたもの（`subAgentMarker`）だけにし、開けないようにする（今の `SubAgentMarkerCell` も「中身は見せないので押せない」。`SF/ChatMessageCells+Structured.swift:35`）。子の作業ごとの時刻は扱わない。子の作業をタスクの下に展開するのは、要望が出たら別に足す。

### 3.2 Claude の Bash の説明

`handleToolUse`（`CAK/ClaudeChatClient+SubAgentContent.swift:132-210`）で、Bash の `input["description"]` を読み、`.commandExecution` に載せる。そのために `NormalizedChatEvent.commandExecution` に `intent: String?` を足す。Claude Code の Bash ツールの入力に `description` があることは、Claude Code のツール定義で確認した。今の Phlox は読んでいない。

### 3.3 タスクの変化を追記する

- `CVM:2695` の `.taskListUpdated` の処理を、`appendOrReplace(.taskList(id: "task-list", ...))` から、新しい id での追記に変える。
- 同じ入力の中で、直前のスナップショットと内容が同じなら追記しない。
- Claude の `TaskCreate` は、作成の結果が届いてから一覧に加わる（`resolveCreatedTaskIfNeeded`）。そのため、作成のたびに 1 件ずつ増えたスナップショットが並ぶ。

### 3.4 ターンの終わりを記録する

`.turnCompleted` / `.turnInterrupted` / `.error` / `.processExited` の処理（`CVM:2731-2780`、Codex は `:3049-3060`）で、その時点で実行中だった入力の `userMessage` に `turnEnd` を書く。どの入力かは、終わりを待っている入力（下の「書く先」）で決まる。`.processExited` は、利用者が止めた・閉じた（`isTerminating`）なら `.interrupted`、それ以外は `.error` にする。既に `turnEnd` がある入力には書かない。実行中に次の入力を送ったときは、送信の処理で、`client.turnStart` が成功してから、前の入力の `userMessage` に `turnEnd(.superseded, at: 送信時刻)` を書く（送信に失敗したら書かない）。

実装で足した規則（2026-11-07）:

- **書く先**: 「最後の `userMessage`」ではなく、終わりを待っている入力（CVM の `openInputID`）に書く。復元した古い入力は待っていないので、後から届く終了で書かれない。
- **遅れて届く終了の吸収**: `superseded` を書いた数を CVM の `pendingSupersededEnds` で数える。完了・中断・エラーが届いたとき、件数が 1 以上なら前の入力の終わりとして 1 つ減らして捨て、0 なら待っている入力に書く。`.processExited` は吸収せず、待っている入力に書く。利用者の中断（`turnInterrupt`）は件数を 0 に戻す。
- **`.error`**: 今の CVM は `.error`（起動失敗を除く）で必ず実行中の状態を終えるので、ターンの終わりとして扱う。
- **未確認**: Claude の CLI が実行中に送った入力を前のターンに合流させ、結果を 1 件しか返さない場合、Codex が実行中の `turn/start` を合流させる場合は、新しい入力の終わりが吸収されて記録が残らず、見出しは「終了」になる（実機の CLI での確認は費用がかかるため 1 段目では見送った。§9）。

### 3.5 巻き戻しでタスクの記憶を消す（既存の不具合の修正を含む）

`ClaudeChatClient.resetConversation`（`CAK/ClaudeChatClient.swift:418`）は、次の 4 つを空にしていない。

- `taskListTasks`
- `taskListToolUseIds`
- `pendingCreatedTaskTitles`
- `toolUseItemIds`

そのため巻き戻しの後、古い会話の id 宛ての `TaskUpdate` が届くと、消えたはずのタスクが一覧に戻りうる（今のコードにもある不具合）。`resetConversation` でこの 4 つを空にする。会話ログの切り詰めは今の `revert` のままでよく、切り詰めた範囲のスナップショットとカードは自然に消える。

### 3.6 Codex の計画の二重表示をやめる

Codex の計画は今、次の 2 つの経路で画面に出る（`CodexAppServerClient.swift:836-846`）。

- `codexPlanTaskState` → 末尾の `CodexSessionSurface` の「プラン」
- `.taskListUpdated` → 会話ログ

カードは後者から組み立てるので、`CodexSessionSurface` から計画の表示を外す。子エージェントのエラー表示は残す。`CodexPlanTaskState` は、実行中の状態の受け渡し（runtime snapshot、`CVM:4680/4767`）でまだ使っているので、型は残す。

## 4. カードの組み立て（`SF/AgentStatusCardBuilder.swift`、新規・純粋関数）

### 4.1 入力と出力

- **入力**: `[ChatItem]`（会話ログ）と、実行中の状態をまとめた値 `AgentStatusLiveState`。
  - `isProcessing`（= `showsProcessingIndicator`）
  - `activityState`
  - `hangAssessment`
  - `isAwaitingReply`
  - `now`
- **出力**: `[ChatTranscriptBlock]`。今の `.single` / `.commandGroup` に `.statusCard(AgentStatusCard)` を足す。
- **適用範囲**: Claude と Codex のセッションだけで使う。Cursor は今の `ChatTranscriptGrouping.blocks` のまま。

### 4.2 区切り

- 会話ログを `userMessage` で区切る。区切った 1 つを「入力の区間」と呼び、カード 1 枚に当たる。
- 区間の中に作業・タスク・サブエージェントのどれも無く、実行中でもなければ、カードは作らない（FR-2）。

### 4.3 基準のスナップショット

区間に入る直前の、最後の `.taskList` を「基準」とする。区間の中で、タイトルか状態が一度でも基準と違ったタスクだけをカードに出す（D8）。これで、前の入力で完了したまま触られていないタスクは出ない。

### 4.4 作業の振り分け（位置で決める）

区間の中の各 item について、**その item より前にある直近のスナップショット**で、進行中のタスクを数える。

| 進行中の件数 | 属する先 |
|---|---|
| ちょうど 1 件 | そのタスク |
| 0 件・2 件以上 | タスク外の作業 |

**時刻ではなく、会話ログ上の位置で決める。** 理由は次の 2 つで、時刻は所要時間にしか使わない。

- `appendOrReplace` は書き換えても開始時刻を保つ。
- `subAgentMarker` の timestamp は `.distantPast` 固定である。

古い会話（固定 id `task-list` の 1 枚だけ）のスナップショットは、表示（最後の状態）には使うが、振り分けと所要時間には使わない。最後の状態で進行中が 1 件でも、作業は全部タスク外になる（FR-22）。基準で進行中のタスクがこの入力のカードに出ないときも、その作業はタスク外にする。

### 4.5 カードの上・中・下

1. **カードの上**: 区間の先頭から、最初の作業・スナップショット・サブエージェントの直前までにある `agentMessage` と `reasoning`。
2. **カードの下**: 実行中でなければ（`turnEnd` が無い入力も含む。2026-11-07 ユーザー決定 D21）、区間の末尾から `turnCost` を除いた最後の item が `agentMessage` なら、それと `turnCost` をカードの下に出す（`.turnCompleted` は `turnEnd` より先に `turnCost` を追記するため、末尾は `turnCost` になる）。末尾が返答でなくても、末尾の `turnCost` は下に出す。最初の作業より前には遡らない。
   - 区間の先頭（最初の作業・返答より前）にある `turnCost` は、`superseded` で閉じた前の入力の使用量なので、カードの中に入れず、カードの外の上に出す。
3. **カードの中**: それ以外の全部。作業、タスクの進行中の文章と思考、回答済みの `userQuestion`、`error`。

### 4.6 タスクの所要時間

あるタスクが最初に進行中として現れたスナップショットの時刻から、最初に完了として現れたスナップショットの時刻までを所要時間とする。古い会話のスナップショットは 1 枚しかないので、所要時間は出ない。

### 3.7 タスクの道具を有効にして起動する（実画面の確認で判明。ADR 0228）

- **Claude の作成結果**: 本物の CLI は TaskCreate の結果を、イベントの `tool_use_result`（スネークケース）に載せる。`resolveCreatedTaskIfNeeded` は `toolUseResult` を読んでいたため、作成が確定せず、後の TaskUpdate も捨てられていた。`tool_use_result.task.id` を読む。Claude の stream-json のほかの読み取りは、本物のログと突き合わせて確認した（`modelUsage`・`multiSelect`・`resetsAt` などのキャメルケースは本物の CLI がそう送る）。
- **Claude の起動**: `ClaudeChatClient.spawn` が子プロセスへ渡す環境に `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` を足す（呼び出し側が同じ変数を指定していればそちらを優先）。`-p` の Claude は既定ではタスクの道具を持たない。使うようには指示しない。
- **Codex の起動**: app-server の引数（`AppEnvironment.codexAppServerProcessArguments`）に `-c tools.update_plan.enabled=true` を足す。計画は `turn/plan/updated` → `.planUpdated` → `.taskListUpdated` の既存の経路で届く想定（実画面で確認する）。

### 4.7 作業の行の文言

- **種類の判定**: 今の分類（`AgentActivityClassifier.state(forCommand:)`、`ChatCommandToolLabel.derive`）を使い、読み込み・検索・編集・書き込み・実行・その他に分ける。
- **文言**: 「対象＋動詞」にする。ファイル操作はファイル名、検索は結果の行数から「N 件」。実行は `intent` があればそれ、無ければコマンド。
- **時制**: カードが実行中で `completedAt` が無ければ「〜中」、それ以外は見本どおり体言止め（「go.mod を編集」。2026-11-07 ユーザー決定 D20）。古い会話は実行中でないので体言止めになる。
- **検索の件数**: 結果の空でない行数。ただしツールの見出し行は数えない（「No … found」は 0 件、「Found N …」は N 件）。
- **まとめ**: 連続する同じ種類（読み込み・検索・編集）は 1 行にまとめる。コマンドの実行はまとめない。
- **シェルの包み**: Codex のコマンドは `/bin/zsh -lc '…'` の包みごと届くので、行の文言では `<shell> -c|-lc` の接頭辞を外し、中身を 1 つのシェルの語として引用（連結を含む）を解いて出す（`AgentStatusCardBuilder.unwrappingShell`）。1 語として読めなければ元のまま。
- **説明の末尾**: 実行中の `intent` は、日本語の文字で終わるときだけ「中」を付ける。それ以外（英語など）は英語の表記に合わせて「…」を付ける。小さいタイルの状態の行も同じ見出しの文言を通る。
- **文字列**: xcstrings に置く。

### 4.7.1 作業の無い文章と自動の開閉

- 作業が 0 件のタスク外の行は作らない。作業を含まない文章（全タスクの完了後に書いている返答など）は `AgentStatusCard.trailing` に入れ、行の外、タスクの一覧の後ろに出す。終わった後に返答がカードの下へ移る動きは変わらない。
- 自動で開くのは、進行中のタスクと、実行中の作業を含むタスク外の行だけ。タスクがまだ 1 件も無い間は、タスク外の行も開く。前のタスク外の行をタスクのある間に開き直さない（`AgentStatusCardDisclosure.isAutoExpanded`）。

### 4.8 見出し

- **状態**: 最新のカードでは `isProcessing` を `turnEnd` より優先する（ターンが終わってもバックグラウンドタスクやサブエージェントが動く間は実行中。ADR 0064）。それ以外は `turnEnd` から決め、`turnEnd` が無ければ「終了」（印なし・所要時間なし。この機能より前の会話や、プロセスの異常終了・アプリの終了で終わった入力）にする（要件 §4.2 の表）。
- **今の作業**: 区間の最後の作業。ただし実行中（`isRunning`）のときだけ。終わっていれば出さず、今の活動状態の語（「考え中…」など）にする。
- **窓の分だけ作る**: 画面の再描画では、末尾から区間を遡り、表示する窓（single=50、grid=16 ブロック）に入る区間だけカードを作る（`AgentStatusCardBuilder.visibleSlice`）。結果は全件を作ってから窓で切った場合と一致する。入力 300 回・item 6,000 件の合成会話で 1 回 release 1.13 ms（窓 50）／0.73 ms（窓 16）、dev の窓の処理は 0.28 ms（2026-11-07 計測）。
- **残すもの**: `ChatRecap.summary`・`thinkingRecap(now:)`・`hangAssessment(now:)` は、通知（`CVM:~2480`）とグリッドの小さいタイル（`GridTileParts.swift:277/292`）が使っているので残す。

## 5. 描画

- **新しい部品**（`SF/AgentStatusCard*.swift`）:
  - `AgentStatusCardView`
  - `AgentStatusTaskRow`
  - `AgentStatusActionRow`
  - `AgentStatusHeader`
- **`DisclosureCard` は使わない**し、変えない。ADR 0144 で外したアイコンの引数を、そこへ戻さないためである（ADR 0227）。
- **作業の行を開いた中身**: 今のセル（`ChatItemView`）の中身の部品を再利用する。
- **置き場所**: `ChatTranscriptView`（`SF/ChatTranscriptView.swift:322-352` の `transcriptBlock`）に `.statusCard` の分岐を足す。Claude と Codex では、末尾の `ThinkingIndicatorCell`（`:259`）を出さない。`CompactingIndicatorCell`（`:246`）はそのまま残す。
- **時計とアニメーション**:
  - 見出しの経過時間は、今の `HangStatusTimelineSchedule` と `isTimelineVisible` で動かす。
  - 点描アニメーションは今の `ThinkingOrbView` を使う（ADR 0142・0117 の Core Animation 駆動・viewport pause をそのまま使う）。
  - 新しいタイマーや `GeometryReader` は足さない。
- **再描画の抑制**:
  - `AgentStatusCardView` は `.equatable()` で比較し、比較にクロージャを含めない。
  - 実行中でないカードは、時刻が進んでも等しいままにする（`TranscriptCellEquatableWhiteboxTests` と同じ考え方）。
- **描画量の予算**: `TranscriptRenderBudget.weight` に `.statusCard` を足す。重みは、開いている作業の行の数に比例させる。
- **開閉の状態**:
  - 自動の開閉（進行中のタスクを開く）は組み立ての結果から決める。
  - ユーザーが手で開いた・閉じたものは、ビューの状態として、カード id とタスク id の組で覚える。保存はしない。
- **圧縮中・接続待ちとの並び**: 今は圧縮中に考え中の表示を出さない（`CompactingIndicatorPresentation.shouldShowThinkingIndicator`）。カードも同じ考え方にする。圧縮中（`CompactingIndicatorCell`）と接続待ち（`ConnectingIndicatorRow`）の間は、その行を今の位置（カードの下）にそのまま出し、カードの見出しの点描アニメーションは止めて静止表示にする。動くものを 2 つ重ねないためである。
- **作業が多いタスク**: 開いたときは最新の 30 件を出し、残りは「さらに表示」にする（FR-15）。件数は今の会話ログの窓（single=50、grid=16）と合わせて、実装時に決める。
- **自動スクロール**: カードの高さが変わる。今の追従の仕組み（ADR 0037）は内容の寸法の変化で働く（ADR 0159）ので、新しい処理は要らない見込み。実装時に確かめる。

## 6. グリッド・他の画面

- **グリッドの列**: `GridChatColumn` は `ChatTranscriptView` を使うので、カードが出る（`.gridTile` では窓が 16 ブロック）。
- **小さいタイル**: `GridTileParts.swift:274-285` の「実行中」の行を、`AgentStatusHeader` の文言に置き換える。組み立てに使う関数は同じものを使う。
- **iOS（2 段目）**:
  - モバイルの DTO（`ControlActionHandler.swift:~985-1040`）に、`completedAt`・`intent`・`turnEnd`、`taskList` の構造化した中身を足す。
  - iOS 側（`ios/Packages/PhloxKit`）に、同じ組み立て規則と、カードの部品を作る。
  - 組み立て規則は Mac と iOS で共有できる場所に置くかを、2 段目の最初に決める。今は共有パッケージが無い。

## 7. テスト計画

### 7.1 新しく書くテスト

| 対象 | 種類 | 中身 |
|---|---|---|
| `AgentStatusCardBuilder` | 単体（純粋関数） | 区切り、基準、振り分け（進行中 0/1/2 件）、上・中・下の分け方、所要時間、古い会話（固定 id 1 枚）、`superseded`、文言とまとめ |
| `ChatItem` の新フィールド | 単体 | 保存して読み直すと同じ値。新フィールドの無い古い JSON を読める。新フィールドの値だけが違う 2 つが `==` で等しくならない。`contentFields` が変わる |
| CVM のイベント処理 | 単体（フェイクのクライアント） | `.itemCompleted` で `completedAt` が入る。タスクの更新が追記になる。中断・エラー・完了・実行中の再送信で `turnEnd` が入る |
| `ClaudeChatClient.resetConversation` | 単体 | 巻き戻しの後、古い id 宛ての `TaskUpdate` でタスクが戻らない |
| Claude の Bash の `description` | 単体（`ClaudeAgentKitTests`） | `intent` に載る |
| 描画 | 画面外の描画（`DesignSnapshotRenderTests`） | 見本と見比べる 5 状態（作業中・タスク登録前・タスクなし・完了・中断） |

### 7.2 期待値が変わる既存のテスト（仕様変更。ユーザー決定 D7・D8 による）

| テスト | 今の期待 | 新しい期待 |
|---|---|---|
| `SF Tests/TaskListCardTests` | 固定 id `task-list` の 1 枚を上書きする | 更新のたびに一意の id で追記する。同じ入力内で同じ内容なら追記しない |
| `AcceptanceCodexPlanTaskListTests`・`AcceptanceCodexProductionReachabilityTests` | `CodexSessionSurface` に計画が出る | 計画はカードに出て、surface には出ない（§3.6） |
| `Harness/TranscriptTypographyRenderHarness` の `cell-task-list-*` と、thinking のゴールデン画像 | 今の `TaskListCell`・`ThinkingIndicatorCell` | Claude と Codex ではカードの画像。Cursor 用の今の画像は残す |
| `DashboardFeatureTests/ChatMessageCellsRenderTests` の `ThinkingIndicatorCell` | — | Cursor 経路で引き続き使うので変えない |

`TaskListCell` は呼び出し元が無くなる（Claude・Codex はカードの中に出し、Cursor は `taskList` を出さない。古い会話もカードで組み立てる）ので、`TaskListCell` とそのゴールデン画像は削除する。

`ProcessingIndicatorTests`（`showsProcessingIndicator` の意味）・`AcceptanceQuietChatChromeTests`（`DisclosureCard` にアイコンが無い）・`ChatActivityStateTests` は変えない。カードはこれらの決まりの上に作る。

### 7.3 送信・停止・再開・復元の検証

この変更は `ChatSessionViewModel.swift` の `handle`（`.turnCompleted`・`.turnInterrupted`・`.error`）と、送信と巻き戻しを触る。そのため AGENTS.md に従い、次の 2 つを作業ブランチで実行し、結果を `.verification/<作業名>/` に残す。

- `verify-phlox` の段 1
- `verify-session-state-model`（`--input human` と `--input any`）

## 8. 実装の順番

1. **保存形式**: `ChatItem` の新フィールドと互換のテストを書く（§2）。
2. **イベント**: `.itemCompleted`、Bash の説明、タスクの追記、`turnEnd`、`resetConversation` の修正（§3.1-3.5）。
3. **組み立て**: `AgentStatusCardBuilder` を純粋関数としてテストつきで書く（§4）。
4. **見本**: Claude Design の見本を受け取り、`macos/docs/specs/ClaudeDesign/` に置く。
5. **描画**: カードの部品と `ChatTranscriptView` の分岐。Claude と Codex で `ThinkingIndicatorCell` を出さないようにする。`CodexSessionSurface` から計画を外す（§3.6・§5）。
6. **グリッド**: 小さいタイルの状態の行（§6）。
7. **検証**: 見本との見比べ、性能（9 列のグリッドで今と比べる）、§7.3 の検証。
8. **2 段目**: iOS。

## 9. 未決・リスク

- **D14 は暫定**: 見直すときの代わりの案は、補助ファイル（`.display.json` の `ChatDisplayState`）にタスクの経過と作業の時刻を置く方式である。
  - 既にターン単位の情報（`turnUsageByItemID` など）を持っている。
  - 会話ログの形式を変えずに済む。
  - その代わり、正本が 2 つになり、巻き戻しや保存の失敗で食い違いうる（ADR 0226 の「見送った案」）。
- **タスクの id**: Claude の `TodoWrite` の id は「位置＋タイトル」なので、並べ替えると別のタスクに見える。所要時間がずれることを許容する。
- **Codex のコマンド**: 説明が無い。行はコマンドそのものになり、長い。
- **結果の失敗**: 失敗したツール（`is_error`）は今の Phlox が読んでいない。カードでも、失敗した作業を区別しない。必要なら別に足す。
- **2 回以上の入力を含むターン**: `superseded` の吸収（§3.4）は、実行中に送った入力ごとに終わりが 1 回届く前提。合流して 1 回しか届かない場合は、新しい入力の見出しが「終了」になる。実機の CLI では未確認。
- **吸収の取り違え**: A→B と送り、A の完了で状態が待機に戻った後に C を送ると、B の完了が C に書かれうる。送信が失敗した後に別の入力を送ったときも同じ。CVM が前の入力の完了で待機に戻る今の挙動に由来する。
- **性能**: 窓の分だけ作っても dev より 1 回あたり約 0.5〜1 ms 多い。9 列のグリッドの実機では計測していない。
