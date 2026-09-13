---
task: task-49
status: completed
---

task-49（UX-11b HistoryEntryPresentation）の受け入れ検査を新規作成した。製品コード・契約・台帳は未変更。他担当の未コミットファイルと `/tmp/ui-ux-wt-*` には触っていない。コミットしていない。

作成物:

- `tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift`（実パス `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceHistoryEntryPresentationTests.swift`。先頭コメントに実パス。Swift Testing。`HistoryEntryPresentation` と task-51 の `titleUserMessages`／`titleSummary` 未実装のコンパイル RED が正常）
- `.claude/scripts/task49-wiring.rb`（`TASK49_BASELINE` 必須、契約 `baseline_commit` 一致、HEAD／ブランチ名拒否、祖先確認、基準に task-41／task-51 あり・`HistoryEntryPresentation.swift` と表示配線なし、凍結テストと rb の blob 同一性、製品配線、`--selftest`）
- `docs/agent-output/tests-task-49.md`

Swift テストは SessionFeature 実パスに置いていない（他タスクが同パッケージのテストを実行中のため退避）。PM が凍結時に実パスへ移す。`.claude/` は gitignore される。凍結時は `git add -f .claude/scripts/task49-wiring.rb` が必要。

## 期待値の出所（契約の行）

正本は `tasks/task-49.md`。製品モデルや `SessionTitleDeriver.derive` の戻り値から期待値を生成していない。各行はテスト内の独立リテラル。32／33 Character と複合絵文字・結合文字の省略形は task-41 契約と同じ固定文字列を再掲した（導出器を呼んでいない）。

| 検査 | 契約 |
|---|---|
| `["ログイン画面を修正"]` → title／fullTitle ともその文字列 | 成功基準表 L117 |
| `["/review\nログイン画面を修正"]` → `"ログイン画面を修正"` | L118 |
| `["/review", "設定画面を整理"]` → `"設定画面を整理"` | L119 |
| `Base directory for this skill:` 本文は丸ごと除外し次の依頼 | L120、決定順序 2（L63） |
| `"<command-name>/review</command-name>"` は丸ごと除外し次の依頼 | L121、L63 |
| 閉じたコードフェンスに続く依頼行 | L122。フェンス文法は task-41 に任せる（L68） |
| 適格なユーザー材料は異なる `titleSummary` より優先 | L123、決定順序 3→4（L64-65） |
| ユーザー材料が不適格、補助 `"履歴表示を修正"` | L124 |
| ユーザー・補助が定型文だけ → `"作業名なし"` | L125、決定順序 5（L66） |
| `titleUserMessages == []`、preview は旧表示、補助なし → `"作業名なし"` | L126、決定順序 1（L62） |
| `titleUserMessages == nil`、preview `"履歴表示を修正"`（旧 initializer） | L127、L62 |
| 32 Character はそのまま、33 Character は title 省略・fullTitle 入力 | L128-129 |
| cwd `/tmp/project-a/` は名前 `project-a`・projectPath は入力どおり | L130 |
| cwd `/` は両方 `/` | L131 |
| cwd nil・空・空白のみ → `"プロジェクト不明"`、projectPath nil | L132 |
| lastUsedAt は lastModified。`firstUserAt` で補わない | L133、L75-76 |
| lastModified が `.distantPast` → lastUsedAt nil | L134、L75 |
| 複合絵文字・結合文字の 32／33 Character 境界 | L136 |
| 同一入力の決定性、生成前後で entry の既存・新規フィールド不変 | L136 |
| 接頭辞は大文字・小文字を区別 | L63 |

配線検査の期待エラー文字列は契約成功基準 2（L140-177）の項目に対応する。到達性はコメント／文字列／未使用ヘルパー／`if false` を除いた実参照で判定する。

## `xcrun swiftc -parse` 原文

