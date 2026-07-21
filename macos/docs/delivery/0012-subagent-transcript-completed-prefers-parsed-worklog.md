---
status: completed
last-verified: 2026-07-21
---

# 0012: 完了サブエージェント transcript の parsed 優先化 worklog

agentic-loop（N=1・backend=external）による run 記録。実装は外部エージェント（Cursor ヘッドレス）へ委譲、
PM（Claude）が問題定義・受け入れテスト凍結・独立レビュー・検証・蒸留を担当。並行 run が複数走る状況のため
dev 起点の worktree（`Phlox-oss-worktrees/fix-subagent-transcript-source`）に隔離して実施。

## 症状 / 根本原因

- 症状（ユーザー確認済み・実データ検証済み）: 完了したサブエージェントの右ペインで「ツール実行 ×62」のように
  ツールが2重表示され、ツールの合間の中間ナレーション（実 sidechain に存在）が表示されない。
- 根本原因: `ChatSubAgentModel.transcript(for:)` のソース選択タイブレークが `parsed.count >= live.count ? parsed : live`
  （項目数の多い方）。ライブは各ツールを tool_use（inline assistant）と tool_result（inline user）の両方から
  `.subAgentActivity(.tool)` として生み件数が約2倍に水増しされ、かつ stdout が中間ナレーション text を運ばない。
  一方 parsed はツールを1セルにマージし中間ナレーションを保持する。結果、2重化で膨れたライブ（ナレーション欠落）が
  richer な parsed に件数比較で不当に勝つ。ライブは非永続のため再起動後は parsed が復活する＝データ喪失ではなく
  ライブ存在中の表示欠落。

## 何をしたか

| task | 内容 |
|---|---|
| task-1 | `transcript(for:)` に「完了済み（`status == .completed`）かつ parsed が読めるなら parsed 優先」分岐を、reasoning 優先の2分岐の後・件数タイブレークの前に追加（4挿入0削除）。表示・保存本文は無加工。`.completed` のみ特別扱い（`.failed` 等は件数タイブレーク据え置き）。 |

## 検証

- PM 著の受け入れテスト `SubAgentCompletedPrefersPersistedNarrationAcceptanceTests`
  （`completedSubAgentPrefersPersistedNarrationOverDoubledLiveTools`）を先に追加し RED 確認
  （旧規則で live=commandCount 4・ナレーション欠落）→ 修正で GREEN。
- `agentic-loop-verify-task.sh task-1` 権威ゲート: pass:true（out_of_scope なし・tests pass・report completed）。
- 独立レビュー（persona-reviewer）: pass（MUST/HIGH/MEDIUM=0、LOW=1 二重ルックアップ＝非ブロッキング・未修正）。
  `swift test --filter SubAgent` 31 tests / 12 suites 全 green（新受け入れ＋回帰 `prefersLiveWhenOnlyLiveHasReasoning` 含む）。

## 生成 / 更新した永続ドキュメント

- ADR: `adr/0106-subagent-transcript-completed-prefers-parsed.md`（新規）。`adr/README.md` 索引に追加。
- 構造: `architecture/chat-subagent-display.md` の「transcript の 2 ソースと選択」節に完了→parsed 規則と理由を追記。
- テスト: `DashboardFeature/Tests/.../SubAgentCompletedPrefersPersistedNarrationAcceptanceTests.swift`（契約・不変）。

## 未検証 / 既知の限界

- ライブ stdout の生データは Phlox に永続化されず直接キャプチャ不可。「stdout が中間ナレーションを運ばない」点は
  スクショの `×62` 単一グループ＋コード（inline text は `.message` として必ず描画される）＋親 JSONL の launcher
  tool_result が最終レポートのみを含む事実から三方向で強く推定（未直接観測）。修正は完了時 parsed 採用でこの推定に
  依存せず表示を正す（parsed には中間ナレーションが実在するのを検証済み）。
- ライブのツール2重化そのものは本 run の対象外（完了時は parsed 採用で回避される。実行中の2重表示は別課題）。
- 全アプリのデバッグビルド起動での目視確認は未実施（内部の表示選択変更・UIレイアウト変更なし・実 VM 経路を
  受け入れテストが通すため不相応と判断）。
