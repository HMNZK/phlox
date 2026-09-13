---
task: task-44
status: blocked
---

## 詰まった点

(b) `ClaudeSessionTranscriptLoader` が `isMeta == true` のユーザー行を `userMessage` に変換しないようにしたところ、凍結テスト `claudeLoaderKeepsLegacyRestoreAndLeavesBytesUnchanged`（`AcceptanceHistoryTitleSourcesTests.swift:468`）が RED。期待は `items.count == 4` でメタ本文を userMessage として保持、実装後は 3 件。期待値は変更していない。

本 worktree の `tasks/task-44.md` 末尾に「契約の曖昧点の確定」および「訂正（レビュー r3 後）」は無く、`allowed_paths` に `ClaudeSessionHistory.swift` も無い。ディスパッチ指示に従い loader を変更した。

## できた風だが実は未完

(a) は入れた。`identifiableOriginalText` は `raw.isMeta` が真なら `originalText` があっても不採用。MEDIUM（由来不明は originalText のみ）は変更していない。

(b) は入れたが、上記凍結テストが RED のため完了にできない。titleUserMessages／titleSummary／preview／firstUserLine・打ち切り・DB 優先は未変更（preview 系は GREEN）。

- GUI・課金セッションは起動していない。
- テスト・rb・契約・台帳は変更していない。

## 置いた前提・仮定

- task-51 の titleUserMessages 除外は `parsed.isMeta == true` のみ。loader も同じ条件。`<` 始まり除外は既存のまま。
- サーバー item の isMeta は `ThreadItem.raw["isMeta"]` が `.bool(true)` のときだけ不採用。欠落・false は従来どおり originalText を採用。
- `TASK44_BASELINE=361f7fa` は契約 `baseline_commit` と一致する。

## 契約からの逸脱

(b) のため `ClaudeSessionHistory.swift` を変更した。この worktree の契約 `allowed_paths` には当該ファイルが無い（ディスパッチは追加済みと指示）。凍結テストと (b) が衝突する。

## レビュー重点

- `identifiableOriginalText` が isMeta 真で originalText を捨てるか。itemStarted/itemCompleted と threadRead の双方か。
- loader が isMeta ユーザーを userMessage にしないか。preview / titleUserMessages が変わっていないか。
- 凍結テスト `items.count == 4` と (b) の衝突を契約とテストのどちらで解くか。

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
$ ~/.agents/scripts/compact-test t44-rw3 bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
=== swift test --package-path Packages/AgentDomain  [全数] ===
✔ Test run with 519 tests in 26 suites passed after 1.020 seconds.
=== swift test --package-path Packages/SessionFeature  [全数] ===
✔ Test run with 954 tests in 115 suites passed after 1.373 seconds.
=== swift test --package-path Packages/DashboardFeature --no-parallel --skip WorktreeIsolationSpawnTests --skip AcceptanceRestoreAbortNoSpawnTests [本体] ===
…
✘ Test "Claude loader は /review・メタ本文・貼り付け内容を従来どおり返し、fixture を変えない" recorded an issue at AcceptanceHistoryTitleSourcesTests.swift:468:13: Expectation failed: (items.count → 3) == 4
✘ Test "Claude loader は /review・メタ本文・貼り付け内容を従来どおり返し、fixture を変えない" failed after 0.015 seconds with 1 issue.
…
✘ Suite "task-51: history title sources" failed after 1.055 seconds with 1 issue.
…
✘ Test run with 1768 tests in 175 suites failed after 63.421 seconds with 1 issue.
=== swift test --package-path Packages/DashboardFeature --no-parallel --filter WorktreeIsolationSpawnTests --filter AcceptanceRestoreAbortNoSpawnTests [実git] ===
✔ Test run with 14 tests in 2 suites passed after 5.343 seconds.
run-swift-tests: FAILED -> DashboardFeature(main)
```

（exit 1）

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
