---
status: active
last-verified: 2026-07-24
---

# ADR 0118: 処理中を表す表示面は生 status ではなく displayStatus を読む

> **このファイルの役割**: ADR 0064 が `showsProcessingIndicator` をチャット本体スピナーに限定導入した後も、状態を読む複数の表示面（グリッド/サイドバーのドット・アイコン、Agora 手番、チームタイムライン Thinking）が生 `SessionStatus` を直読みしていたため、背景タスク/サブエージェント継続中に「停止」と誤表示する desync が残っていた。これを表示専用の実効状態 `displayStatus` へ集約する決定。
> **書かないもの**: `showsProcessingIndicator` 自体の定義（→ ADR 0064）、interrupt/述語統一（→ ADR 0081）。

## 文脈
ADR 0064 は「主ターン完了（`turnCompleted` → `.idle`）後もバックグラウンドタスク/サブエージェントが動く間、処理中が見えない」問題を `showsProcessingIndicator`（`status == .running || !runningBackgroundTasks.isEmpty || subAgents.contains { $0.status == .running }`）で解いたが、配線先はチャット本体スピナー（`ChatTranscriptView`/`ChatSessionView`/`GridChatColumn`）のみだった。

状態を読む他の表示面は生 `SessionStatus`（主ターン完了で `.idle` に落ちる）を直読みしており、同じ desync が残存していた:
- グリッドタイルの `StatusDot` / `AgentSessionIcon`（`SessionGridView`）
- サイドバー行の `StatusDot`（`DashboardSidebarView`）
- Agora 討論の手番判定（`DashboardViewModel` の `node.status == .idle`）
- チームタイムラインの Thinking 判定（`TeamTimelineView` → `AgoraThinkingPolicy`）

ユーザーからは「何もしていないのにセッションが勝手に停止表示になるのに処理（背景 Bash 等）は続く」として観測された。`ControllableSession.status` / `SessionNode.status` は生 status を委譲するだけで処理中判定を持たず、構造的にこれらの面が `showsProcessingIndicator` をバイパスしていた。

## 決定
- 純関数 `SessionDisplayStatus.resolve(rawStatus:isProcessing:)` = `(rawStatus == .idle && isProcessing) ? .running : rawStatus` を新設。`.idle` のときだけ処理中を `.running` へ表示上昇格させ、他状態（`error`/`awaiting*`/`completed`/`starting`）は不変。
- `ControllableSession` / `SessionNode` に `isProcessing`（appServer 型 = `showsProcessingIndicator`、PTY 型 = `status == .running`）と `displayStatus`（protocol extension で resolve を既定実装）を追加。
- 上記4表示面を `displayStatus` 参照へ差し替える。
- 不変に保つもの: `SessionStatus` 型、`showsProcessingIndicator` の定義、`status` の意味と書き込み経路、DesignSystem（`StatusDot`/`AgentSessionIcon`）のシグネチャ、PTY セッションの表示挙動（`displayStatus == status`）。

## 結果
- 背景作業（バックグラウンド Bash を含むタスク・サブエージェント）継続中、これら表示面が「実行中」を保つ。凍結受け入れテスト（`resolve` の真理値表）＋白箱テスト（`ChatSessionViewModel` に背景タスクを注入し `status == .idle` でも `displayStatus == .running`）で固定。SessionFeature 335 / DashboardFeature 1454 tests 緑。
- 既知の残件（本 run スコープ外・LOW）: `DashboardViewModel.runningBreakdown` は実行中セッション数を生 `status` で数えており、同種の desync が残る。displayStatus へ寄せる追随が望ましい。
- 対象外: interrupt の非対称（SIGINT が claude プロセスの実処理を止めない可能性）、および完全なフォアグラウンド Bash 実行中の表示（`status` は `.running` のままのため本 desync とは別系統。未特定）。
