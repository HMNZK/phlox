---
status: active
last-verified: 2026-07-04
---

# ADR 0015: 端末描画からの脱却 — 複数 CLI 共通の構造化チャットバックエンド

- ステータス: 採択（2026-06-19）— MVP 実装済み（Claude / Cursor）。下記「実装状況」参照
- 関連: ADR 0001（アーキテクチャ全体）, ADR 0006（マルチエージェント状態ファイル）, ADR 0009（子プロセスのライフサイクル堅牢化）, ADR 0012（ClaudeCode resumeId ネイティブ追従）

> 本 ADR は「Phlox のターミナル画面（SwiftTerm による ANSI 端末描画）を、Codex/ClaudeCode デスクトップアプリのような独自チャット形式 UI に置き換える」ことの実現可能性調査の結論を、設計判断として記録する。**MVP として Claude / Cursor を実装・検証済み**（loopflow run `045E25A7`, branch `feature/structured-chat-mvp`）。承認方式は A1（事前許可）。調査の一次資料・PoC ログは本文「裏付け」、実装の詳細は末尾「実装状況」を参照。

## コンテキスト

### 現状は2バックエンドの併存
Phlox には既に2系統のセッションバックエンドがある（`AgentDomain/SessionBackend.swift`）。

- **`.pty`**: 実 CLI を実 PTY 上で回し、`PTYManager` が**生 ANSI バイト列**を `AsyncStream<Data>` で受け、`TerminalCoordinator.feed` → `SwiftTerm.TerminalView` が ANSI を解釈して端末描画する。完了検知は別経路の **Hook**（`hook-dispatcher.sh` → `HookServer`）が `sessionStart/stop/preToolUse/...` を受けて状態遷移する。対象は Claude Code / Cursor / その他全 CLI。
- **`.appServer`**: `codex app-server`（JSON-RPC 2.0 over stdio）を `CodexAppServerKit` で喋り、**構造化イベント**を `ChatSessionViewModel` が `ChatItem`（userMessage / agentMessage / reasoning / commandExecution / fileChange(差分) / error）へ畳み込み、`ChatSessionView` がネイティブのチャット UI として描画する。承認（コマンド/ファイル変更/パーミッション）は `ChatApprovalBroker` がサーバ起点リクエストを受けモーダル UI で処理する。**Codex 専用**。

つまり要望の「端末→チャット」は **Codex については既に実装・稼働済み**。問題は「残る Claude Code / Cursor（および将来の CLI）を同じ構造化チャットへ載せられるか」に尽きる。

### 一般化を阻む現在の Codex 固定
`.appServer` は2か所で Codex に固定されている。〔2026-07 更新: 現在は Codex 専用ではない。`ControlServer.parseSpawn` は `role` 付き claudeCode spawn（アゴラ討論招集）でも `backend = .appServer` を既定とする。以下は本 ADR 決定時点の記述として残す〕
1. **生成ゲート**: `DashboardViewModel.swift:847` が `backend == .appServer && ref != .builtin(.codex)` を `unsupportedBackend` で弾く。
2. **ノードの暗黙固定**: `SessionNode.appServer(ChatSessionViewModel)` は `agentDescriptor` を `AgentRegistry.descriptor(for: .codex)` と**ハードコード**（`ControllableSession.swift:61`）。チャットノードが自分のエージェント種別を保持していない。

一方で**統合の継ぎ目は既にある**: `ControllableSession`（`id/status/sendText/readText/terminate/...`）に `SessionViewModel`(pty) と `ChatSessionViewModel`(chat) の双方が準拠し、`SessionNode` がその上の二項 enum になっている。UI モデル `ChatItem` も CLI 非依存。よって「PTY と並ぶ構造化セッション」という抽象は既に確立しており、追加コストは UI 再設計ではなく**各 CLI のストリーム→`ChatItem` 正規化アダプタ**に集約できる。

### PoC で確認した事実（実機）
3 CLI を headless 実走し、ライブの構造化イベントを採取済み（`/tmp` の使い捨てプロンプト、read-only）。

| 観測 | Claude Code (`claude -p --output-format stream-json`) | Cursor (`cursor-agent -p --output-format stream-json -f`) | Codex（既実装） |
|---|---|---|---|
| 本文 | `assistant.message.content[].text` | `assistant` | `item/agentMessage/delta` |
| 推論 | `thinking` ブロック | `thinking/delta` | `item/reasoning/*` |
| コマンド/読取 | `tool_use{name:"Bash"/"Read", input}` | `tool_call{readToolCall.args.path \| shellToolCall.args.command}` (started→completed) | `item/commandExecution/outputDelta` |
| 差分 | `tool_use{name:"Edit", input:{file_path, old_string, new_string}}` | `tool_call{editToolCall.args:{path, streamContent}}` | `fileChange{path,kind,diff}` |
| 完了 | `result/success{session_id, result, num_turns}` | `result/success` | `turn/completed` |

