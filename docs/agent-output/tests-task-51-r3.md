---
task: task-51
status: completed
---

# task-51 ハーネス修理 r3

decision-log 2026-09-13 の PM 承認に基づく。契約・台帳は未変更。製品差分は fileURL 再構築の撤回のみ。

## 修理内容（行と理由）

| 箇所 | 行 | 理由 |
|---|---|---|
| `ClaudeSessionHistory.swift` | `:94` `for fileURL in contents` に復帰。`listed` + `projectDir.appendingPathComponent(listed.lastPathComponent)` を削除 | 実装役の逸脱。列挙 URL をルートへ載せ直すのは材料契約外。基準の `contentsOfDirectory` 結果をそのまま使う |
| `CodexSessionHistory.swift` | `rolloutFiles` `:217` `return RolloutFile(url: url, …)` に復帰。`:217–227` 相当の symlink rebase を削除 | 同上。基準は enumerator の `url` を保持する |
| `AcceptanceHistoryTitleSourcesTests.swift` | `:99` / `:559` の `entry.fileURL == file` を `comparableFileURL` 同士の比較へ。ヘルパー `:1528–1530` | `/var` と `/private/var` で `URL ==` が落ちるコンパイル後アサーション欠陥。期待値（同一ファイル）は維持。Foundation の `resolvingSymlinksInPath()` は `/private` を剥がすため、fixture だけでなく列挙結果にも同じ `standardizedFileURL`／`resolvingSymlinksInPath()` を適用しないと一致しない |
| `task51-wiring.rb` | `strip_entry_constructors` `:934`、`claude_entries_enumeration_blob` `:954`、`frozen_listing_errors` `:965`、`check_frozen_restore` `:1068` | `rolloutFiles` 全体と Claude `entries` の列挙（entry コンストラクタを除く）・`options: [.skipsHiddenFiles]` を凍結 blob と比較。fileURL 再構築を材料配線の外で検出する |
| 同上 fixture | good/baseline の `contentsOfDirectory` `:1224` / `:1466`、`rolloutFiles` `:1397` / `:1620` | 正例が列挙・隠しファイル除外を含むようにした。検査の意味は弱めていない |
| 同上 selftest | `:2014–2054` | 列挙改変・隠しファイル除外の削除/改変・`rolloutFiles` 削除/改変の負例。既存の材料・loader・SQL 負例は維持 |

## 検証原文

```
$ ruby .claude/scripts/task51-wiring.rb --selftest
task51-wiring --selftest: OK
```

```
$ env TASK51_BASELINE=a2c5882 ruby .claude/scripts/task51-wiring.rb
task51-wiring: NG 基準時点の受け入れテストが現在と同一ではない
task51-wiring: NG 基準時点のrb 自身が現在と同一ではない
```

基準 `a2c5882` は旧凍結のため、ハーネス修理した受け入れテストと rb 自身の blob 比較だけが NG。材料配線・loader・走査上限・SQL・DB 優先・列挙処理・隠しファイル除外を含むそれ以外は GREEN（上記 2 行以外の NG なし）。

```
$ (cd macos/Packages/DashboardFeature && ~/.agents/scripts/compact-test t51-h swift test)
✔ Test run with 1761 tests in 176 suites passed after 13.128 seconds.
```

```
$ git diff --check
```

出力なし。exit 0。

=== REPORT COMPLETE ===
