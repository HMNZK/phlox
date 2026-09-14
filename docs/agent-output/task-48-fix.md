---
task: task-48-fix
status: partial
---

## 変更内容と設計判断

`TranscriptItemPresentation.command` に実行中／出力ありの補足文字列、`error` に見出し文字列を受け取る引数を追加した。既存呼び出しは既定値で維持し、表示セルでは `UIWording` から取得した文字列をファクトリへ渡す。

`CommandExecutionCell` は `presentation.heading`／`presentation.subtitle` を `DisclosureCard` へ渡し、`ErrorMessageCell` は `presentation.heading` を `Label` へ渡す。単体・グループの出力あり文言も表示言語を渡して生成する。

## できた風だが実は未完

指定された task-40 配線検査は、task-40 基準以後の統合差分（対象外ファイルを含む）を検出して NG のまま。今回の回帰修正の範囲外であり、他タスクの製品コードや検査を変更していないため、status は `partial` とした。

## 置いた前提

`UIWording.Key` に実行中のキーはなく、task-48 契約でも既存の「実行中」は対象外とされているため、実行中ラベルは既存文字列を維持した。`TranscriptItemPresentation` の新引数は既定値を持たせ、task-46 の凍結呼び出しを変更していない。

## 検証原文

```text
$ env TASK46_BASELINE=9b93efc TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb
task46-wiring: NG SubAgentMarkerCell が基準 blob と同一ではない

$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK

$ env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb
task48-wiring: OK

$ env TASK40_BASELINE=bdbf1d9 TASK40_RB_BASELINE=9883e66 ruby .claude/scripts/task40-wiring.rb
task40-wiring: NG ReasoningSummaryView の要約が正本または委譲窓口へ到達していない
task40-wiring: NG themeCacheKey が themeID と scale で分離していない
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift の help 文字列が凍結 blob から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift の help 文字列が凍結 blob から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+TaskList.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionAccessories.swift が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift が TASK40_BASELINE から変化している

$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t48fix-sf swift test --no-parallel)
✔ Test run with 1009 tests in 119 suites passed after 13.156 seconds.

$ (cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t48fix-ds swift test)
✘ Test run with 173 tests in 31 suites failed after 0.093 seconds with 8 issues.

$ (cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t48fix-ds swift test)
✔ Test run with 173 tests in 31 suites passed after 0.090 seconds.

$ git diff --check
(出力なし、終了コード 0)
```

=== REPORT COMPLETE ===