3 CLI とも、本文・推論・構造化ツール呼び出し・編集（差分）・完了を**非 ANSI の構造化ストリーム**で出す。観測イベントは既存 `ChatItem` の各ケースに素直に対応する。

## 決定（案）

### D1. `.appServer` を CLI 非依存の `.chat` バックエンドへ一般化する
`SessionBackend` を `.pty` / `.chat`（旧 `.appServer` を改名・一般化）の二項に整理する。`.chat` は「構造化ストリームを `ChatItem` へ正規化して描画するセッション」を意味し、特定 CLI を含意しない。`SessionNode.appServer(ChatSessionViewModel)` も `.chat(ChatSessionViewModel)` とし、**`ChatSessionViewModel` に `agentRef`/`agentDescriptor` を保持させて** `descriptor(for: .codex)` のハードコードを撤去する。

### D2. トランスポート非依存の `StructuredAgentClient` 抽象を切る
`CodexAppServerClient` を一般化し、CLI ごとのアダプタが準拠する protocol を定義する（最小契約）。
- 入力: `start()` / `initialize()` / `turnStart(input)` / `turnInterrupt()` / `resume(sessionRef)` / `updateSettings(...)` / `close()`
- 出力: 正規化イベントの `AsyncStream`（`AgentMessageDelta` / `ReasoningDelta` / `CommandExecution` / `FileChange` / `TurnStarted` / `TurnCompleted` / `Error` …＝現 `ThreadEvent` を CLI 中立化したもの）
- 承認: サーバ/プロセス起点の承認要求を `ChatApprovalBroker` へ流す共通ハンドラ

`ChatSessionViewModel`（描画・状態機械・transcript・承認集約・永続化）は**このイベント型だけに依存**し、トランスポートを知らない。

### D3. CLI ごとに3アダプタを実装する
| CLI | トランスポート | 起動 | 承認モデル |
|---|---|---|---|
| **Codex** | JSON-RPC 2.0 over stdio（`app-server`, 既実装） | `codex app-server` を spawn | per-tool `requestApproval`（最も豊か。既実装） |
| **Claude Code** | stdio 双方向 JSON（`--input-format stream-json --output-format stream-json`） | `claude` バイナリを spawn し stdin/stdout で行区切り JSON を交換（Codex の `AppServerTransport` と同形） | 第一候補は `--allowedTools`/permission-mode による事前許可。**per-tool 対話承認を CLI 単体で出せるかは要追加 PoC**（Agent SDK の `canUseTool` 相当のチャネルが CLI stream-json に存在するか） |
| **Cursor** | stdio 一方向 NDJSON（`-p --output-format stream-json`） | `cursor-agent` を `-f`（trust）付きで spawn | **事前 trust（`-f`/`--trust`）が前提**。in-stream の per-tool 承認は PoC で観測されず＝**粗い承認に留まる可能性**（要追加 PoC） |

ランタイム一貫性のため、Claude も SDK（Node/Python サイドカー）ではなく **`claude` バイナリの stdio JSON** を第一候補とする（Phlox は Swift アプリで、既に Codex バイナリを spawn して stdio で JSON-RPC を喋る実績がある＝同じプロセスモデルに収束できる）。SDK は承認チャネルが必要十分でないと判明した場合の代替に留める。

### D4. 完了検知をイベント駆動へ寄せる（チャットセッションは Hook を使わない）
`.chat` セッションの状態遷移（running/idle/awaitingApproval/completed）は構造化イベント（`turn/completed`・`result`・`thread/status`）から導く。`.appServer` は既に `hookIntegration: .none` 固定でこれを実証済み（`AgentLaunchPlanner.swift:204`）。Claude/Cursor の `.chat` 化でも Hook 経路は使わず、各ストリームの完了イベントへ統一する。**`.pty` セッションは従来どおり Hook を維持**（D6 のハイブリッド継続のため）。

### D5. 永続化・復元・resume をアダプタ責務にする
セッション復元はアダプタごとに実装する（Codex `threadResume`＋`threadRead` は既実装、Claude は `--resume <session_id>`〔ADR 0012 のネイティブ resume 系譜〕、Cursor は `--resume`）。transcript は「永続化した `ChatItem` 列（Phlox `TranscriptStore`）を復元」または「ネイティブ session を read して再構築」のいずれか。**ADR 0016 以降は全 appServer backend で前者（Phlox store）を優先し、Codex のみ store が空のとき後者（`threadRead`＋`rebuildTranscript`）へフォールバックする**（Claude/Cursor は store 復元のみ）。継続（resume）は引き続き各 CLI のネイティブ機構を使う（表示と継続の分離）。`PersistedSessionDescriptor.backend` に `.chat` と CLI 種別を記録する。

