受け入れ検査を作成し、凍結用 RED を確認しました。製品コード・契約・台帳は変更していません。コミットもしていません。

作成したのは次の3ファイルです。

- `macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift` — 公開契約と成功基準1の全ケース。期待値は契約リテラル
- `.claude/scripts/task41-wiring.rb` — 凍結検査。`--selftest` はメモリ fixture
- `docs/agent-output/tests-task-41.md`

`ruby .claude/scripts/task41-wiring.rb --selftest` は **exit 0**（`task41-wiring --selftest: OK`）。

`(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41-red swift build --build-tests)` は **exit 1**。診断はすべて `cannot find 'SessionTitleDeriver' in scope` です。

`.claude/` は gitignore のため、凍結時は `git add -f .claude/scripts/task41-wiring.rb` が必要です。
ない |

`.claude/` は `.gitignore` されている。凍結コミット時は `git add -f .claude/scripts/task41-wiring.rb` が必要。

## 期待値の出所（契約の行）

正本は `tasks/task-41.md`。製品の戻り値から期待値を生成していない。

| テスト | 契約 |
|---|---|
| 公開 `derive(from:)` が `title` / `fullTitle` を返す | L38-47（新規公開契約） |
| `ログイン画面を修正\n詳しい条件` → 両方 `ログイン画面を修正` | L77 |
| `\r\n  API\t の　接続を修正  \r\n次の行` → 両方 `API の 接続を修正` | L78 |
| `ＡＰＩ　１２３を修正` → 両方 `API 123を修正` | L79 |
| 空文字・空白のみ・改行のみ → `nil` | L80 |
| `/review`、`／review 引数` → `nil` | L81 |
| `/review\nログイン画面を修正` → 両方 `ログイン画面を修正` | L82 |
| バッククォート3個の開始・コード・終了だけ → `nil` | L83（言語指定は L54） |
| 閉じたフェンスの次行 `ログインを修正` | L84 |
| チルダ3個のフェンス（同上） | L85 |
| バッククォート4個開始・3個の行しかない → 開始後から採らない | L86 |
| バッククォート開始をチルダで閉じようとする → 開始後から採らない | L87 |
| 未閉鎖フェンスの前の適格行 | L88 |
| `    let value = 1\nログインを修正` | L89 |
| `\t説明\nログインを修正` | L90 |
| `import Foundation\nログインを修正` | L91 |
| 各除外接頭辞の行に続く `ログインを修正` | L92（接頭辞一覧は L59-62） |
| `APIを修正` の大文字維持 | L93 |
| 32 Character 維持 | L94 |
| 33 Character → title は 31 Character + `…`、fullTitle は入力 | L95 |
| `👨‍👩‍👧‍👦` と `e\u{301}` の 32／33 Character 境界 | L97 |
| 反復呼び出しが同じ結果・入力文字列が変化しない | L97 |

表の `\n`・`\r`・`\t` は実際の制御文字。省略記号は U+2026 `…`。

## RED 原文

コマンド: `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41-red swift build --build-tests)`

exit 1。エラーはすべて `cannot find 'SessionTitleDeriver' in scope`。他種別の診断は無い。

