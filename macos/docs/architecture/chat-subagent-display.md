---
status: active
last-verified: 2026-09-30
---

# サブエージェント表示（現行構造）

**役割（ここにしか書かない）**: サブエージェント（Claude の `Task`/`Agent`、Codex の子スレッド）の出力を親の会話から隔離して保持し、上部の「札の帯」に名前と状態だけを出す現行の構成・データフロー・I/F。

**右パネルは廃止済み（2026-09）**: 以前は札を押すと右側に子の中身を見せるパネル（`SubAgentDrawerView` / `SubAgentSplitLayout`、Codex は `thread/read` の 2 秒ポーリング）が開いたが、「サブエージェントが中で何をしているかは見せない」方針でコードごと削除した。札は押せず、選択状態・追加指示の入力も無い。以下の transcript 保持は、パネルのためではなくモバイル操作 API（`controlSubAgentMessages` / `messageCount`）のために残している。Codex の子の transcript は保持しない。

**書かないもの**: なぜこの設計にしたか（→ `adr/0025-subagent-chat-isolation-display-and-transcript-assembly.md`、断片結合は → `adr/0077-subagent-transcript-fragment-merge.md`）。

## コンポーネント

| 層 | 型 / ファイル | 役割 |
|---|---|---|
| 正規化 | `ClaudeChatClient`（ClaudeAgentKit） | stdout stream-json → `NormalizedChatEvent`。サブエージェントを識別し `subAgent*` イベントへ隔離 |
| イベント | `NormalizedChatEvent`（StructuredChatKit） | `subAgentStarted` / `subAgentActivity(toolUseId:kind:itemId:text:)` / `subAgentOutput` / `subAgentCompleted`。kind は `prompt`/`message`/`reasoning`/`tool`（呼び出し）/`toolResult`（結果）。itemId は text/thinking では message id × content 種別、`.tool`/`.toolResult` では**子の tool_use_id**（`.prompt` は nil） |
| 状態 | `ChatSessionViewModel` / `ChatSubAgentModel` | `subAgents: [SubAgentRef]`・`subAgentTranscripts: [String:[ChatItem]]`（ライブ）・`stripSubAgents`（札の帯用）・transcript ソース選択。Codex の子は `CodexSubAgentState`（一覧・停止・失敗/停止の記録）から `displaySubAgents` に合流 |
| 解析 | `SubAgentTranscriptLoader.parse`（SubAgentModel.swift） | 子 output_file(JSONL) → `[ChatItem]`。tool_use+tool_result をマージ |
| 表示 | `SubAgentStrip` / `SubAgentStripRow`（ChatSessionAccessories.swift）・`SubAgentMarkerCell` | 札の帯（単一・グリッド共通）・会話中のインラインマーカー（押せない） |

## データフロー

```
Claude Code stdout (stream-json)
  └─ ClaudeChatClient.handleAssistant/User/SystemEvent
       ├─ parent_tool_use_id ∈ subAgentToolUseIds → subAgentActivity(.prompt/.message/.reasoning/.tool/.toolResult)  [隔離]
       ├─ launcher tool_result (tool_use_id ∈ subAgentToolUseIds)
       │     ├─ 署名(isAsyncLaunchMetadata) → 抑制
       │     └─ else → subAgentOutput
       ├─ tool_use(Agent/Task) → subAgentStarted + subAgentActivity(.prompt from input.prompt)
       └─ task_notification(local_agent) → subAgentCompleted(summary, outputFile)
  └─ ChatSessionViewModel
       ├─ subAgents.upsert（+ 本文へ subAgentMarker を upsert）
       ├─ subAgentTranscripts[id] へ append（appendSubAgentTranscriptItem で dedup）
       └─ subAgentTranscript(for:) がライブ / parsed を選択して返す
  └─ View（`stripSubAgents` を札の帯に表示。札・マーカーは押しても何も開かない）
```

## transcript の 2 ソースと選択（`subAgentTranscript(for:)`）

