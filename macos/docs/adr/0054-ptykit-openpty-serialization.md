---
status: active
last-verified: 2026-07-08
---

# 0054: openpty(3) 呼び出しのプロセス内直列化（並列 PTY 割当レースの根治）

> **このファイルの役割**: PTYKit の PTY 生成を mutex で直列化した決定の rationale と棄却案。
> **書かないもの**: PTYKit の現行構造（→ コード `Packages/PTYKit`）。

- **文脈**: リアーキテクチャ Run 1 のベースライン計測で、`AuditRegressionTests` の `terminateAllAndWaitEscalatesPromptlyOnCancellationInsteadOfHotSpinning()` ほかが `openPTYFailed(errno: -6)`（ENXIO）で間欠 fail（連続実行で 10 回中 5 回）。詳細ログで同一 run 内の複数テスト（`getWinsize_onClosedFD_returnsNil()` 等）が同時に同 errno で落ちており、特定テスト固有ではなく **Swift Testing の並列実行下で `openpty(3)` が同時呼び出しされたときの macOS 側 PTY 割当レース**と特定した（`pty_helpers.c:38` → `Posix.swift` の errno 伝播で顕在化）。flaky な安全網はリファクタリングキャンペーン全体の振る舞い保存証明を汚染するため Stage 0 で根治対象とした。
- **決定**: `pty_helpers.c` に `pthread_mutex_t` を追加し、**`openpty` 呼び出しのみ**をプロセス内で直列化する。`errno` は `openpty` 直後に保存し unlock 後に復元して、Swift 側 `PTYError.openPTYFailed(errno:)` の既存契約を維持する。PTY IO・child lifecycle の並行性は維持（直列化は生成時のみ）。
- **棄却案**: (a) ENXIO 時のリトライ（真因を隠蔽し flakiness が残る）、(b) テスト側の直列化・分離（本番の `PTYManager` も並行 spawn しうるため、テストだけ守っても製品コードのレースが残る）、(c) skip/タイムアウト緩和（検証意図の毀損）。
- **証拠**: 修正前 red 10 回中 5 回 → 修正後は実装者・PM・独立レビュアー2系統がそれぞれ連続 10 回全 green（31 tests）を実走確認。二段独立レビュー pass（指摘 MUST/HIGH 0）。コミット `378f963`。
