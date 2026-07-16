---
status: active
last-verified: 2026-07-12
---

# サブエージェント別チャット表示（現行構造）

**役割（ここにしか書かない）**: Claude Code のサブエージェント（`Task`/`Agent`）出力を「別チャット」として隔離・表示する現行の構成・データフロー・I/F。

**書かないもの**: なぜこの設計にしたか（→ `adr/0025-subagent-chat-isolation-display-and-transcript-assembly.md`、断片結合は → `adr/0077-subagent-transcript-fragment-merge.md`）。

## コンポーネント

| 層 | 型 / ファイル | 役割 |
|---|---|---|
| 正規化 | `ClaudeChatClient`（ClaudeAgentKit） | stdout stream-json → `NormalizedChatEvent`。サブエージェントを識別し `subAgent*` イベントへ隔離 |
| イベント | `NormalizedChatEvent`（StructuredChatKit） | `subAgentStarted` / `subAgentActivity(toolUseId:kind:itemId:text:)` / `subAgentOutput` / `subAgentCompleted`。itemId は emitter が message id × content 種別から導出する安定 id（`.prompt` は nil） |
| 状態 | `ChatSessionViewModel` | `subAgents: [SubAgentRef]`・`subAgentTranscripts: [String:[ChatItem]]`（ライブ）・`selectedSubAgentId`・`stripSubAgents`（表示用）・transcript ソース選択 |
| 解析 | `SubAgentTranscriptLoader.parse`（SubAgentModel.swift） | 子 output_file(JSONL) → `[ChatItem]`。tool_use+tool_result をマージ |
| 表示 | `ChatSessionView` / `SubAgentDrawerView` / `SubAgentSplitLayout` / `SubAgentMarkerCell` | ストリップ・横並び分割ペイン・インラインマーカー |

## データフロー

```
Claude Code stdout (stream-json)
  └─ ClaudeChatClient.handleAssistant/User/SystemEvent
       ├─ parent_tool_use_id ∈ subAgentToolUseIds → subAgentActivity(.prompt/.message/.reasoning/.tool)  [隔離]
       ├─ launcher tool_result (tool_use_id ∈ subAgentToolUseIds)
       │     ├─ 署名(isAsyncLaunchMetadata) → 抑制
       │     └─ else → subAgentOutput
       ├─ tool_use(Agent/Task) → subAgentStarted + subAgentActivity(.prompt from input.prompt)
       └─ task_notification(local_agent) → subAgentCompleted(summary, outputFile)
  └─ ChatSessionViewModel
       ├─ subAgents.upsert（+ 本文へ subAgentMarker を upsert）
       ├─ subAgentTranscripts[id] へ append（appendSubAgentTranscriptItem で dedup）
       └─ subAgentTranscript(for:) がライブ / parsed を選択して返す
  └─ View（ストリップ選択 or マーカークリック → selectedSubAgentId → ペイン/タイル表示）
```

## transcript の 2 ソースと選択（`subAgentTranscript(for:)`）

- **ライブ**: `subAgentTranscripts[id]`（stdout の子ターン由来。thinking テキストを保持しうる）。永続化されない（再起動で消える）。
- **parsed**: `SubAgentRef.outputFile`（子 JSONL）を `SubAgentTranscriptLoader.parse`。ファイルメタデータ（mtime/size）でキャッシュ。
- 選択規則:
  1. 片方だけ reasoning を持つ → reasoning を持つ側。
  2. それ以外 → `parsed.count >= live.count ? parsed : live`。
- **parse のマージ**: `tool_use` が作る `commandExecution` を `tool_use_id` で引き、`tool_result` は同 id の別項目にせず output をマージ（1 ツールコール=1 セル）。text/thinking の id は `message.id:type:行index:offset` で一意化。
- **制約**: 子の `thinking` が暗号化（`thinking:""`＋signature）の個体は reasoning 本文が両ソースに無く表示できない。

## ストリーミング断片の結合（`appendMergeableSubAgentActivity`・ADR 0077）

