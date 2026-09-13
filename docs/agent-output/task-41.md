ESCALATION: 凍結テストが幅変換の期待値を内部矛盾したまま残しており、テスト改変禁止では task-41 を全件 GREEN にできません。開示レポートは `docs/agent-output/task-41.md`（`status: blocked`）。コミットしていません。

**製品側は契約修正どおりに直した。** `SessionTitleDeriver` は全角英数字・記号（U+FF01–U+FF5E）を半角 ASCII へ、半角カナ連続区間（U+FF61–U+FF9F）だけ Foundation の逆変換で全角カナへ、カナは半角化しない。U+3000 は trim / 内部圧縮のまま。`ｶﾀｶﾅ修正` → `カタカナ修正`、`ｶﾞ` → `ガ`、`ログイン*` と全角カナは不変。

**残っている旧ケースがブロッカー。** `halfwidthKatakanaConvertsToFullwidth` は PASS。同じ入力を半角のまま期待する `halfwidthKatakanaAndDakutenAreKept`（`AcceptanceSessionTitleDeriverTests.swift:363-367`）だけが 4 issues で RED。配線はテスト blob が `201e846` と一致することを要求するので、こちらでは消せない。

**検証。** 受け入れ 43 件中この 1 テストのみ失敗。全数 462 件も同じ 4 issues。`task41-wiring.rb --selftest` と `TASK41_BASELINE=201e846 TASK41_SCOPE_CHECK=1` は OK。`git diff --check` は exit 0。他担当の SessionFeature / DesignSystem には触っていない。

**PM へ。** 旧ケースを削除（または全角化の期待に合わせ）て再凍結すれば、実装の続きは不要でテスト再走だけで完了できる。
ト全件 GREEN という合格線は未達。
- スタブ・TODO・固定値の仮置きはなし。未完の原因は実装不足ではなく、再凍結後も残った旧ケース。

## 置いた前提・仮定

- 幅変換は契約修正を正本とした。(a) U+FF01...U+FF5E はコードポイント −0xFEE0。(b) U+FF61...U+FF9F の連続区間だけ `applyingTransform(.fullwidthToHalfwidth, reverse: true)`。(c) それ以外（全角カナ・ひらがな・漢字・U+3000）は変更しない。
- U+3000 は幅変換では触らず、既存の `trimmingCharacters(in: .whitespaces)` と内部空白圧縮で扱う。
- `applyingTransform` が `nil` のときは変換前の半角カナ区間を使う。
- 終了フェンスの「空白」は半角空白・タブ・U+3000。開始インデントは半角空白 0〜3 のみ。
- コード除外は契約のフェンス・4 空白/タブ・固定接頭辞のみ。任意言語の識別はしない（既存の `ponytail:` コメント）。
- `DerivedSessionTitle` の memberwise init は同一モジュールの合成 init で足りる（公開 init は契約に無い）。
- 他担当の未コミット（SessionFeature / DesignSystem 等）には触っていない。

## 契約からの逸脱

- 製品実装は契約修正に従っている。逸脱なし。
- 旧ケース `halfwidthKatakanaAndDakutenAreKept` の期待値（半角カナ維持）には従っていない。契約修正の「半角カナ→全角カナ」と衝突するため。テストは改変していない。
- task-41 の成立を UX-01 全体の完了とはしていない。

## レビュー重点（PM 用・レビュアーには渡さない）

- 最優先: `halfwidthKatakanaAndDakutenAreKept` を凍結スイートから除く（または期待値を全角化に合わせる）再凍結。実装側で両ケースを同時成立させる解はない。
- 幅変換の区間分割（全角 ASCII は算術、半角カナ連続区間だけ Foundation 逆変換）が契約文面どおりか。濁点 `ｶﾞ` → `ガ` は Foundation の合成結果に依存している。
- フェンス・32/33 Character・U+3000 圧縮は今回の差分の主眼ではないが、再凍結後の回帰で再確認する価値がある。

