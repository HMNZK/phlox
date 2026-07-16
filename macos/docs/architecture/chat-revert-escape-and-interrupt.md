---
status: active
last-verified: 2026-07-13
---

# チャットの中断・esc・履歴リバート機構（現行構成）

> **このファイルの役割**: チャットモードの「中断（interrupt）」「esc ホットキー」「履歴リバート」「モデル/effort の last-used 記憶」が**今どう動いているか**（Reference/Explanation）。
> **書かないもの**: なぜこの方式か（→ ADR 0031 / 0032）、作業経緯（→ delivery/0014）。

真実源: `Packages/DashboardFeature/Sources/DashboardFeature/Session/ChatSessionViewModel.swift`・`ChatSessionView.swift`・`ChatHistoryRevertPicker.swift`、各クライアント Kit。齟齬があればコードが正。

## 1. 中断（interrupt）——2026-07-05 の根治

「処理中に中止→再送信しても始まらない」バグの根本原因は **CursorChatClient.interrupt() が実行中の one-shot プロセスを止めていなかった**こと（旧 cursor-agent プロセスが同一 chatId を掴んだまま残存し、次ターンが受けられない）。現行:

- `OneShotProcessRunner.run` は**構造化 Task キャンセル**に応答する: cancellation handler がプロセスを SIGKILL し、`OneShotCancelBox`（lock）が launch とキャンセルのレースを直列化（kill 冪等・continuation 単一 resume）。
- `CursorChatClient.interrupt()` は `turnGeneration` を bump → in-flight run の Task を cancel。**世代ガード**がキャンセル済みターン由来のイベント（正常完了・error・timeout 含む）を全遮断する。`resumeSessionId` は保持（次ターンの `--resume` 継承）。
- `ChatSessionViewModel.turnInterrupt()` は**非スロー**で、client の成否に関わらずローカル状態を収束させる（失敗は transcript に `.error` で可視化）。View 側に `try?` の握りつぶしはない。2026-07-12（ADR 0081）から:
  - **ターン間でも有効**: サブエージェントのみが running（status == .idle）でも `client.interrupt()` を送り、`failRunningSubAgents()` でローカル収束する。
  - **in-flight 合流**: 実行中の interrupt があれば新規送信せず同じ Task を await（esc 連打・停止ボタン・confirmRevert の同時流入で SIGINT は1回）。
  - **世代ガード**: `turnGeneration`（論理ターンにつき1回 bump。ローカル送信で先行 bump し対応する `.turnStarted` は消費、resume 等イベント起点では `.turnStarted` で bump）が interrupt 開始時と不一致なら状態収束をスキップ＝古い interrupt の遅延完了が新ターンの `status` を潰さない。
- 注意（既知の限界）: interrupt を挟まず reentrant に turnStart した場合は旧 run をキャンセルしない（実 UI フローは必ず interrupt を通るため現状問題なし）。

## 2. esc ホットキー（ChatSessionViewModel.handleEscapeKey）

時刻注入可能な排他 4 分岐の状態機械（この順で評価）:

1. 履歴ピッカー表示中 → 閉じる（`lastEscapeAt` をリセット＝閉じ直後の誤再オープン防止）
2. 直前 esc から **1.5 秒以内（包含）** の 2 連打 → 候補（userMessage・新しい順）が空でなければピッカーを開く（status 非依存・**interrupt の完了を待たない**）
3. 単発 esc かつ**処理中（`showsProcessingIndicator`＝status ∨ backgroundTasks ∨ サブエージェント running。ADR 0081）** → `turnInterrupt()` を Task で発火（fire-and-forget）。ターン完了後にサブエージェントだけが走っている状態でも停止が効く
4. 単発 esc かつ完全 idle → 時刻記録のみ

View 層のイベント経路は**フォーカス状態で3層に排他分岐し、すべて `performChatEscape` へ収束する**: (1) composer フォーカス時は `SubmitAwareTextView.keyDown`（keyCode 53。**IME 変換中（hasMarkedText）は super へ委譲**し状態機械を走らせない・esc 消費時は super 非呼出で SwiftUI へ伝播させない）、(2) composer 非フォーカスだが SwiftUI フォーカスがある時は `.onKeyPress(.escape)`、(3) **フォーカスがどこにも無い時は `.onExitCommand`**（AppKit `cancelOperation:`。`ChatSessionView`・`GridChatColumn` 双方に付与）。層(3)はかつて**サブエージェントドロワーを閉じるだけで `turnInterrupt` を呼ばず**、「非フォーカス時に esc を押しても無音で中止できない」バグだった（Bug1）——2026-07-13 に層(3)も `performChatEscape` へ統一して根治（実機で非フォーカス時 esc 中止を確認・ADR 0083）。層(2)(3)は相互排他（`.onKeyPress(.escape)` は `.handled` を返し `cancelOperation` へ伝播しないため同一 esc で二重発火しない）。優先順は「ピッカー閉じ > サブエージェントドロワー閉じ（既存挙動維持）> 状態機械」——running 中にドロワーが開いていると esc 1 回目はドロワー閉じに消費される（裁定済みの仕様）。

## 3. 履歴リバート（revert / confirmRevert）

方式の決定は **ADR 0031**（ローカル転写切り詰め＋`resetConversation()`＋次回送信時の文脈リプレイ。上限 12,000 字・古い側切り捨て・単一適用・表示/保存は新規入力のみ）。実装の要点:

- `revert(toUserMessageID:) async -> String?`: running 中は nil（拒否）。転写切り詰め→ store は追記キューを flush してから `replaceTranscript`（同一直列チェーンで FIFO 保証）→ `resetConversation()` 1 回→ 返り値は選択メッセージ本文（composer へ復元）。
- `confirmRevert(toUserMessageID:)`: **running が残っていれば先に `turnInterrupt()` を await してから** revert（esc 1 回目の中断が未収束の窓で選択が無音 no-op になるのを防ぐ）。結果は `draftRestoration` → View が composer へ反映して `consumeDraftRestoration()`。
- クライアント別 `resetConversation()`: Cursor=`resumeSessionId=nil`／Claude=transport close→resume なし新規 spawn／Codex=**捕捉済みの thread/start 引数**（`threadStart` に加え `threadResume` でも捕捉——復元セッションで reset 不能にならない）で新 thread 開始。
- reset 後の旧 thread 遅延イベントは多層で遮断: adapter 層（`CodexStructuredAgentClient.yield` が threadId 不一致を drop）＋ VM 層（codex settings イベントの threadId 一致 guard、`turnCompleted`/`turnInterrupted` の nativeSessionId 採用条件）。

## 4. モデル/effort の last-used 記憶（LastUsedChatSettingsStore）

- `Environment/LastUsedChatSettingsStore.swift`: UserDefaults（キー `phlox.lastUsedChatSettings.<agentID>`、agentID は `AgentRef.id`）。**model と effort のみ**記憶（permission/planMode は対象外）。
- 記録: `codexSettingsDidChange` クロージャ（DashboardViewModel）で設定変更のたびに record（nil 通知では既存値を保持）。
- 適用: **新規チャットセッション作成時のみ** `startNew(persistedSettings:)` に渡す。spawn 系（claude/cursor）は `loadSpawnAgentSettings` の既存優先順位（persisted > 現在値 > 既定）、codex 系は `reapplyPersistedSettings` 経由で thread に反映（`syncSettings` がサーバー既定を先に埋めるため nil ガードでは適用されない——restore と同じパターン）。復元セッションは従来どおり per-session 永続値を使い、last-used では上書きしない。