- **ライブ**: `subAgentTranscripts[id]`（stdout の子ターン由来。thinking テキストを保持しうる）。永続化されない（再起動で消える）。
- **parsed**: `SubAgentRef.outputFile`（子 JSONL）を `SubAgentTranscriptLoader.parse`。ファイルメタデータ（mtime/size）でキャッシュ。
- 選択規則は **2 通り＋例外1**（ADR 0113。順序が重要）:
  1. 片方だけ reasoning を持つ → reasoning を持つ側（例外。ADR 0025）。
  2. parsed が読めれば parsed（永続が権威）。
  3. 読めなければ live（`outputFile` は完了通知でしか届かないので、実質「実行中は live」）。
- **なぜ件数タイブレークを捨てたか（ADR 0113）**: かつてライブは各ツールを tool_use（inline assistant）と tool_result（inline user）の両方から別セルとして生み、件数が約2倍に水増しされていた。そのため「件数の多い方」が信用できず、ADR 0106 が `.completed` 特例で症状を塞いでいた。ライブ側を parse と同じ「1 ツールコール=1 セル」に直した（下記）ことで、件数で権威を決める必要がなくなった。
- **parse のマージ**: `tool_use` が作る `commandExecution` を `tool_use_id` で引き、`tool_result` は同 id の別項目にせず output をマージ（1 ツールコール=1 セル）。text/thinking の id は `message.id:type:行index:offset` で一意化。
- **ライブのマージ（`appendMergeableSubAgentToolActivity`・ADR 0113）**: `.tool`/`.toolResult` は `itemId`（＝子の tool_use_id）で stableId `"\(toolUseId)-tool-\(childToolUseId)"` を作り、**呼び出し → `command` 欄 / 結果 → `output` 欄**へ 1 セルにマージする。結果が先着する順序逆転にも非依存（command nil のセルを作り、後から来た呼び出しが補う）。itemId nil の活動は従来どおり独立 item（後方互換）。
- **制約**: 子の `thinking` が暗号化（`thinking:""`＋signature）の個体は reasoning 本文が両ソースに無く表示できない。

## ストリーミング断片の結合（`appendMergeableSubAgentActivity`・ADR 0077）

- itemId 非 nil の `.message`/`.reasoning` 活動は、stableId `"\(toolUseId)-\(kind)-\(itemId)-stream"` の item へ text を追記結合する（断片 N 件 → O(メッセージ境界数) item。CPU 暴走の根本対策）。
- 棄却は厳密な `text.isEmpty` のみ（空白のみの断片は保存）。itemId nil は従来どおり個別 item。

## transcript 組立の冪等性（`appendSubAgentTranscriptItem`）

- agentMessage は、**新規 or 既存の一方が完了レポート系 id（`-output` / `-summary`）**で本文が**空白非依存で一致**（スペース・タブ・改行を全て除去して比較＝`whitespaceStrippedForDedup`）なら追加しない（完了レポートの二重表示防止）。inline 最終テキストとレポート系は同一レポートでも整形（改行↔空白・連結時の区切り欠落）が異なりやすく、完全一致では二重表示が漏れるため（ADR 0105）。比較は dedup 専用で、**表示・保存する本文は無加工**。
- 完了レポート系が絡まない inline（`-message-N`）同士の同一本文は両方残す。
- id 一致は in-place 置換（ストリーム更新）。

## 札の帯（`SubAgentStrip`）

