---
task: task-44
status: partial

## 詰まった点

製品実装は allowed_paths 内で入れた。受け入れテストと rb の GREEN は、凍結成果物側の欠陥で止まっている。rb は直していない。テストも直していない。

1. `.claude/scripts/task44-wiring.rb` の恒久検査 `check_no_name_ai` が、許可パス内の任意の `Process(` を「名前目的のプロセス起動」として拒否する。`SessionSpawnService.swift:372` の `let process = Process()` は worktree 隔離の `/usr/bin/git` 起動であり、基準 `d65fde1` から存在する。名前導出・AI 呼び出しではない。契約どおりの実装でも rb が NG になる。

2. 凍結受け入れテストがコンパイルできない。実装役はテスト改変禁止のため手を入れていない。
   - `AcceptanceSessionTitleLifecycleTests.swift:150` `threadResume` が `return` なし（コンパイラが last expression の return を提案）。
   - `AcceptanceSessionTitlePersistenceTests.swift:285/316/350` が actor `TitleSpawnPIDGate.resume()` を `await` なしで呼ぶ。

## できた風だが実は未完

AgentDomain の SessionTitleState / descriptor 受け入れは GREEN。SessionFeature / DashboardFeature の凍結テストは上記コンパイルエラーで実行に到達しない。rb 恒久検査は Process 誤検知で NG。GUI・課金セッションは起動していない（契約どおり未実施）。

## 置いた前提

- task-41 の `SessionTitleDeriver.derive(from:)` を複製せず使う。
- サーバー履歴の由来識別は `ThreadItem.raw["originalText"]` の有無だけ。本文の見た目では推測しない。
- ローカル確定本文は `pendingInput + text` を ID マップに残し、同一 ID のサーバー補足より優先する。
- derived/manual では `InputHistoryPolicy.entries` / 導出の前に `source == .flower` で return する。
- 復元中の明示削除は `SessionPersistenceCoordinator` で件数減少抑止を維持し、`completeSessionRestore()` 後へ繰り越す。PID 書き戻しは現存 descriptor に `updating(pid:)` するだけで upsert しない。
- 花名の通常 `name` 代入はしない。生成・復元・復元失敗は `titleState:` で渡す。

## 契約からの逸脱

製品契約の公開 API・四フィールド保存・H5 繰り越しは実装した。合格ライン（凍結テスト全 GREEN、rb 恒久検査 GREEN）は凍結成果物の欠陥で満たせていない。rb・テストは改変していない。

## レビュー重点

- initializer 正規化と旧 JSON legacy（欠落/null source は手動、花名・導出全文を捨てる）。
- 補足付きサーバー本文を混入させていないか。早期ガードが抽出より前か。
- 初回保存が live `titleState` を使うか。PID が古いスナップショット全体を書いていないか。削除済み ID を再作成しないか。
- H5: 復元中削除が要求時点では残し、復元終了後に消えるか。
- task-45 向け `titleState` 読み取りが両 VM / SessionNode にあるか。表示責務を先取りしていないか。

## 検証原文

```
$ ~/.agents/scripts/compact-test t44-selftest ruby .claude/scripts/task44-wiring.rb --selftest
t44-selftest: OK（要約未対応）
```

```
$ ~/.agents/scripts/compact-test t44-rb env TASK44_BASELINE=d65fde1 ruby .claude/scripts/task44-wiring.rb
task44-wiring: NG macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift に名前目的のプロセス起動がある
```

根拠: 基準 blob にも同じ行がある。

```
$ git show d65fde1:macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift | rg -n "Process\\("
372:        let process = Process()
```

```
$ ~/.agents/scripts/compact-test t44-packages bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
=== swift test --package-path Packages/AgentDomain  [全数] ===
✔ Test run with 519 tests in 26 suites passed after 1.038 seconds.
=== swift test --package-path Packages/SessionFeature  [全数] ===
/private/tmp/ui-ux-wt-44/macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift:150:9: error: missing return in instance method expected to return 'ThreadResponse'
148 |     func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
149 |         liveThreadID = params.threadId
150 |         try TitleLifecycleJSON.threadResponse(id: params.threadId)
    |         |- error: missing return in instance method expected to return 'ThreadResponse'
    |         `- note: did you mean to return the last expression?
=== swift test --package-path Packages/DashboardFeature --no-parallel ...
/private/tmp/ui-ux-wt-44/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift:285:14: error: actor-isolated instance method 'resume()' cannot be called from outside of the actor
283 |         let flowerBefore = dashboard.sessionNode(id: id)?.titleState.flowerName
284 |         dashboard.renameSession(id, to: "通知を修正")
285 |         gate.resume()
    |              `- error: actor-isolated instance method 'resume()' cannot be called from outside of the actor
run-swift-tests: FAILED -> SessionFeature DashboardFeature(main) DashboardFeature(git)
```

指定の `(cd macos/Packages/AgentDomain SessionFeature DashboardFeature && ...)` は `cd` の引数が複数のため実行不能。上記 `run-swift-tests.sh` で代替した。

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
