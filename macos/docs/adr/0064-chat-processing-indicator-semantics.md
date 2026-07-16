---
status: active
last-verified: 2026-07-10
---

# ADR 0064: 処理中インジケータは status を変えず表示専用述語で拡張する

> **このファイルの役割**: 「処理が続いているのにローディングが止まる」問題への修正で、`SessionStatus` の意味を変えずに `showsProcessingIndicator` を新設した決定と、interrupt/error 時のサブエージェント終端の扱い。
> **書かないもの**: スピナー描画（→ ChatTranscriptView.swift）、サブエージェント表示全般（→ architecture/chat-subagent-display.md）。

## 文脈

スピナー（ThinkingIndicatorCell）の表示条件が `status == .running` のみだったため、(a) 主ターン完了（`turnCompleted` → `.idle`）後もバックグラウンドタスク・サブエージェントが動いている間、処理中であることが見えない、(b) Codex の `threadStatusChanged` がターン進行中に非同期で idle を報告して status を格下げする競合、の2系統で「処理中なのにローディングが消える」が起きていた。

## 決定

- **`SessionStatus` の遷移は変えない**。`isReadyForInput`・ハング検知など status に依存する既存機能を壊さないため、表示専用の computed プロパティ **`ChatSessionViewModel.showsProcessingIndicator`**（`status == .running || !runningBackgroundTasks.isEmpty || サブエージェントに .running が存在`）を新設し、スピナー条件をこれに切り替える。
- **Codex ガード**: ターン進行中（`turnStartedAt != nil`）の `threadStatusChanged == .idle` は無視する。`awaitingApproval`・エラー系の遷移は従来どおり反映。
- **interrupt/error 時は実行中サブエージェントを `.failed` へ終端する**（`ChatSubAgentModel.failRunningSubAgents()`）。これが無いと running サブエージェントが残りスピナーが永久表示になる（ステージ2レビューが検出した欠陥）。`.failed` はストリップに残るため「失敗に気付ける」既存意味論を保つ。

## 棄却案

- **turnCompleted で `.idle` にしない（status 拡張）**: status の意味変更は依存機能全体（入力可否・ハング判定・サイドバー表示）に波及。棄却。
- **表示条件からサブエージェントを外す**: 症状(a)の主因（サブエージェント継続中の視覚的沈黙）を放置する対症療法。棄却。

## 結果

- 受け入れテスト AcceptanceProcessingIndicatorTests（8件）が凍結（background/subAgent × completed/interrupt/error の境界を含む）。
- 残余リスク: Codex が turnCompleted を送らず threadStatusChanged(idle) だけで終わる異常系では、ガードにより running 表示が残る（次ターン開始時クリアで bound。ステージ1レビューが指摘・受容済みトレードオフ）。
