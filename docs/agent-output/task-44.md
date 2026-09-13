---
task: task-44
status: completed
---

## 詰まった点

PM 裁定により、(b) loader の `isMeta` 除外は入れない。`ClaudeSessionHistory.swift` は基準 `361f7fa` と同一へ戻した。凍結テストは変更していない。

## できた風だが実は未完

(a) は維持した。`identifiableOriginalText` は `raw.isMeta` が真なら `originalText` があっても不採用。MEDIUM（由来不明は originalText のみ）は変更していない。

(b) は撤回した。titleUserMessages／titleSummary／preview／firstUserLine・打ち切り・DB 優先は未変更。

- GUI・課金セッションは起動していない。
- テスト・rb・契約・台帳は変更していない。

## 置いた前提・仮定

- サーバー item の isMeta は `ThreadItem.raw["isMeta"]` が `.bool(true)` のときだけ不採用。欠落・false は従来どおり originalText を採用。
- `TASK44_BASELINE=361f7fa` は契約 `baseline_commit` と一致する。
- 契約の既知の限界: meta のみの履歴で再開したときの名前復元は後日対応とする。

## 契約からの逸脱

残る逸脱はない。`ClaudeSessionHistory.swift` は基準 `361f7fa` と同一。テスト・rb・契約・台帳は変更していない。

## レビュー重点

- `identifiableOriginalText` が isMeta 真で originalText を捨てるか。itemStarted/itemCompleted と threadRead の双方か。
- loader が基準どおりメタ本文を userMessage として返すか（凍結テスト `items.count == 4`）。
- preview / titleUserMessages が変わっていないか。

## 検証原文

```
$ ruby .claude/scripts/task44-wiring.rb --selftest
task44-wiring --selftest: OK
```

```
$ env TASK44_BASELINE=361f7fa ruby .claude/scripts/task44-wiring.rb
task44-wiring: OK
```

```
$ ~/.agents/scripts/compact-test t44-rw3b bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 4.752 seconds.
```

（exit 0）

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
