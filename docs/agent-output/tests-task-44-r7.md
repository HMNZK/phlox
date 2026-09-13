---
task: task-44
status: completed
---

# tests-task-44-r7

PM 承認（decision-log 2026-09-13「task-44 レビュー r4 裁定」）どおり、凍結受け入れテストへ被覆 2 件を追加した。製品コード・契約・rb・台帳・他テストは未変更。期待値は契約（tasks/task-44.md 末尾「訂正（レビュー r3 後）」: サーバー item の `raw.isMeta` が真なら `originalText` があっても不採用）から固定した。

対象: `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift`

## 追加ケースの行と根拠

ヘルパー（既存呼び出しの JSON は `isMeta` 省略時に不変）:

- `:396-417` `unidentifiedSupplementJSON` / `identifiedOriginalJSON` / `identifiedPlainJSON` に `isMeta: Bool? = nil` を追加し、真なら raw へ `"isMeta":true` を載せる。既存ケースの期待は不変。

追加ケース:

- `:1022-1039` `サーバー履歴でisMeta真ならoriginalTextがあってもflowerのまま`
  - 手順: ローカル履歴なし。`threadReadItemsJSON` に `identifiedOriginalJSON(id: "srv-meta", originalText: "ログイン画面を修正", isMeta: true)` だけを入れ、公開 `restore(...)` の実 `threadRead` 経路へ注入する。復元後も flower `Rose` のまま（derived にしない）。
  - 根拠: 同一本文でも `originalText` があれば採用できる既存ケース（`:948-971`）と対になる。契約訂正は `raw.isMeta == true` なら識別可能な元本文でも不採用。すべて識別不能なら flower。
- `:1041-1068` `ライブのisMeta真user項目は不採用で後続の通常user項目を採用する`
  - 手順: `startNew` 後、`.itemStarted` / `.itemCompleted` で `isMeta: true` かつ `originalText`「ログイン画面を修正」の user item を注入 → flower `Rose`。続けて通常の user item `identifiedPlainJSON(id: "live-readme", text: "README を更新")` → derived「README を更新」（花名 `Rose` 保持）。
  - 根拠: 契約のサーバー開始・完了イベントは識別可能な元本文を採用できるが、`isMeta` 真は不採用。識別不能項目の後の適格本文は採用できる（成功基準 2）。

## 検証原文（現行実装 GREEN）

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t44-tadd2 swift test --no-parallel --filter AcceptanceSessionTitleLifecycleTests)
✔ Test run with 26 tests in 1 suite passed after 0.463 seconds.
```

exit 0。新規 2 件を含む 26 件 GREEN。

## 変異確認の原文（isMeta 分岐削除 → RED、確認後に製品を復元）

一時的に `ChatSessionViewModel.identifiableOriginalText` から

`if case .bool(true) = item.raw?["isMeta"] { return nil }`

を外して同一フィルタを再走。既存 24 件は GREEN のまま、追加 2 件だけ RED。

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t44-tadd2-mut swift test --no-parallel --filter AcceptanceSessionTitleLifecycleTests)
[1/1] Compiling plugin GenerateManual
[2/2] Compiling plugin GenerateDoccReference
Building for debugging...
[2/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/7] Emitting module SessionFeature
[6/7] Compiling SessionFeature ChatSessionViewModel.swift
[6/8] Write Objects.LinkFileList
[7/8] Linking SessionFeaturePackageTests
Build complete! (3.87s)
Test Suite 'Selected tests' started at 2026-09-13 21:50:40.977.
Test Suite 'SessionFeaturePackageTests.xctest' started at 2026-09-13 21:50:40.978.
Test Suite 'SessionFeaturePackageTests.xctest' passed at 2026-09-13 21:50:40.978.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-13 21:50:40.978.
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
✔ Test assistant_tool_error_質問回答_別transcriptからは導出しない() passed after 0.012 seconds.
◇ Test 質問回答の入力はタイトル候補にしない() started.
✔ Test 質問回答の入力はタイトル候補にしない() passed after 0.011 seconds.
◇ Test ローカル_review_の補足付き送信文字列をitemCompletedで返してもflowerのまま() started.
✔ Test ローカル_review_の補足付き送信文字列をitemCompletedで返してもflowerのまま() passed after 0.015 seconds.
◇ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() started.
✔ Test ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま() passed after 0.015 seconds.
◇ Test ローカル本文と対応付くitemCompletedはローカル元本文を使い補足で先に確定しない() started.
✔ Test ローカル本文と対応付くitemCompletedはローカル元本文を使い補足で先に確定しない() passed after 0.011 seconds.
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
◇ Test サーバー履歴でisMeta真ならoriginalTextがあってもflowerのまま() started.
✘ Test サーバー履歴でisMeta真ならoriginalTextがあってもflowerのまま() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:380:5: Expectation failed: (state.name → "ログイン画面を修正") == (name → "Rose")
↳ isMeta true server history name
✘ Test サーバー履歴でisMeta真ならoriginalTextがあってもflowerのまま() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:381:5: Expectation failed: (state.source → .derived) == (source → .flower)
↳ isMeta true server history source
✘ Test サーバー履歴でisMeta真ならoriginalTextがあってもflowerのまま() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:383:5: Expectation failed: (state.fullDerivedTitle → "ログイン画面を修正") == (fullDerivedTitle → nil)
↳ isMeta true server history fullDerivedTitle
✘ Test サーバー履歴でisMeta真ならoriginalTextがあってもflowerのまま() failed after 0.001 seconds with 3 issues.
◇ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() started.
✘ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:380:5: Expectation failed: (state.name → "ログイン画面を修正") == (name → "Rose")
↳ isMeta true live item name
✘ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:381:5: Expectation failed: (state.source → .derived) == (source → .flower)
↳ isMeta true live item source
✘ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:383:5: Expectation failed: (state.fullDerivedTitle → "ログイン画面を修正") == (fullDerivedTitle → nil)
↳ isMeta true live item fullDerivedTitle
✘ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:380:5: Expectation failed: (state.name → "ログイン画面を修正") == (name → "README を更新")
↳ subsequent normal user item name
✘ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() recorded an issue at AcceptanceSessionTitleLifecycleTests.swift:383:5: Expectation failed: (state.fullDerivedTitle → "ログイン画面を修正") == (fullDerivedTitle → "README を更新")
↳ subsequent normal user item fullDerivedTitle
✘ Test ライブのisMeta真user項目は不採用で後続の通常user項目を採用する() failed after 0.030 seconds with 5 issues.
◇ Test PTY_の_sendText_と直接入力は導出しない() started.
✔ Test PTY_の_sendText_と直接入力は導出しない() passed after 0.340 seconds.
✘ Suite "task-44: session title lifecycle" failed after 0.464 seconds with 8 issues.
✘ Test run with 26 tests in 1 suite failed after 0.464 seconds with 8 issues.
```

exit 1。確認後 `git checkout -- macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift` で製品を復元。`git diff -- macos/Packages/SessionFeature/Sources` は空。作業ツリーの差分は受け入れテストのみ。

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
