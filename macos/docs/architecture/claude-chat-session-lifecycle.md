---
status: active
last-verified: 2026-07-13
---

# Claude チャットセッションのプロセスライフサイクル（現状仕様）

> **このファイルの役割**: `ClaudeChatClient`（ClaudeAgentKit）の spawn / respawn / self-heal / 中断後始末 / stderr 回収 / バックグラウンドタスクイベントが「今どう動いているか」。
> **書かないもの**: なぜこの設計か（→ ADR 0021 / 0022）、Codex/Cursor チャットのライフサイクル、PTY セッション。

## spawn 引数の選択（状態機械）

`claude -p --input-format stream-json --output-format stream-json --verbose [--model M] [--permission-mode P] [--effort E] [--allowedTools ...]` に加え、セッション参照は次で決まる:

| 状態 | 初回 spawn | settings dirty respawn |
|---|---|---|
| 新規セッション（会話未確立） | `--session-id <PHLOX_SESSION_ID>` | `--session-id <PHLOX_SESSION_ID>` |
| success result 受信後（会話確立） | — | `--resume <currentSessionId>` |
| `resume(sessionRef:)` 呼び出し後（復元） | `--resume <ref>` | `--resume <ref>` |

- 「会話の実在」は2状態で追跡する: `callerResumedSession`（復元 caller の主張）と「実在観測」（**`.sessionId` spawn で任意の result を受信**——中断/エラーで終わったターンでも CLI は会話ファイルを生成するため。`.resume` spawn の deferred エラーは証拠にしない。ADR 0022）。いずれか真なら `--resume`。
- 設定フラグは model / permission-mode / **effort**（低〜最大: low/medium/high/xhigh/max、UI 既定 "high"）の3値を常にフルスナップショットで置換適用する（コンポーザーのメニューは Claude セッションのみ。表示名は "Opus 4.8" 等の手動対応表）。
- **effort はモデル依存**（2026-07-04〜）: effort 非対応モデル（現状 `haiku` のみ。`ChatSessionViewModel.claudeEffortUnsupportedModelAliases` の denylist が単一真実源で、集合に無ければ対応とみなす）ではコンポーザーの effort メニューを非表示にし、`--effort` を送らない。実装は VM の1箇所——`applySpawnAgentSettings` が `claudeCode && supportsEffort(selectedModel)` でなければ effort=nil を渡すため `buildArguments`（不変）は `--effort` を付けない。モデル切替時は非対応→`selectedEffort=nil`、対応へ復帰→既定 `high` を復元し、復元経路（`loadSpawnAgentSettings`）も非対応モデルで effort を nil に矯正する。opus/sonnet/fable は従来どおり effort 対応。判定は `ClaudeChatClient` へ複製しない。
- claude CLI の制約（2.1.198 実測）: `--resume <未存在ID>` は起動直後に即死（error_during_execution・stderr `No conversation found with session ID`）。`--session-id <既存会話ID>` は `already in use` で即死（result なし）。この非対称が上表の使い分けの理由（ADR 0021）。

## resume 失敗の self-heal

1. `--resume` spawn の `error_during_execution` result は（ターンの有無を問わず）即時 `.error` にせず保留する。
2. stream 終了時に `stderrTail()` を確認し、`No conversation found with session ID` を含む場合のみ: `.error` を出さず `--session-id <ref>` で respawn。**ターン中**なら送信済み raw 1 行をそのまま再送（`.turnStarted` は重複させない）、**ターン外**（復元直後の即死）なら待機状態へ戻す。
3. stderr 不一致なら保留エラーを yield。stream が終わらない病理ケースでは `interrupt()`/`close()` が保留エラーを放出する（握りつぶしなし）。
4. heal 先は `--session-id` spawn のため heal 条件（resume spawn であること）を再び満たさず、一回性は構造的に保証される。

## 再入安全性（spawnGeneration）

`handleStreamEnded` は入口と **`await stderrTail()` の直後**の両方で `generation == spawnGeneration` を再検証する。await 中に `resume(sessionRef:)` 等の再入で respawn が起きても、旧世代の終了処理が新 transport を巻き添えにしない。