### D6. ANSI フォールバックを残す（ハイブリッド）
構造化ストリームを持たない/不安定な CLI、および ANSI でしか表れない情報（CLI 独自スピナー・カラー・予期しない TUI 出力）に備え、**`.pty` 経路と `TerminalUI` は撤去せず存続**させる。CLI 単位で `.chat` 対応可否を `AgentDescriptor` のケイパビリティとして持ち、未対応 CLI は自動的に `.pty` で起動する。`.chat` 対応 CLI でも「端末で開く」を選べる退避路を残す。

## 根拠
- **UI を作り直さない**: 観測イベントが既存 `ChatItem` に対応し、`ControllableSession`/`SessionNode` の継ぎ目が既にある。追加は正規化アダプタと一般化のみで、描画・承認・状態機械・永続化の中核は流用できる。
- **ANSI 逆解析を避ける**: 端末描画の代替として ANSI を後段でパースするのは脆く、ツール呼び出し・差分の構造が落ちる。3 CLI とも公式に非 ANSI の構造化経路を提供する以上、上流の構造化データを直接使うのが正攻法。
- **公式リッチクライアントと同形**: Codex app-server は VS Code 拡張を実際に駆動する設計で、Phlox の Codex チャットは既にこの上で動く。Claude/Cursor も同じ「バイナリを spawn し stdio で構造化 JSON を交換」モデルへ寄せると、トランスポートが一様になり保守点が減る。
- **段階導入できる**: D1〜D3 を Claude だけ先行実装しても既存（Codex chat / 全 PTY）は無改修で共存する。CLI 単位で漸進でき、リスクを区切れる。

## 影響
- 新規パッケージ: `ClaudeAgentKit`（と必要なら `CursorAgentKit`）。`CodexAppServerKit` を `StructuredAgentClient` 準拠へ一般化（後方互換維持）。
- 改修: `SessionBackend`(`.appServer`→`.chat`)、`SessionNode`/`ControllableSession`（descriptor ハードコード撤去・agentRef 保持）、`DashboardViewModel:847` ゲート緩和、`AgentLaunchPlanner`（CLI ごとの `.chat` 起動分岐）、`AgentDescriptor`（`.chat` 対応ケイパビリティ）、`PersistedSessionDescriptor`（backend/CLI 種別）。
- 非改修で存続: `TerminalUI` / `.pty` / Hook 経路（D6）。Codex チャット（既存挙動）。
- テスト: 各アダプタの正規化（モックトランスポートで stdio JSON → `ChatItem`）、承認ブローカ結線、resume、ゲート緩和。`CodexAppServerKitTests` の `MockTransport` 方式を踏襲。

## 未解決・リスク（着手前に潰す）
1. **Cursor のきめ細かい承認**（最重要）: headless stream-json で per-tool 承認要求イベントが出るか未確認。出ないなら `-f` 事前 trust の粗い承認に留まり、Codex/Claude と UX が非対称になる。`-f` 無し headless・他フラグでの承認チャネル有無を追加 PoC で確定する。
2. **Claude の承認チャネル**: CLI の `--input-format stream-json` 双方向モードで `canUseTool` 相当の per-tool 承認制御が可能か未検証。不可なら SDK サイドカー（Node/Python 依存の増加）か事前許可運用かの判断が要る。
3. **ANSI 固有表現の喪失**: 構造化ストリームに現れない描画（スピナー・色・想定外出力）の欠落が UX を損なわないか。D6 のハイブリッドで足りるか、実 runtime で確認する（ADR 0010 同様、UI/描画は実 Debug 起動で裏取りする）。
4. **experimental 依存**: Codex `app-server` は `--help` 上 `[experimental]`、一部 notification も実験的。Cursor/Claude のフラグ・スキーマも新しめでバージョン変動しうる。アダプタ層でスキーマ差を吸収し、未知イベントは `rawEventLog` へ退避する設計にする。
5. **プロセス/セッション管理**: 複数同時 `.chat` セッションの stdio プロセス多重・認証・終了処理（ADR 0009 の子プロセス堅牢化と整合）。