- **表示**: `stripSubAgents` を帯に出す。単一は `SessionActivityOverlayStrip`（`.safeAreaInset(edge:.top)`）、グリッドは `GridChatColumn` の `SubAgentStrip`。子がいなければ帯ごと出ない。先頭の「メイン」の札は見た目だけで押せない。
- **残る / 消える**: 帯に出るのは実行中と失敗だけ（`stripSubAgents`・`CodexSubAgentPresentation.isVisibleInStrip`）。完了と、ユーザーが止めて**停止が確認できた**札（`SubAgentStatus.stopped`）は帯から消える。失敗は ✕ で閉じるまで残る。停止を要求してから確認が来るまでの「停止中」は実行中の札のまま（ボタンなし）。
- **札の中身**: 名前＋状態アイコンだけ。アイコンは純関数 `SubAgentChipPresentation.statusIcon(for:)` が決める——実行中＝ローディング（回転マーク）、失敗＝失敗マーク、それ以外（完了・停止）はアイコンなしで名前のみ。
- **ホバー操作**（純関数 `SubAgentChipPresentation.control`）: 実行中で止められる札（Codex の子、`stop_task` の宛先が分かった Claude の子）は停止ボタン（■）。実行中で止められない札（宛先が未確定・停止中・turn 不明・stale）は何も出さない（✕ で札だけ消して子が走り続けるのを防ぐ）。実行中でない札（失敗・停止・完了）は ✕（`dismissSubAgent`）。VoiceOver には同じ判定でアクションを出す。停止ボタンは `ChatSessionViewModel.stopSubAgent(displayID:)`、状態は `subAgentStopState(forDisplayID:)` で Codex・Claude 共通。
- **閉じた札は sticky**: 閉じた id は後着イベントで復活しない。`subAgents` 本体・インラインマーカーは残す。永続化はしない。

## 個別停止

- **Codex**: `turn/interrupt`。確認は対応する interrupted 完了（`.stopping → .stopped`）。
- **Claude**: stream-json の `control_request`（`subtype: "stop_task"`, `task_id`）。`task_started` で `tool_use_id → task_id` を覚え、その時点で `NormalizedChatEvent.subAgentStopAvailable` を流して札が止められるようになる（`ClaudeChatClient+StopTask.swift`、プロトコル `SubAgentStopping`）。実測の応答順は `system/task_updated` → `system/task_notification`（`status: "stopped"`）→ `control_response`（success）。**停止の確認は task_notification**（`subAgentCompleted(status:"stopped")` → `.stopped`）で取る。親は「ユーザーが続行を望まない」という tool_result を受けてターンを数秒で終える。この tool_result は必ず届くので、クライアントは停止確定した子（`stoppedSubAgentToolUseIds`）のものを捨て（出力にも完了・失敗にもしない）、`ChatSubAgentModel.completeSubAgent` も `.stopped` の子を終端として後着の完了・失敗を無視する（二重に守る）。
- **失敗時の復帰**: `control_response` が success 以外なら `subAgentStopFailed`、確認が 15 秒（`ChatSessionViewModel.subAgentStopTimeout`）来なければタイムアウトで、停止中を解除して実行中のまま再び押せる状態に戻す（Codex・Claude 共通のタイマー）。失敗イベントは試行番号（`attempt`。`ChatSubAgentModel.beginStop` が振り、`stopSubAgent(toolUseId:attempt:)` 経由で返る）を運び、今の試行のものだけ反映する（タイムアウト後の再試行で、1 回目への遅れた応答が 2 回目を解除しない）。プロセスの再起動・終了・停止では、`task_id` の対応と未応答の要求を捨て、未応答の要求は失敗として通知する（`releaseStopTasks`）。
- **状態の写像**: Codex の `interrupted` と Claude の `stopped` は `SubAgentStatus.stopped`。会話マーカーは「停止」（en: Stopped、キー `subagent.status.stopped`）。モバイル向けのワイヤ契約は 3 値固定のため `ControlActionHandler.wireStatus` は `.stopped` を `"completed"` で送る。

## 札の名前の出所

札の名前は**親が付けた名前**を使う。
- **Codex**: 子スレッドの `source.subAgent.thread_spawn.agent_path` の末尾（親が spawn 時に付けたタスク名。`_` は空白に）を最優先（`CodexSubAgentPresentation.purpose(for:)`）。取れない旧 spawn 方式・末尾が `root` のときだけ、子の最初の usermessage → thread.name → preview の順にフォールバック。一度得たタスク名は、後続の read/refresh が agent_path を省略しても失わない（`CodexChildThread.taskName` / `keepingTaskName`）。
- **Claude**: `Task`/`Agent` ツール入力の `description`。`task_started` の description が先に届いても、完了通知の後にツール入力が届いても、親のツール入力が名前になる（`ClaudeChatClient.yieldSubAgentStartedIfNeeded` が出所の優先度で流し直し、`ChatSubAgentModel.markStarted` が状態を巻き戻さず名前だけ更新）。ツール入力に description が無いときにツール入力の JSON を名前にはしない。