```
Building for debugging...
[0/4] Write sources
[1/4] Write swift-version--58304C5D6DBC2206.txt
[3/6] Emitting module AgentDomainTests
[4/6] Compiling AgentDomainTests AcceptanceSessionTitleDeriverTests.swift
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:18:22: error: cannot find 'SessionTitleDeriver' in scope
 16 | struct AcceptanceSessionTitleDeriverTests {
 17 |     private func expectBoth(_ input: String, _ expected: String, _ label: String) {
 18 |         let result = SessionTitleDeriver.derive(from: input)
    |                      `- error: cannot find 'SessionTitleDeriver' in scope
 19 |         #expect(result?.title == expected, Comment(rawValue: "\(label) title"))
 20 |         #expect(result?.fullTitle == expected, Comment(rawValue: "\(label) fullTitle"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:24:17: error: cannot find 'SessionTitleDeriver' in scope
 22 | 
 23 |     private func expectNil(_ input: String, _ label: String) {
 24 |         #expect(SessionTitleDeriver.derive(from: input) == nil, Comment(rawValue: label))
    |                 `- error: cannot find 'SessionTitleDeriver' in scope
 25 |     }
 26 | 

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:29:22: error: cannot find 'SessionTitleDeriver' in scope
 27 |     @Test("公開契約: derive(from:) が title/fullTitle を返す")
 28 |     func publicAPIMatchesContract() {
 29 |         let result = SessionTitleDeriver.derive(from: "ログイン画面を修正")
    |                      `- error: cannot find 'SessionTitleDeriver' in scope
 30 |         #expect(result?.title == "ログイン画面を修正", Comment(rawValue: "public title"))
 31 |         #expect(result?.fullTitle == "ログイン画面を修正", Comment(rawValue: "public fullTitle"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:32:21: error: cannot find 'SessionTitleDeriver' in scope
 30 |         #expect(result?.title == "ログイン画面を修正", Comment(rawValue: "public title"))
 31 |         #expect(result?.fullTitle == "ログイン画面を修正", Comment(rawValue: "public fullTitle"))
 32 |         let again = SessionTitleDeriver.derive(from: "ログイン画面を修正")
    |                     `- error: cannot find 'SessionTitleDeriver' in scope
 33 |         #expect(result == again, Comment(rawValue: "equatable"))
 34 |     }

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:208:22: error: cannot find 'SessionTitleDeriver' in scope
206 |     func thirtyThreeCharactersTruncateTitle() {
207 |         let input = "abcdefghijklmnopqrstuvwx123456789"
208 |         let result = SessionTitleDeriver.derive(from: input)
    |                      `- error: cannot find 'SessionTitleDeriver' in scope
209 |         #expect(result?.title == "abcdefghijklmnopqrstuvwx1234567…", Comment(rawValue: "33 title"))
210 |         #expect(result?.fullTitle == "abcdefghijklmnopqrstuvwx123456789", Comment(rawValue: "33 fullTitle"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:224:22: error: cannot find 'SessionTitleDeriver' in scope
222 |         let input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦bc"
223 |         #expect(input.count == 33, Comment(rawValue: "33 Character fixture"))
224 |         let result = SessionTitleDeriver.derive(from: input)
    |                      `- error: cannot find 'SessionTitleDeriver' in scope
225 |         #expect(result?.title == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦…", Comment(rawValue: "family emoji 33 title"))
226 |         #expect(result?.fullTitle == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦bc", Comment(rawValue: "family emoji 33 fullTitle"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:240:22: error: cannot find 'SessionTitleDeriver' in scope
238 |         let input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}bc"
239 |         #expect(input.count == 33, Comment(rawValue: "33 Character fixture"))
240 |         let result = SessionTitleDeriver.derive(from: input)
    |                      `- error: cannot find 'SessionTitleDeriver' in scope
241 |         #expect(result?.title == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}…", Comment(rawValue: "combining 33 title"))
242 |         #expect(result?.fullTitle == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}bc", Comment(rawValue: "combining 33 fullTitle"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:249:21: error: cannot find 'SessionTitleDeriver' in scope
247 |         var input = "ログイン画面を修正"
248 |         let snapshot = input
249 |         let first = SessionTitleDeriver.derive(from: input)
    |                     `- error: cannot find 'SessionTitleDeriver' in scope
250 |         let second = SessionTitleDeriver.derive(from: input)
251 |         #expect(first == second, Comment(rawValue: "repeat equal"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:250:22: error: cannot find 'SessionTitleDeriver' in scope
248 |         let snapshot = input
249 |         let first = SessionTitleDeriver.derive(from: input)
250 |         let second = SessionTitleDeriver.derive(from: input)
    |                      `- error: cannot find 'SessionTitleDeriver' in scope
251 |         #expect(first == second, Comment(rawValue: "repeat equal"))
252 |         #expect(first?.title == "ログイン画面を修正", Comment(rawValue: "repeat title"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:259:20: error: cannot find 'SessionTitleDeriver' in scope
257 |         var normalized = "\r\n  API\t の　接続を修正  \r\n次の行"
258 |         let normalizedSnapshot = normalized
259 |         let once = SessionTitleDeriver.derive(from: normalized)
    |                    `- error: cannot find 'SessionTitleDeriver' in scope
260 |         let twice = SessionTitleDeriver.derive(from: normalized)
261 |         #expect(once == twice, Comment(rawValue: "normalized repeat"))

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift:260:21: error: cannot find 'SessionTitleDeriver' in scope
258 |         let normalizedSnapshot = normalized
259 |         let once = SessionTitleDeriver.derive(from: normalized)
260 |         let twice = SessionTitleDeriver.derive(from: normalized)
    |                     `- error: cannot find 'SessionTitleDeriver' in scope
261 |         #expect(once == twice, Comment(rawValue: "normalized repeat"))
262 |         #expect(once?.title == "API の 接続を修正", Comment(rawValue: "normalized title"))
```

## selftest 原文

コマンド: `ruby .claude/scripts/task41-wiring.rb --selftest`

exit 0。

```
task41-wiring --selftest: OK
```

`--selftest` は本番関数へメモリ fixture を渡す。実ファイルは変更しない。正例と、違反 1 件ずつの負例（SHA 未設定・不正・`HEAD` / `HEAD~1` / `@` / ブランチ名・契約不一致・blob 欠落・テスト改変・検査改変・実装入り基準・禁止依存・コメントだけの宣言偽装）。

## PM の凍結コマンド

契約 `baseline_commit` を実 SHA へ置換し、検査ファイルを `git add -f` した凍結コミットの SHA を `<凍結SHA>` とする。実装前に RED、実装後に GREEN。

```sh
~/.agents/scripts/compact-test task41-models bash macos/scripts/run-swift-tests.sh AgentDomain
~/.agents/scripts/compact-test task41-wiring-selftest ruby .claude/scripts/task41-wiring.rb --selftest
~/.agents/scripts/compact-test task41-wiring env TASK41_BASELINE=<凍結SHA> ruby .claude/scripts/task41-wiring.rb
```

実装後の統合確認:

```sh
~/.agents/scripts/compact-test task41-integration bash .claude/verify.sh
```

凍結コミットに含めるもの: 受け入れテスト、`git add -f .claude/scripts/task41-wiring.rb`、契約の `baseline_commit` 置換。`SessionTitleDeriver.swift` は含めない。

実装前の期待: selftest は OK。Swift は `SessionTitleDeriver` 未定義でコンパイル RED。製品配線は公開面不在で NG。基準 SHA と HEAD が同一でも、基準 blob に実装が無ければ自己比較としては拒否しない。

## 未対応事項

- 契約 `baseline_commit` はプレースホルダのまま。`env TASK41_BASELINE=<凍結SHA> ruby .claude/scripts/task41-wiring.rb` の製品検査は凍結後に PM が行う。
- 成功基準 3 の実装後統合（`.claude/verify.sh`）は未実施。
- コミットしていない。

=== REPORT COMPLETE ===
