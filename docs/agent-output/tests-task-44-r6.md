---
task: task-44
status: completed
---

# tests-task-44-r6

PM 承認（decision-log 2026-09-13「task-44 レビュー r1 HIGH」）どおり、凍結受け入れテストへ被覆 1 件を追加した。製品コード・契約・rb・台帳・他テストは未変更。期待値は契約（経路別の本文由来判定・ローカル履歴復元）から固定し、現行実装には合わせていない。

対象: `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift`

## 追加ケースの行と根拠

- `:630-668` `ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま`
  - 手順: ローカル `/review` 送信 → `yieldUserItem` + `unidentifiedSupplementJSON`（既存の `.itemStarted` / `.itemCompleted` 注入）で「`/review\nログイン画面を修正`」を受信 → 受信直後は `source == .flower` → `vm.transcript`（ChatItem 列）を `TitleLifecycleTranscriptStore` に載せ、公開 `restore(...)` で新しい VM を作る → 復元後も flower `Rose` のまま（derived にしない）。
  - 契約: 「チャット本文の候補採用」の経路別表。ローカルのスラッシュコマンド等に対するサーバー補足本文はタイトル材料にしない。ローカル履歴復元は「保存された元本文と確認できる項目」だけ採用し、由来不明の項目を元本文扱いしない。すべて識別不能なら flower。成功基準 2 の独立ケース「ローカル `/review` の送信文字列に `\nログイン画面を修正` という補足を付け、サーバー開始・完了イベントで返しても flower `Rose` のまま」を、保存・復元後にも固定する。
  - レビュー原文の欠陥: `chatItem(from:)` が `originalText` 由来を保持せず、`itemCompleted` の ChatItem を保存する。復元側 `adoptTitleFromLocalTranscript` は `InputHistoryPolicy.entries` の本文をそのまま `receivingUserMessage` へ渡すため、受信直後は flower でも復元後は補足の `ログイン画面を修正` から derived になる。

