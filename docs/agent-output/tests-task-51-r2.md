---
task: task-51
status: completed
---

敵対レビュー `docs/agent-output/task51-acceptance-adversarial.md` の採択項目（MUST1、HIGH2〜8、MEDIUM9・10）を退避先のまま反映した。製品コード・契約・台帳は未変更。コミットしていない。テストは `tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift` のまま（実パスへコピー・移動していない）。

## 指摘ごとの反映

| 指摘 | 反映 | 該当行 |
|---|---|---|
| MUST1 | Codex assistant 先行 fixture の既存 preview を実 `scan` どおり `"system 相当の出力"` に修正。`firstUserAt` は当該 event の `10:02:00` を固定。材料は `[Self.responseUser]` のまま | staged `:611` / `:612` |
| HIGH2 | 新規材料の宣言・収集・引数以外を凍結比較。`processScannedLine` の `firstUserLine` ブロックと entry 既存6引数を baseline と比較。先行メタと後続 user で日時・ブランチが違うテストを追加 | rb `check_frozen_restore` `:934`、staged `:150`、負例 `:1786` |
| HIGH3 | loader 依存の `extractUserText` / `extractAssistantText` / `extractTextContent` / `messageText` / `text` / `read` を凍結。`parseLine` は `isMeta` 追加だけ除外。`compact_preserving_strings` で文字列リテラルを保護 | rb `:317` / `:934`、負例 `:1780` / `:1793` / `:1800` |
| HIGH4 | 全 entry 生成で収集配列→append→条件→引数を検査。`isMeta==true` の除外方向、`role=="user"`、DB 列（first_user / preview）接続を要求。条件反転・配列破棄・別変数加工・片経路未接続・コメント/文字列/未使用/`if false` 偽装を負例に | rb `:661` / `:711`、負例 `:1804`–`:1834` |
| HIGH5 | 実行 SQL 文字列と bind を凍結比較。`sqlite3_open_v2` 第3引数が識別子 `SQLITE_OPEN_READONLY` であること。DB 分岐の追加 `scan`、LIMIT 削除、列順変更、フラグ変数化を負例に | rb `:837` / SQL 比較 `:934`、負例 `:1837`–`:1854` |
| HIGH6 | Swift に Claude 200/201 行、Codex index 201/202、不正 JSON で打ち切りを飛ばす境界、512 KiB 内外と `onRead` 回数・バイト数を追加。rb は while 条件と `index>200` の位置を比較 | staged `:410` / `:719` / `:740` / `:761`、rb `:786`、負例 `:1860` / `:1867` |
| HIGH7 | 本番マーカーは代入行ではなく独立コメント行。本番の `check_frozen_baseline(full)` 呼び出しだけを除去する負例。正常配線を外したコメント/文字列/未使用/`if false` は拒否 | rb `:1541`、負例 `:1874`、偽装 `:1816`–`:1834` |
| HIGH8 | Codex 複数 user・複数 text block・文字列 content・`event_msg.content`・改行付き長文・system/tool 非混入・assistant のみ（材料 `[]`・summary `nil`）。loader 取得結果も材料配列で固定 | staged `:793`–`:942`、loader `:712` |
| MEDIUM9 | 生 `Data` で不正 JSON / 不正 UTF-8 を挟み前後の材料と preview を固定。マルチバイトの 16KiB チャンク境界。Codex 空ファイルとメタデータのみは entry なし | staged `:494` / `:516` / `:968` |
| MEDIUM10 | `snapshotTree` は隠し項目も列挙し、ディレクトリ追加も記録。fixture に `.task51-hidden` と隠しディレクトリを置く | staged `:1492` / `:1431` |

## selftest 原文

```
$ ruby .claude/scripts/task51-wiring.rb --selftest
task51-wiring --selftest: OK
```

exit 0。

## parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceHistoryTitleSourcesTests.swift
```

診断出力なし。`PARSE_EXIT:0`。型検査・パッケージビルドは未実行（指示どおり。PM が再凍結時に実パスへ戻してコンパイル RED を確認する）。

## 見送った点と理由

- 製品コード（`ClaudeSessionHistory.swift` / `CodexSessionHistory.swift` / `ClaudeSessionHistoryEntry.swift`）・契約・台帳は指示どおり未変更。
- 受け入れテストは退避先のまま編集し、実パスへコピー・移動していない。
- 他担当の未コミットファイル（`AgentDomain/Tests` の Acceptance*SessionTitle*、`tasks/frozen/staged/` の他ファイル）には触っていない。
- 実 CLI 出力全体との一致は検査対象外のまま（敵対レビューどおり unverified）。

=== REPORT COMPLETE ===
