---
status: completed
last-verified: 2026-07-21
---

# 0011: サブエージェント最終レポートの二重表示（整形差）修正 worklog

agentic-loop（single モード・backend=external）による run 記録。実装は外部エージェント（Cursor ヘッドレス）へ委譲、
PM（Claude）が問題定義・受け入れテスト凍結・独立レビュー・統合検証・蒸留を担当。並行作業が多い状況のため
dev 起点の worktree（`Phlox-oss-worktrees/fix-subagent-dup-output`）に隔離して実施。

## 症状 / 根本原因

- 症状（ユーザー確認済み）: サブエージェント完了後、右ペイン（`SubAgentDrawerView`）に最終レポートが2回表示される。
- 根本原因: サブエージェント最終レポートは複数チャネル（inline `.subAgentActivity(.message)` / `-summary` / `-output`）で
  同一本文が届く（ADR 0025 §3）。二重表示防止の砦 `ChatSubAgentModel.appendSubAgentTranscriptItem` の dedup が
  「片方がレポート系 id かつ **trim 後の完全一致**」限定だったため、inline とレポート系が同一レポートでも
  整形（改行↔空白・連結時の区切り欠落）で byte 不一致になると dedup をすり抜けた。

## 何をしたか

| task | 内容 |
|---|---|
| task-1 | `appendSubAgentTranscriptItem` の本文一致判定を空白非依存（`whitespaceStrippedForDedup`＝空白を全除去して比較）に変更。レポート系チャネル制約は維持（ADR 0025 §7 非回帰）。表示・保存する本文は無加工。変更は `ChatSubAgentModel.swift` の8挿入3削除のみ |

## 検証

- PM 著の受け入れテスト `SubAgentReportFormattingDedupAcceptanceTests`（`newlineVsSpace` / `missingSeparator` /
  `genuinelyDifferent`）を先に追加し現行コードで red 確認（先頭2件 fail）→ 修正で green。
- `agentic-loop-verify-task.sh task-1` 権威ゲート: pass:true（scope クリーン・tests pass・report completed）。
- 独立レビュー（persona-reviewer）: pass（MUST/HIGH/MEDIUM/LOW=0）。DashboardFeature 30 tests / SessionFeature 24 tests（`--filter SubAgent`）green、既存 dedup・§7 契約は不変。

## 生成 / 更新した永続ドキュメント

- ADR: `adr/0105-subagent-report-dedup-whitespace-insensitive.md`（新規。ADR 0025 §7 の一致判定を精緻化）
- 構造: `architecture/chat-subagent-display.md` の「transcript 組立の冪等性」節を空白非依存比較へ更新（STALE 解消）
- テスト: `DashboardFeature/Tests/.../SubAgentReportFormattingDedupAcceptanceTests.swift`（契約・不変）

## 未検証 / 既知の限界

- 実セッションの生 stream-json は Phlox にログ機構が無く LIVE チャネルが永続化されないため、inline とレポート系の
  厳密な byte 差分は事後捕捉できていない。修正は「整形（空白）差」の class を対象とし、その class を受け入れテストで固定した
  （症状「完了後に最終レポートが2回」はユーザー確認済み）。非空白の実質差なら両方残す設計（過剰 dedup 回避）。