- itemId 非 nil の `.message`/`.reasoning` 活動は、stableId `"\(toolUseId)-\(kind)-\(itemId)-stream"` の item へ text を追記結合する（断片 N 件 → O(メッセージ境界数) item。CPU 暴走の根本対策）。
- 棄却は厳密な `text.isEmpty` のみ（空白のみの断片は保存）。itemId nil は従来どおり個別 item。

## transcript 組立の冪等性（`appendSubAgentTranscriptItem`）

- agentMessage は、**新規 or 既存の一方が完了レポート系 id（`-output` / `-summary`）**で同一本文なら追加しない（完了レポートの二重表示防止）。
- 完了レポート系が絡まない inline（`-message-N`）同士の同一本文は両方残す。
- id 一致は in-place 置換（ストリーム更新）。

## 表示（`ChatSessionView`）

- **ストリップ**（上部チップ）: `stripSubAgents`（`status != .completed`）を表示。単一は `SessionActivityOverlayStrip`（`.safeAreaInset(edge:.top)`）、グリッドは `GridChatColumn` の `SubAgentStrip`。完了は非表示。
- **選択時の表示**:
  - シングル: `ChatSessionView` の HStack 水平分割。左=メイン（縮む）／右=`SubAgentDrawerView`。境界は 1pt separator ＋ `ResizeGripView`（`.overlay(.topTrailing)`＋offset）。幅は `SubAgentSplitLayout.paneWidth(fraction:availableWidth:)`（既定 0.42・下限 320・上限 60%）、比率は `@AppStorage("phlox.chat.subAgentPaneFraction")` 永続。
  - グリッド: `GridChatColumn` がタイル内で `selectedSubAgentTranscript` を表示（メイン⇔サブを置換）。
- **ヘッダー整列**: メイン（`ChatSessionView.header`）とサブ（`SubAgentDrawerView.header`）を `SubAgentSplitLayout.headerHeight`(=32。2026-07-11 にグリッドのタイルヘッダと同等の縦幅へ変更・メインはアイコン右にセッション名を表示) に固定し罫線を一直線に。
- **インラインマーカー**: `upsertSubAgentMarker` が本文（メイン transcript）へ `subAgentMarker` を upsert。`SubAgentMarkerCell` クリックで `selectSubAgent`。完了サブエージェントの唯一の恒久的導線（ストリップから消えても閲覧可）。
- **描画**: `.reasoning` はテキスト空なら `EmptyView`、非空なら `ReasoningSummaryView`。
- **メインとの表示パリティ（2026-07-12）**: `SubAgentDrawerView` は表示述語 `SubAgentDrawerPresentation`（SessionFeature）経由で描画を決める——`showsThinkingIndicator(status:)`（running 中のみ `ThinkingIndicatorCell` を末尾表示）、`isRunningCommand(item:lastItemID:status:)`（末尾の `commandExecution` かつ running でツール実行中ローディング。メイン `ChatTranscriptView.isRunningCommand` と同じ結合則）、`reasoningPreview(transcript:status:)`（最新 reasoning の末尾3行。メイン `runningReasoningPreview` 相当）。transcript コンテナは ADR 0030 に従い LazyVStack ではなく VStack。

## 受け入れテスト（契約）

`Packages/ClaudeAgentKit/Tests/.../SubAgentPromptDisplayAcceptanceTests`・`SubAgentIsolationAcceptanceTests`・`AcceptanceSubAgentActivityItemIdTests`、`Packages/SessionFeature/Tests/.../AcceptanceSubAgentTranscriptMergeTests`・`AcceptanceSubAgentDrawerParityTests`・`AcceptanceSubAgentStopParityTests`、`Packages/DashboardFeature/Tests/.../SubAgentSplitLayoutAcceptanceTests`・`SubAgentTranscriptMergeAcceptanceTests`・`SubAgentReasoningPreferenceAcceptanceTests`・`SubAgentOutputDedupAcceptanceTests`・`SubAgentStripFilterAcceptanceTests`・`SubAgentTranscriptCacheAcceptanceTests`。
