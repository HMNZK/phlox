---
status: active
last-verified: 2026-07-04
---

# ADR 0016: 全 appServer backend で表示用 transcript を Phlox 側永続化へ統一する

- ステータス: 採択（2026-06-20）— 実装・検証済み（loopflow run `B8EE89CA`, branch `feature/chat-persist-external`）
- 関連: ADR 0015（複数 CLI 共通の構造化チャットバックエンド）, ADR 0012（ClaudeCode resumeId ネイティブ追従）

> 構造化チャット（`.appServer` backend）の「再起動後の履歴**表示**の復元」を、全 backend（Claude / Codex / Cursor）で **Phlox 側 `TranscriptStore`** に統一する。会話の「**継続**(resume)」は各 backend のネイティブ機構（Claude=`--resume`、Codex=`threadResume`、Cursor=resumeId）を維持する。**表示と継続を別経路に分離する**のが本決定の核心。

## コンテキスト

構造化チャットの履歴復元方式が backend ごとに分かれており、Claude 以外が lossy だった。

- **Claude**: Phlox 側 `FileTranscriptStore` に全項目を永続化し、復元時に store から読み戻すため再起動後も完全復元する（feature/chat-persistence の B+C、実機実証済み。これが本決定のテンプレート）。
- **Codex**: 復元が `threadRead(includeTurns:true)`+`rebuildTranscript` 依存。app-server の `threadRead` は実質 agent メッセージ中心で、再起動後に user 入力・ツールコール（commandExecution 等）が欠落する。
- **Cursor**: 再起動後に履歴が完全に消える。

`threadRead` は外部 CLI 側の挙動で Phlox から直せない。全 backend で完全復元を保証する唯一の方法は Phlox 側永続化への統一である。

### 調査で判明した事実（タスク前提の訂正を含む）

1. **書き込み側は既に backend 非依存**だった。`ChatSessionViewModel.enqueueTranscriptUpsert`/`flushTranscriptAtTurnBoundary` は `transcriptStore != nil` のときに動き、user メッセージ（`sendText`）・turn 境界の transcript 全体（`.turnCompleted`/`.turnInterrupted`/`.error`）・Codex の per-item（`.itemCompleted`）を store へ upsert する。**`transcriptStore` が注入されれば全 backend で動く**。turn 境界 flush が全文を保存する安全網になっている。
2. **注入が claudeCode 限定**だった（`DashboardViewModel.makeChatSessionViewModel`）。Codex/Cursor では store が nil で書き込み・復元とも無効化されていた。
3. **復元経路の分岐**: `codexClient`（`client as? CodexSettingsProviding`）は **`CodexStructuredAgentClient` のみが準拠**する。よって：
   - Claude **および Cursor** は `codexClient==nil` 経路を通り、既に `restoreTranscriptFromStore()` を呼んでいた（store が nil で早期 return していただけ）。
   - Codex のみが `codexClient!=nil` 経路で `threadRead`+`rebuildTranscript` に依存し、store を参照していなかった。
   - **訂正**: 当初の課題設定は「Cursor も threadRead 依存」としていたが、`CursorChatClient` は `CodexSettingsProviding` 非準拠で `resume(sessionRef:)` は resumeId を保存するだけ。Cursor が履歴を失っていたのは threadRead ではなく **store 未注入**が原因。

## 決定

### D1. transcriptStore の注入を全 appServer セッションへ一般化する
`makeChatSessionViewModel`（appServer 専用経路）で `transcriptStore` を claudeCode 限定でなく無条件に `environment.transcriptStore` を注入する。これだけで Cursor は Claude 同等に永続化+store 復元される。

### D2. Codex 復元を store 優先・threadRead フォールバックにする
`ChatSessionViewModel.restore()` の Codex 経路で、表示の復元を「**Phlox store 優先 → store が空なら従来の `threadRead`+`rebuildTranscript`（後方互換）**」にする。`restoreTranscriptFromStore()` は復元有無を `Bool` で返す。store 優先時は `threadRead` を呼ばず、status は `threadResume` の応答から設定する（thread.id も `threadResume` で取得済み）。

### D3. 表示と継続を分離したまま維持する
継続のための `threadResume`（Codex）・`client.resume()`（Claude/Cursor）は従来どおり常に呼ぶ。**真実源を二重化しない**: 表示の真実源は Phlox `TranscriptStore`、継続の真実源は各 backend のネイティブ session。

## 結果

- 3 backend すべてで再起動後に user 入力・ツールコール・agent 出力を含む完全な履歴が表示される。
- 後方互換: 本機能導入前に作られた Codex セッション（store 空）は従来どおり `threadRead` フォールバックで復元する。
- 既知ギャップ（スコープ外）: ハードクラッシュで turn 境界 flush 前に落ちた最終 turn の欠落は Claude と同じ（迷子セッションの本文復旧は対象外）。

## 検証

- 単体: `DashboardFeature` 718 / `CursorAgentKit` 9 / `CodexAppServerKit` 19 / `ClaudeAgentKit` 15 green（新規テスト: Codex store 優先・空時 threadRead フォールバック・注入の3件、既存 threadRead 復元テスト2件を維持）。
- E2E: `PHLOX_E2E=1 … --filter E2E --no-parallel` 16 green。
- App ターゲット xcodebuild リンク: BUILD SUCCEEDED。
- 二段独立レビュー（persona-reviewer + 新規 Codex）両者 pass。
- **実機（3 backend 会話→再起動の履歴表示・CPU 収束）はユーザー確認に委ねる**（コード層は上記で裏取り済み）。
