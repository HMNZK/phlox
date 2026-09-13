---
task: task-51
status: completed
---

task-51 の受け入れ検査を完成させた。製品コード・契約・台帳は未変更。他担当の未コミットファイルには触っていない。コミットしていない。

作成・完成したファイル:

- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift`
- `.claude/scripts/task51-wiring.rb`
- `docs/agent-output/tests-task-51.md`

`.claude/` は `.gitignore` される。凍結時は `git add -f .claude/scripts/task51-wiring.rb` が必要。契約の `baseline_commit` はプレースホルダのまま。

## 期待値の出所（契約の行）

正本は `tasks/task-51.md`。task-41 / task-49 の製品 API は呼ばない。fixture は現行パーサ `ClaudeSessionHistory.swift` / `CodexSessionHistory.swift` の JSONL・SQLite 形式に合わせた合成データ。

| 検査 | 契約 |
|---|---|
| `titleUserMessages: [String]?` / `titleSummary: String?`、既存 init 末尾に既定 `nil` | 新規公開契約 L53-67 |
| 新規引数なし → 両フィールド `nil`、既存6フィールドは入力どおり | 成功基準 L106 |
| Claude 文字列 `"/review\nログイン画面を修正"` | L107 |
| Claude text block `/review` + `設定画面を整理` → 1本文改行結合 | L108 |
| `isMeta: true` 除外、後続実依頼を保持、既存 preview は従来値 | L109 |
| `isMeta` 欠落 / `false` は通常本文 | L110 |
| 複数本文の改行・前後空白・出現順 | L111 |
| 120文字超は材料では切らない。preview は120文字。後続も保持 | L112 |
| assistant / system / tool result は混入しない。entry 成立時は `[]` | L113 |
| Codex `response_item` / `event_msg` の加工前本文 | L114 |
| assistant 先・user 後は user のみ。既存 preview 規則維持 | L115 |
| DB `first_user_message` と `preview` を分離 | L116 |
| DB ユーザー NULL・空・空白のみ → `[]`。補助材料保持。rollout 0回 | L117 |
| DB 利用可能で0件なら rollout 0回 | L118 |
| DB 利用不可なら既存 rollout フォールバック | L119 |
| Claude sidechain / メタデータのみ除外、件数・mtime・200行・256KiB | L123, L88 |
| Codex cwd・件数・順序、行数打ち切り、16KiB / 512KiB | L123, L89 |
| 採用 entry の ID / URL / preview / 日時 / ブランチ | L124 |
| loader は `/review`・メタ・貼り付けを従来どおり。fixture バイト列不変 | L125-L126 |
| XML 風本文は取得器では選定しない（材料に残す） | L81 |
| `nil` と `[]` の区別。取得器は `nil` を渡さない | L62-67 |

## RED 原文

コマンド: `(cd macos/Packages/DashboardFeature && swift build --build-tests)`

exit 1。error はすべて今回の受け入れテスト内の未定義メンバー。他ファイルの error はない。unique 箇所は 49。内訳は `titleUserMessages` と `titleSummary` のみ。

```
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift:58:23: error: value of type 'ClaudeSessionHistoryEntry' has no member 'titleUserMessages'
  56 |         #expect(entry.gitBranch == "dev")
  57 |         #expect(entry.fileURL == url)
  58 |         #expect(entry.titleUserMessages == nil)
     |                       `- error: value of type 'ClaudeSessionHistoryEntry' has no member 'titleUserMessages'
  59 |         #expect(entry.titleSummary == nil)
  60 |     }

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift:59:23: error: value of type 'ClaudeSessionHistoryEntry' has no member 'titleSummary'
  57 |         #expect(entry.fileURL == url)
  58 |         #expect(entry.titleUserMessages == nil)
  59 |         #expect(entry.titleSummary == nil)
     |                       `- error: value of type 'ClaudeSessionHistoryEntry' has no member 'titleSummary'
  60 |     }

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift:89:23: error: value of type 'ClaudeSessionHistoryEntry' has no member 'titleUserMessages'
  87 |         #expect(entry.preview == "/review ログイン画面を修正")
  88 |         #expect(entry.firstUserAt == isoDate(Self.claudeUserTimestamp))
  89 |         #expect(entry.titleUserMessages == [Self.reviewLogin])
     |                       `- error: value of type 'ClaudeSessionHistoryEntry' has no member 'titleUserMessages'
```

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番関数を呼び、正例と単一違反の負例を厳密比較する。

```
$ ruby .claude/scripts/task51-wiring.rb --selftest
task51-wiring --selftest: OK
```

exit 0。

## 契約の曖昧点

- `baseline_commit` は `"PM が凍結時に設定"` のまま。凍結 SHA は PM が実値へ置換する。調査時 HEAD は採用していない。
- `threads.preview` の生成者と常時要約可否は契約上未確認。本検査は補助候補として加工前値を固定する。
- 現行 `ParsedLine` に `isMeta` が無い。メタ除外は新規材料だけに適用し、`firstUserLine` / loader へ流用しない。
- Codex `scan` の `index > 200` は 0 始まりの既存打ち切り。行数の切り方は変えない前提で凍結する。
- assistant / system / tool result だけでは既存 `firstUserLine` が立たず entry 不成立。`[]` は isMeta ユーザー等で既存条件が成立する fixture に限る。
- `<` 始まりのユーザー本文は既存 preview 選定から外れる。取得器は選定せず材料に残す（task-49 の責務）。
- DB の空文字・空白のみ `preview` は `titleSummary` では加工せず保持する。既存 `preview` フィールドは従来の正規化とフォールバックのまま。

=== REPORT COMPLETE ===