## 検証原文

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t44-tadd swift test --no-parallel --filter AcceptanceSessionTitleLifecycleTests)
[0/1] Planning build
[1/1] Compiling plugin GenerateManual
[2/2] Compiling plugin GenerateDoccReference
Building for debugging...
[2/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling SessionFeatureTests AcceptanceSessionTitleLifecycleTests.swift
[6/7] Emitting module SessionFeatureTests
[6/8] Write Objects.LinkFileList
[7/8] Linking SessionFeaturePackageTests
Build complete! (12.42s)
Test Suite 'Selected tests' started at 2026-09-13 18:53:04.147.
Test Suite 'SessionFeaturePackageTests.xctest' started at 2026-09-13 18:53:04.148.
Test Suite 'SessionFeaturePackageTests.xctest' passed at 2026-09-13 18:53:04.148.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-13 18:53:04.148.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "task-44: session title lifecycle" started.
◇ Test 公開窓口titleStateとdisplayNameのfallbackはshortID() started.
✔ Test 公開窓口titleStateとdisplayNameのfallbackはshortID() passed after 0.003 seconds.
◇ Test name代入はrenamedによる手動化であり花名をflowerに戻さない() started.
✔ Test name代入はrenamedによる手動化であり花名をflowerに戻さない() passed after 0.001 seconds.
◇ Test 未確定入力submit_falseではflowerを維持する() started.
✔ Test 未確定入力submit_falseではflowerを維持する() passed after 0.001 seconds.
◇ Test 添付のみではflowerを維持する() started.
✔ Test 添付のみではflowerを維持する() passed after 0.001 seconds.
◇ Test 適格本文でも送信前ガードで拒否されればflowerのまま本文は確定しない() started.
✔ Test 適格本文でも送信前ガードで拒否されればflowerのまま本文は確定しない() passed after 0.001 seconds.
◇ Test ローカル確定はpendingInputとtextの元本文から導出する() started.
✔ Test ローカル確定はpendingInputとtextの元本文から導出する() passed after 0.001 seconds.
◇ Test ローカル確定後の通信失敗でも導出名を保持し成功状態へは遷移しない() started.
✔ Test ローカル確定後の通信失敗でも導出名を保持し成功状態へは遷移しない() passed after 0.001 seconds.
◇ Test follow_upはメインtranscriptの元本文だけを使う() started.
✔ Test follow_upはメインtranscriptの元本文だけを使う() passed after 0.001 seconds.
◇ Test assistant_tool_error_質問回答_別transcriptからは導出しない() started.
✔ Test assistant_tool_error_質問回答_別transcriptからは導出しない() passed after 0.013 seconds.
◇ Test 質問回答の入力はタイトル候補にしない() started.
✔ Test 質問回答の入力はタイトル候補にしない() passed after 0.013 seconds.
◇ Test ローカル_review_の補足付き送信文字列をitemCompletedで返してもflowerのまま() started.
✔ Test ローカル_review_の補足付き送信文字列をitemCompletedで返してもflowerのまま() passed after 0.013 seconds.
◇ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() started.
✘ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:380:5: Expectation failed: (state.name → "ログイン画面を修正") == (name → "Rose")
↳ restore from saved ChatItems name
✘ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:381:5: Expectation failed: (state.source → .derived) == (source → .flower)
↳ restore from saved ChatItems source
✘ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:383:5: Expectation failed: (state.fullDerivedTitle → "ログイン画面を修正") == (fullDerivedTitle → nil)
↳ restore from saved ChatItems fullDerivedTitle
✘ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() failed after 0.014 seconds with 3 issues.
◇ Test ローカル本文と対応付くitemCompletedはローカル元本文を使い補足で先に確定しない() started.
✔ Test ローカル本文と対応付くitemCompletedはローカル元本文を使い補足で先に確定しない() passed after 0.013 seconds.
◇ Test 元本文_review_と補足を識別できる場合も補足だけを候補にしない() started.
✔ Test 元本文_review_と補足を識別できる場合も補足だけを候補にしない() passed after 0.001 seconds.
◇ Test 確定後の置換と再読込と巻き戻しは名前を変更しない() started.
✔ Test 確定後の置換と再読込と巻き戻しは名前を変更しない() passed after 0.013 seconds.
◇ Test 復元待機中のrenameは適格履歴の解放後も手動名を保持する() started.
✔ Test 復元待機中のrenameは適格履歴の解放後も手動名を保持する() passed after 0.001 seconds.
◇ Test 復元待機中のderivedは適格履歴の解放後も導出名を保持する() started.
✔ Test 復元待機中のderivedは適格履歴の解放後も導出名を保持する() passed after 0.001 seconds.
◇ Test 状態復元_flower_derived_manual_空名を保持する() started.
✔ Test 状態復元_flower_derived_manual_空名を保持する() passed after 0.001 seconds.
◇ Test ローカル履歴の識別可能本文は採用しサーバー履歴とは分離する() started.
✔ Test ローカル履歴の識別可能本文は採用しサーバー履歴とは分離する() passed after 0.001 seconds.
◇ Test ローカル履歴なしのthreadReadで由来の無い同一本文はflowerのまま() started.
✔ Test ローカル履歴なしのthreadReadで由来の無い同一本文はflowerのまま() passed after 0.001 seconds.
◇ Test 同一本文でもoriginalTextがあればサーバー履歴からログイン画面を修正を採用できる() started.
✔ Test 同一本文でもoriginalTextがあればサーバー履歴からログイン画面を修正を採用できる() passed after 0.001 seconds.
◇ Test 由来不能項目の後の由来ある通知を修正をthreadReadで採用する() started.
✔ Test 由来不能項目の後の由来ある通知を修正をthreadReadで採用する() passed after 0.001 seconds.
◇ Test サーバー履歴でoriginalTextが_review_なら補足を候補にしない() started.
✔ Test サーバー履歴でoriginalTextが_review_なら補足を候補にしない() passed after 0.001 seconds.
◇ Test PTY_の_sendText_と直接入力は導出しない() started.
✔ Test PTY_の_sendText_と直接入力は導出しない() passed after 0.396 seconds.
✘ Suite "task-44: session title lifecycle" failed after 0.487 seconds with 3 issues.
✘ Test run with 24 tests in 1 suite failed after 0.487 seconds with 3 issues.
```

exit 1。コンパイルは通った（`Build complete! (12.42s)`）。新規 1 件 RED（復元後 `source == .derived` / name・fullDerivedTitle が `ログイン画面を修正`）。既存 23 件 GREEN。

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