## Codex の子の状態（`CodexSubAgentState`）

- read/refresh の失敗（stale）は「確認できなかった」だけで、実行中の子を失敗にも完了にもしない（停止操作だけ失効）。失敗・完了になるのは Codex が報告したとき（失敗系 status・`turnCompleted`・notLoaded/idle 等の refresh）だけ。
- 遅れて届く refresh / read は turn を照合できないので、終わったと分かっている子（完了して消えた札・止めた札・失敗済み）を失敗 status で書き換えない。
- **子の状態を決めるもの**: 一覧の refresh（`thread/list` と必要時の `thread/read`）と、停止要求に対応する interrupted 完了だけ。app-server クライアント（`CodexAppServerClient.yield`）が親と異なるスレッドの通知を遮断している（reset 後の古いスレッドのイベントを防ぐ設計）ため、子の `turnStarted` や、停止以外の子の `turnCompleted` は ViewModel に届かない。
- **既知の制限**: 失敗した子が、refresh の間隔より短い新しい turn で成功した場合、refresh が実行中の状態を一度も観測できず、失敗札は ✕ で消すまで残る。
- **停止要求中の規則**: read 失敗（stale）は何も変えない（停止待ち・status を保つ。確認は interrupted の実報告だけ）。interrupted 以外の実報告（自然完了・失敗、refresh の completed）が届いたら「止めた」印を外し、届いた報告のとおりに扱う（自然完了は完了、失敗は失敗）。
- 停止要求中に一覧が失敗（systemError 等）を報告したら、停止待ちを解除して失敗として反映する（規則 B は、終わったと分かっている子＝停止確定・完了・失敗済みにだけ適用）。停止要求中に一覧が idle / notLoaded を返したら停止確定とみなす（完了か停止かは区別できないが、どちらでも札は消え、違いは会話カードの「停止」と「完了」の表記だけ。この判断は意図して残している）。
- 停止記録（`StickyTerminal.isUserStop`）は、札の表示可否には使わない。停止確定後の refresh が status を `completed` に戻さない（マーカーの「停止」を保つ）ためと、遅れた失敗 refresh で書き換えない（上の規則）ために残す。停止記録・dismiss は完了通知・refresh・stale の到着順に依存しない。

## インラインマーカー

`upsertSubAgentMarker` が本文（メイン transcript）へ `subAgentMarker` を upsert する。`SubAgentMarkerCell` は名前・種類・状態を出すだけで押せない。

## 受け入れテスト（契約）

`Packages/ClaudeAgentKit/Tests/.../SubAgentNameArrivalOrderTests`・`SubAgentStopTaskTests`・`SubAgentPromptDisplayAcceptanceTests`・`SubAgentIsolationAcceptanceTests`・`SubAgentActivityItemIdTests`、`Packages/SessionFeature/Tests/.../SubAgentTranscriptMergeTests`・`SubAgentStopTests`・`CodexSubAgentNamePriorityTests`・`CodexSubAgentStripVisibilityTests`・`CodexSubAgentLossyRefreshPropertyTests`・`SubAgentDismissWhiteboxTests`・`ClaudeSubAgentStopViewModelTests`、`Packages/DashboardFeature/Tests/.../SubAgentTranscriptMergeAcceptanceTests`・`SubAgentReasoningPreferenceAcceptanceTests`・`SubAgentOutputDedupAcceptanceTests`・`SubAgentStripFilterAcceptanceTests`・`SubAgentDismissAcceptanceTests`・`SubAgentTranscriptCacheAcceptanceTests`・`SubAgentTranscriptSourceRuleAcceptanceTests`、`Packages/ClaudeAgentKit/Tests/.../AcceptanceSubAgentToolIdentityTests`、`Packages/SessionFeature/Tests/.../AcceptanceSubAgentLiveToolMergeTests`。