## 検証原文

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41 swift test --filter AcceptanceSessionTitleDeriverTests)`

exit 1。原文:

```
[0/1] Planning build
Building for debugging...
[0/4] Write sources
[2/4] Write swift-version--58304C5D6DBC2206.txt
[4/6] Emitting module AgentDomain
[5/6] Compiling AgentDomain SessionTitleDeriver.swift
[6/9] Emitting module AgentDomainTests
[7/9] Compiling AgentDomainTests AcceptanceSessionTitleDeriverTests.swift
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:269:13: warning: variable 'input' was never mutated; consider changing to 'let' constant
267 |     @Test("同一入力への反復呼び出しは同じ結果で、入力文字列は変化しない")
268 |     func repeatedCallsAreStableAndDoNotMutateInput() {
269 |         var input = "ログイン画面を修正"
    |             `- warning: variable 'input' was never mutated; consider changing to 'let' constant
270 |         let snapshot = input
271 |         let first = SessionTitleDeriver.derive(from: input)

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:279:13: warning: variable 'normalized' was never mutated; consider changing to 'let' constant
277 |         #expect(input == "ログイン画面を修正", Comment(rawValue: "input unchanged literal"))
278 | 
279 |         var normalized = "\r\n  API\t の　接続を修正  \r\n次の行"
    |             `- warning: variable 'normalized' was never mutated; consider changing to 'let' constant
280 |         let normalizedSnapshot = normalized
281 |         let once = SessionTitleDeriver.derive(from: normalized)
[7/9] Write Objects.LinkFileList
[8/9] Linking AgentDomainPackageTests
Build complete! (3.08s)
Test Suite 'Selected tests' started at 2026-09-13 12:30:31.203.
Test Suite 'AgentDomainPackageTests.xctest' started at 2026-09-13 12:30:31.204.
Test Suite 'AgentDomainPackageTests.xctest' passed at 2026-09-13 12:30:31.204.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-13 12:30:31.204.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "task-41: session title deriver" started.
✔ Test "半角カナを全角カナへ幅変換する" passed after 0.002 seconds.
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:19:9: Expectation failed: (result?.title → "カタカナ修正") == (expected → "ｶﾀｶﾅ修正")
↳ hw katakana title
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:20:9: Expectation failed: (result?.fullTitle → "カタカナ修正") == (expected → "ｶﾀｶﾅ修正")
↳ hw katakana fullTitle
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:19:9: Expectation failed: (result?.title → "ガ行を修正") == (expected → "ｶﾞ行を修正")
↳ hw dakuten title
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:20:9: Expectation failed: (result?.fullTitle → "ガ行を修正") == (expected → "ｶﾞ行を修正")
↳ hw dakuten fullTitle
✘ Test "半角カナと半角濁点は幅変換後も保持する" failed after 0.003 seconds with 4 issues.
✘ Suite "task-41: session title deriver" failed after 0.003 seconds with 4 issues.
✘ Test run with 43 tests in 1 suite failed after 0.003 seconds with 4 issues.
```

（途中の PASS 行は省略せず実行ログに存在する。失敗は上記 1 テスト・4 issues のみ。）

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41-all swift test)`

exit 1。task-41 以外の suite は PASS。原文の失敗箇所と要約行:

```
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:19:9: Expectation failed: (result?.title → "カタカナ修正") == (expected → "ｶﾀｶﾅ修正")
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:20:9: Expectation failed: (result?.fullTitle → "カタカナ修正") == (expected → "ｶﾀｶﾅ修正")
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:19:9: Expectation failed: (result?.title → "ガ行を修正") == (expected → "ｶﾞ行を修正")
✘ Test "半角カナと半角濁点は幅変換後も保持する" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:20:9: Expectation failed: (result?.fullTitle → "ガ行を修正") == (expected → "ｶﾞ行を修正")
✘ Test "半角カナと半角濁点は幅変換後も保持する" failed after 0.015 seconds with 4 issues.
✘ Suite "task-41: session title deriver" failed after 0.037 seconds with 4 issues.
✘ Test run with 462 tests in 24 suites failed after 1.033 seconds with 4 issues.
```

### `ruby .claude/scripts/task41-wiring.rb --selftest`

```
task41-wiring --selftest: OK
```

### `env TASK41_BASELINE=201e846 TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb`

```
task41-wiring: OK
```

### `git diff --check`

exit 0（出力なし）。

変更は `allowed_paths` の `SessionTitleDeriver.swift` と本レポートのみ。コミットしていない。

<!-- PM 注記 2026-09-13: 残っていた矛盾テスト 1 件（半角カナ保持）を契約修正に合わせて PM が修理し再凍結。製品は実装役の 2 回目のまま。AgentDomain 全数 GREEN を PM が確認し status を completed に更新 -->

=== REPORT COMPLETE ===
