---
task: task-46
status: completed
---

# tests-task-46-r5

PM 裁定（decision-log 2026-09-13「task-46 差し戻し実装中の ESCALATION を PM 裁定」）どおり、配線検査 rb の `check_answer` だけを修理した。製品コード・凍結 Swift テスト・契約・台帳は未変更。他の `check_*` は未変更。

## 変更行と理由

- `.claude/scripts/task46-wiring.rb` `check_answer`（772〜781 行）: `typography_errors(..., "回答", require_leading: false)` をやめ、`AgentMessageBody` の `compact_reach` が `RichMarkdownView`（既存の倍率適用経路: `ChatTypography.bodyFontSize` → `TranscriptTypography`）へ委譲していることだけを見る。委譲が無ければ NG「回答が RichMarkdownView へ委譲していない」。DisclosureCard 収納禁止・Binding 依存禁止は維持。契約 172 行と SCOPE_CHECK（`agent_message_body_errors`）が宣言不変を要求するため、局所のフォント役割・倍率追随を `AgentMessageBody` に置けない。
- 同 `good_basic` の `AgentMessageBody`: 正例から未使用の `@AppStorage` / `ChatFontSettings.adjusted` / `TranscriptTypography.font(for:` を外し、委譲だけで空 NG になることを固定する（旧「回答のフォント役割が無い／倍率追随が無い」期待の更新）。
- 同 `run_selftest`: 正例「回答は RichMarkdownView 委譲で足り、局所のフォント役割・倍率追随を要求しない」、負例「AgentMessageBody から RichMarkdownView を外す」。

## 検証原文

```
$ ruby .claude/scripts/task46-wiring.rb --selftest
task46-wiring --selftest: OK
exit_code: 0

$ env TASK46_BASELINE=77c2e21 TASK46_SCOPE_CHECK=1 ruby .claude/scripts/task46-wiring.rb
task46-wiring: NG 基準時点のrb 自身が現在と同一ではない
exit_code: 1

$ git diff --check
(出力なし)
exit_code: 0
```

本番検査の NG は rb 自身が基準と同一ではない件のみ。回答・AgentMessageBody・製品配線の NG は無い。

=== REPORT COMPLETE ===