## stderr の回収（StructuredChatKit）

- `LineDelimitedTransport.stderrTail() async -> String?`（protocol extension の既定実装は nil）。
- `LineDelimitedProcessTransport` は stderr を専用キューで**連続 drain**（未 drain だと 64KiB 超で子プロセスがブロックする）し、末尾 64KiB を保持。stdout/stderr 両リーダーを同一 `DispatchGroup` に入れ、`receivedLines` の finish 後は `stderrTail()` が完全であることを保証する。
- result なしでプロセスが死んだ場合のエラー `Claude process ended before completing the current turn` に、stderr が非空ならその末尾を付加する。

## 中断（interrupt）の後始末

- 中断時にターンが開いていた場合、同一世代の次の `error_during_execution` result は「後始末」として1件だけ吸収する（次の turnStart では解除しない・世代交代で解除・新ターンの状態には触れない。ADR 0022）。
- **中断後の transport 復活（Bug2・2026-07-13）**: `claude -p` は SIGINT で終了する（`interrupt()`→`transport.interrupt()`→`process.interrupt()`）。中断でターンが閉じた後にプロセスが死ぬと `handleStreamEnded` は自己修復ブランチ（`currentTurnOpen` が既に false）を素通りして `transport=nil` に落とす。この状態で次の `turnStart` が来ると、以前は `notStarted` を throw して**「停止後に送っても処理が始まらない」無音失敗**になっていた。現行の `turnStart` は入口で `transport==nil` を検出したら `settingsRespawnSessionArgument()`（会話確立後は `--resume <currentSessionId>`）で respawn してから送信し、respawn 失敗時のみ `.error` を yield して throw する（握りつぶさない）。Cursor/Codex 経路は interrupt が transport/thread を殺さないため構造的にこの穴が無い。ADR 0083。

## バックグラウンドタスクイベント

- `system/task_started {task_id, tool_use_id, description, task_type: local_bash|local_agent}` → `.backgroundTaskStarted`、`system/task_notification {status, summary}` → `.backgroundTaskCompleted` に正規化（`task_updated` は非正規化）。実測フィクスチャ: `docs/agent-output/claude-bg-task-events-fixture.jsonl`。
- VM は実行中一覧を導出し、UI はトランスクリプト上に **overlay の実行中ストリップ**（トップ固定）を表示する。ストリップはレイアウト兄弟にしない——LazyVStack の配置キャッシュと振動し main thread が固着する（実測）。孤児タスクは terminate/復元/中断/エラー/設定 respawn（次 turnStarted）でクリアする。
- **terminate と承認待ちの解決（2026-07-08）**: `terminate()` は `ChatApprovalBroker.cancelAll()` を呼び、pending の承認 continuation を全て否認で resume する。broker は terminal 状態になり、terminate 進行中に遅れて到達した承認要求も pending に積まず即時否認で返す（continuation リークの根絶。resume-exactly-once は actor 直列化で担保）。
- **既知の未解決**: トランスクリプト複合構造（GeometryReader＋Lazy＋Markdown SelectionOverlay）に別トリガー（Esc 中断等）で発火するレイアウト非収束が残存（delivery/0005 参照・次 run 対応）。

## テスト

- 凍結受け入れテスト: `Packages/ClaudeAgentKit/Tests/ClaudeAgentKitTests/AcceptanceRespawnSelfHealTests.swift`・`Packages/StructuredChatKit/Tests/StructuredChatKitTests/AcceptanceStderrTailTests.swift`。
- 中断後の transport 復活（Bug2）: `Packages/ClaudeAgentKit/Tests/ClaudeAgentKitTests/InterruptRespawnWhiteboxTests.swift`（interrupt でストリーム終了する fake transport を使い、次 turnStart が `--resume` 保持で respawn すること・respawn 失敗時に `.error`＋`notStarted` throw することを白箱で検証）。
- 上表の全遷移と heal 一回性・再入安全性は白箱テスト込みで `swift test --package-path Packages/ClaudeAgentKit`（`ClaudeChatClientTests` / `AcceptanceRespawnSelfHealTests` 等）でカバーされる。件数は腐敗しやすいため明記せず、都度実走して確認する。
