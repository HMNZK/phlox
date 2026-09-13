---
task: task-44
status: partial

## 修理内容（行と理由）

製品コード・契約・台帳は未変更。期待値・検査の意味は弱めていない。

### AgentDomain 2 本

`AcceptanceSessionTitleStateTests.swift` / `AcceptanceSessionTitleDescriptorTests.swift` は実装 7e0dd32 に対してコンパイル可能で、変更していない。

### SessionFeature 1 本

- `AcceptanceSessionTitleLifecycleTests.swift:150` に `return` を追加。`threadResume` は代入の次に `ThreadResponse` を返す必要があり、単一文の implicit return が使えないため（期待値は不変）。

### DashboardFeature 1 本

- `AcceptanceSessionTitlePersistenceTests.swift:285,316,350` の `gate.resume()` を `await gate.resume()` へ。`TitleSpawnPIDGate` は actor で、隔離メソッドを actor 外から呼ぶには await が必要（既存 `SessionOriginWhiteboxTests` と同じ。待ちの意味は不変）。
- 同ファイル `:211` の `capturingStandardError` に `@MainActor` を付与。`@MainActor` テストから nonisolated へクロージャを送ると `#SendingRisksDataRace` でコンパイル不能になるため（stderr 観測と期待文字列は不変）。

### `.claude/scripts/task44-wiring.rb`

- `:700-730` `check_no_name_ai` を基準 blob との行多重集合差分（新規追加分）だけに変更。基準からある `SessionSpawnService` の `Process()` を誤検知しない。正規表現と NG 文言は維持。新規 `Process()` / `NSTask` / `URLSession.shared` は拒否する。
- `:722` `.md` を対象外にする。開示レポートの引用 `Process()` を製品起動と見なさない（typography 検査と同じ）。
- `:758` / `:1414-1431` 本番が `baseline_files` を渡す。`:1192-1197` に正例（基準の Process、md 除外）と負例（新規 Process、基準なし）を追加。

## テスト GREEN にならない箇所（製品。テストは未改変）

`E2EPersistenceTests.swift:296` `partialRestore_preservesStoreEntryCountWhenDestructiveSaveRunsDuringRestore` が `sessionStore.saveCount == 1` で落ちる。H5 実装は復元中削除を `completeSessionRestore()` 後へ繰り越して保存し、その後の再 `removeSession` で save が 2 回になる。契約どおりの製品挙動であり、ハーネス側で期待値を合わせない。隔離再実行でも同失敗。

凍結 4 本のうち DashboardFeature 受け入れはコンパイル到達後、上記 1 件以外はパッケージ内で通過。

## 検証原文

```
$ ruby .claude/scripts/task44-wiring.rb --selftest
task44-wiring --selftest: OK
```

```
$ env TASK44_BASELINE=d65fde1 ruby .claude/scripts/task44-wiring.rb
task44-wiring: NG 基準時点の受け入れテスト3が現在と同一ではない
task44-wiring: NG 基準時点の受け入れテスト4が現在と同一ではない
task44-wiring: NG 基準時点のrb 自身が現在と同一ではない
```

Process() 誤検知と製品配線 NG は出ない。残 NG は旧凍結 blob と今回修理した Lifecycle / Persistence / rb の不一致のみ。

```
$ ~/.agents/scripts/compact-test t44-h bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
=== swift test --package-path Packages/AgentDomain  [全数] ===
✔ Test run with 519 tests in 26 suites passed after 1.033 seconds.
=== swift test --package-path Packages/SessionFeature  [全数] ===
✔ Test run with 953 tests in 115 suites passed after 1.285 seconds.
=== swift test --package-path Packages/DashboardFeature --no-parallel --skip WorktreeIsolationSpawnTests --skip AcceptanceRestoreAbortNoSpawnTests [本体] ===
✘ Test partialRestore_preservesStoreEntryCountWhenDestructiveSaveRunsDuringRestore() recorded an issue at E2EPersistenceTests.swift:296:9: Expectation failed: await sessionStore.saveCount == 1
✘ Test run with 1723 tests in 174 suites failed after 57.110 seconds with 1 issue.
=== swift test --package-path Packages/DashboardFeature --no-parallel --filter WorktreeIsolationSpawnTests --filter AcceptanceRestoreAbortNoSpawnTests [実git] ===
✔ Test run with 14 tests in 2 suites passed after 5.230 seconds.
run-swift-tests: FAILED -> DashboardFeature(main)
```

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