## 代替案
- **A: ANSI を後段パースして構造化**。新トランスポート不要だが脆弱でツール/差分構造が落ちる。却下。
- **B: CLI ごとに専用 ViewModel/UI**。`ChatItem`/`ChatSessionViewModel` を流用せず重複実装。保守負債大。却下。
- **C: Codex のみチャット、Claude/Cursor は端末のまま（現状維持）**。要望「全て置き換え」を満たさない。却下。
- **D: Claude を Agent SDK（サイドカー）で統合**。承認(`canUseTool`)は最も豊かだが Node/Python ランタイム依存が増え、Codex とトランスポートが不揃いになる。CLI stdio JSON（本決定 D3）を第一候補とし、これは承認チャネル不足が判明した場合の代替に格下げ。

## 実装状況（MVP, 2026-06-19）

loopflow run `045E25A7`（PM=ClaudeCode, backend=external）で、D1〜D6 を **Claude / Cursor 対象に MVP 実装**した（branch `feature/structured-chat-mvp`）。承認は A1（事前許可）。

### 成果物（新規/変更パッケージ）
- **`Packages/StructuredChatKit`（新規）**: CLI 非依存の基盤。`StructuredAgentClient` protocol、`NormalizedChatEvent`（agentMessageDelta / reasoningDelta / commandExecution / fileChange / turnCompleted / turnInterrupted / error / warning）、`ChatInput`、長命プロセス用 `LineDelimitedProcessTransport`（`interrupt`=SIGINT / `close`=SIGTERM）、ターン毎用 `OneShotProcessRunner`（stdout/stderr を並行 drain・行順序保証・通常終了時 FD リーク 0。タイムアウト kill 時の稀な例外は ADR 0028 参照）。
- **`Packages/CodexAppServerKit`（変更）**: 既存 `events: ThreadEvent` API を温存し、薄い adapter `CodexStructuredAgentClient` で `StructuredAgentClient` 準拠（`ThreadEvent`→`NormalizedChatEvent` 変換を内包）。
- **`Packages/ClaudeAgentKit`（新規）**: `claude -p --input-format stream-json --output-format stream-json --verbose [--permission-mode acceptEdits] [--allowedTools …] [--session-id <PhloxセッションUUID>（新規時） | --resume <UUID>（復元時）]` を**長命プロセス**で駆動。新規 start は `--session-id` で Phlox セッション UUID を claude のネイティブ session id に固定し、復元時のみ `--resume` に切り替える（両者は排他）。stdout EOF/異常終了で `.error` 終端（固着回避）。
- **`Packages/CursorAgentKit`（新規）**: `cursor-agent -p "<text>" --output-format stream-json -f [--resume]` を**ターン毎プロセス**で駆動。`system/init` の session_id を次ターンの `--resume` に継続。`turnCompleted` は `result/success` 観測時のみ。non-zero exit / stderr 非空 / parse error / no-result は `.error`。
- **`Packages/DashboardFeature`（変更）**: `ChatSessionViewModel` を `StructuredAgentClient` 抽象に依存化（Codex 固有設定は `CodexSettingsProviding` capability に分離・`agentRef` 注入）。`AgentDescriptor.supportsStructuredChat` 追加、生成ゲート緩和、`structuredClientFactory` 一般化、`DashboardView` に「New Claude (chat)」「New Cursor (chat)」メニュー追加。
- **`Packages/AgentDomain`（変更）**: `PersistedSessionDescriptor.chatNativeSessionId`（resume 用・後方互換は `codexThreadId` フォールバック）。
- **`.pty` / `PTYManager` / `TerminalUI` / Hook 経路は不可侵**（D6 ハイブリッド維持）。

### 検証
- ユニット: StructuredChatKit 8 / CodexAppServerKit 19 / ClaudeAgentKit 13 / CursorAgentKit 8 / AgentDomain 65 / DashboardFeature 706 が green（PTY/settle 系は `--no-parallel`）。
- 統合: ヘッドレス E2E 16 green、`xcodebuild`（App ターゲットの新パッケージリンク）BUILD SUCCEEDED。
- ライブ実機: 使い捨て実行ファイルで `ClaudeChatClient`/`CursorChatClient` を実 `claude`/`cursor-agent` に対し駆動し、`turnStarted`→`agentMessageDelta`→`turnCompleted(session_id)` の構造化イベント流を確認。
- 独立レビュー: Claude `persona-reviewer` + Codex の二段で、実害 4 件（warning/turnInterrupted 回帰・stdout EOF 固着・OneShot データ破損・Cursor 異常系の状態機械）を捕捉し全て根本修正のうえ pass。

### MVP スコープ外（ADR 本文の未解決として継続）
- per-tool 対話承認 UI（A1 事前許可で代替）、`.appServer`→`.chat` の enum リネーム、Claude/Cursor 設定 UI の作り込み、フル GUI 起動での目視描画確認（ライブアダプタ実機＋既存 Codex チャットの描画流用で代替）。