作業ディレクトリはリポジトリルート。構文のみ。モジュール解決・型検査はしない（未実装のコンパイル RED は PM が凍結時に実パスへ移して確認する）。

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift
```

標準出力・標準エラーは空。終了コード 0。構文欠陥は無い。

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番関数を呼び、正例と単一違反の負例の期待エラー集合を `==` で厳密比較する。

```
$ ruby .claude/scripts/task49-wiring.rb --selftest
task49-wiring --selftest: OK
```

終了コード 0。

正例は、契約どおりの配線が空 NG、URL／補間／文字列内空白の保持、コメント・文字列追加だけの非誤検知、固定 SHA が HEAD と同じでも実装前 blob なら拒否しない、新規製品ファイルの基準不存在は git 障害ではない、`SCOPE_CHECK` 未設定／`0` では範囲外変更を範囲違反にしない、を含む。負例は契約が列挙した「コメント・文字列・未使用ヘルパー・`if false` だけのモデル呼び出し」「主表示を `entry.preview` に戻す」「作業ディレクトリを固定値にする」「最終利用に `firstUserAt` を使う」「help、アクセシビリティ、新規作成／続きから再開の案内欠落」「別 entry を選択する、タイトルから再開先を引き直す」「履歴表示条件を弱める、キャッシュや復元処理を変更する」「task-51 の entry／取得器を変更する」「SHA 未設定・HEAD・`HEAD~1`・`@`・ブランチ名・契約不一致・blob 欠落・凍結検査改変・実装入り基準」を、期待配列との `==` で固定している。

本番パス（`TASK49_BASELINE` 未設定 + 契約 `baseline_commit: "PM が凍結時に設定"`）は凍結後に通す。今回は指示どおり `--selftest` のみ。

## 契約の曖昧点（検査側の確定）

契約・製品は変更していない。テストが採った解釈だけを残す。

1. **公開 API**: `struct HistoryEntryPresentation: Equatable, Sendable`。メンバーは `title`／`fullTitle`／`projectName`／`projectPath`／`lastUsedAt`。`init(entry:workingDirectory:)`。task-51 の `titleUserMessages: [String]?` と `titleSummary: String?` を entry 末尾引数として渡す。
2. **nil と []**: nil の代表は新規引数なしの既存 initializer。`[]` は明示配列。preview 代替は nil のときだけ。
3. **不適格ユーザー材料**: 表 L124 は `["/review"]`（task-49 接頭辞ではなく導出器が nil）と補助 `"履歴表示を修正"`。定型文だけ（L125）は `<` 接頭辞のユーザー材料と `Base directory for this skill:` の補助で、接頭辞除外だけでも `"作業名なし"` になることを固定した。
4. **閉じたフェンス**: 契約は依頼行の文言を書いていない。task-41 と同じ ```` ```swift` / `print(1)` / ` ``` ```` の閉じたフェンスの次行を `"履歴表示を修正"` とした。
5. **接頭辞の trim**: 判定だけ前後空白を除く。`"  <command-name>…"` は本文全体を除外する。残った本文を導出器へ渡す加工はしない。
6. **大文字・小文字**: `"base directory for this skill:"`（30 Character）は接頭辞不一致のため除外せず、title／fullTitle ともその文字列。
7. **空白のみの cwd**: `" "`・`"\t"`・`"　"`（U+3000）を空白のみとした。改行だけの cwd は契約に無いので固定していない。
8. **projectPath**: `/tmp/project-a/` は末尾 `/` を保持する。`/` は名前もパスも `/`。
9. **lastUsedAt**: `firstUserAt` と異なる `lastModified` をそのまま採る。`.distantPast` だけ nil。現在時刻は使わない。
10. **絵文字・結合文字**: task-41 の 30×`a` + `👨‍👩‍👧‍👦`／`e\u{301}` + 1〜2 文字のリテラルを再掲。33 Character の title は先頭 31 Character + `…`。
11. **entry 不変**: 値型のコピー前後比較。既存 6 フィールドと新規 2 フィールドをリテラルで固定する。
12. **配線の到達性**: `HistoryEntryPresentation` の検査起点は `init(entry:)`、View は `body`。文字列・コメントを先に保護し、未使用 `let`／`_ =`／`if false` はライブコードから除く。存在確認だけでは合格にしない。
13. **VM／Layout／task-51**: 共有 VM は `shouldOfferHistoryStart`／`scheduleHistoryCacheLoadIfNeeded`／`startFromHistory` だけを基準比較する。`ChatHistoryStartLayout` は enum 本体。entry と両取得器は凍結 blob のバイト一致。変更範囲の全体検査は `TASK49_SCOPE_CHECK=1`。
14. **`baseline_commit`**: `"PM が凍結時に設定"` のまま。凍結 SHA は PM が実値へ置換する。

## 凍結時メモ（PM）

- テストを契約 `acceptance_tests` の実パスへ移し、未実装コンパイル RED を確認する。
- `.claude/scripts/task49-wiring.rb` は gitignore される。凍結コミットでは `git add -f` と実パスのテストを同一コミットに入れる。
- そのコミット SHA を契約 `baseline_commit` と `TASK49_BASELINE` の両方に入れる。HEAD／ブランチ名は rb が拒否する。基準に task-41 の `SessionTitleDeriver.swift` と task-51 の `titleUserMessages` があり、`HistoryEntryPresentation.swift` と表示配線が無いことを rb が確認する。
- 取得器の材料供給は task-51 受け入れテスト、再開先と復元本文は既存 `ChatHistoryStartAcceptanceTests.swift` の回帰であり、本ファイルには含めない。

=== REPORT COMPLETE ===
