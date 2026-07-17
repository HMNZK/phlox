---
status: completed
last-verified: 2026-07-17
---

# 0004: デスクトップ UI 磨き込み5件（停止ボタン・ブランチ名・ツールコール集約・Usage バー・チームビュー改名） — 作業ログ

> **このファイルの役割**: 本 run（agentic-loop / backend=external / feature/desktop-ui-polish）の作業経緯スナップショット。
> **書かないもの**: 決定の理由（→ [adr/0091](../adr/0091-codex-app-server-error-terminality.md)・[adr/0092](../adr/0092-chat-tool-call-grouping.md)）、現行仕様（→ [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md)・[architecture/claude-usage-supply.md](../architecture/claude-usage-supply.md)・[architecture/team-timeline-view.md](../architecture/team-timeline-view.md)）。

## 何をしたか（5タスク・全て done）

- **task-1 停止ボタン消失（Codex 実装・差し戻し3回→pass）**: 根本原因は `CodexAppServerClient` が app-server の `willRetry: true` エラー通知を終端 `.error` に正規化していたこと（→ ADR 0091）。`willRetry` → 非終端 `.warning`、`activeTurns` 追跡＋プロセス EOF 時の終端 error 合成を実装。3回目の差し戻しは人間承認を経て実施。最終指摘（turnStart 応答待ち中の EOF 競合）は PM が VM 側 A3 契約の証拠テスト（`PMTurnStartFailureTerminalizationTests`・green）を追加して pass 裁定（覆しルール: 独立機序の客観的証拠）。
- **task-2 ブランチ名省略（Cursor 実装・差し戻し1回→pass）**: `ComposerIndicatorMetrics.branchNameMaxWidth` を両 layout で `nil` に（100pt 固定クランプ撤廃）。50/50 分割回避は `.layoutPriority(1)`（root）／`(-1)`（label）で実現。差し戻し#1はレビュー側の誤指摘（測定で自己訂正）が原因で、PM が残った no-op modifier とテスト基準を整理した。
- **task-3 ツールコール集約（Cursor 実装・pass）**: `ChatTranscriptGrouping.blocks(from:)` による純関数集約と `CommandGroupCell`。identity 設計（グループ id = 先頭 item id・部分ブロック）は ADR 0092。
- **task-4 Usage バー統一（Cursor 実装・pass）**: ブランドアイコン置換・消費率グラデーション色（`UsageDisplay.usageColor`）・Cursor「Auto」ラベル。旧挙動を固定していたスコープ外テスト（`CursorUsageResponseTests`）は PM が契約追従として更新。
- **task-5 チームビュー改名（Cursor 実装・pass）**: `TeamViewBranding` 新設（`displayTitle == "チームビュー (Beta)"`）。ユーザー可視文字列のみ改称・型名は Agora のまま（ADR 0072 決定1 継承）。

## 検証状態

- 最終 verify（マージトレイン後・run ブランチ）: SessionFeature＋DashboardFeature スイート green（最終行: 1363 tests in 119 suites passed）、CodexAppServerKit 41件 green。xcodegen＋xcodebuild Debug ビルド exit 0。
- **未検証**: 実機（ライブアプリ）での5件の目視確認は未実施（ユーザーの起動中 Phlox の再起動が必要なため）。実 app-server のリトライイベント実観測も未実施（MEDIUM 持ち越し）。**Cursor 側の停止ボタン消失症状はコード上の機序を発見できず未解明**（one-shot 実行は中間終端イベントを発しない構造）——再発したら再調査。

## run 運用の特記事項

- 受け入れテストは run ブランチでなく**各 task ブランチへコミットして凍結**（並行 run と共有する verify.sh が他タスクの red で落ちるのを回避。decision-log 記録済みの逸脱）。
- Codex read-only レビューサンドボックスでは swift test が実行不可（`/tmp/xcrun_db-*` 書き込み拒否）→ stage2 は静的検証とし、テスト実走は stage1（Claude）＋PM ゲートで担保。
- CPU 競合下で verify が過渡的に落ちる事象が複数回（単独再実行で green）→ ゲート実行は直列化。
- `gitflow-merge.sh` は「TO が worktree にチェックアウト済み」構成で cwd 制約により実行不可 → ユーザー承認のうえ merge-tree 事前検査つき手動マージトレイン（task 1→2→3→4→5・全て clean）。
