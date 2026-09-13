---
task: task-50
status: completed
---

敵対レビュー `docs/agent-output/task50-acceptance-adversarial.md` の採択項目を退避先のまま反映した。製品コード・契約・台帳は未変更。コミットしていない。テストは `tasks/frozen/staged/AcceptancePermissionWordingTests.swift` のまま（実パスへコピー・移動していない）。

## 指摘ごとの反映

| 指摘 | 反映 | 該当行 |
|---|---|---|
| M1 | `onAppear` から辿れる保存（`applyConfig` / `applySettings`）だけを拒否。正例 Codex は `.onAppear(perform: syncModelDraft)` と Picker 側 `applyConfig` を共存 | rb `on_appear_saves?` `:439`、`check_invariants` `:1237`、正例 `:1679` |
| M2 | 再凍結はしない。基準側で `UIWording.swift` の存在と `text`/`planOption`/`permissionLabel`、共有ファイルの task-48 接続を検査 | rb PATHS `:539`、`task48_canonical_errors` `:675`–`:678`、負例 `:2233` |
| M3 | 採択は PM 裁定どおり本担当では触らない（下記「見送った点」） | — |
| H1 | 許可表示以外を凍結 blob と比較。`option_value_sequence` / `tag_sequence` / AppStorage / action 引数を基準と `same_code?`。切り出し失敗は非ゼロ | rb `:399`、`check_invariants` `:1262`–`:1283`、負例 `:2034` |
| H2 | 起動比較対象に `AgentDescriptor` / `CursorChatClient` / `CompositionRoot` を追加。欠落 blob は非ゼロ。`launch_fingerprint` で条件反転・ON/OFF 交換を検出 | rb PATHS `:549`–`:551`、`launch_fingerprint` `:486`、PROTECTED `:1242`、負例 `:2041` / `:2046` |
| H3 | 文字列をマスクした API 検出と `wording_displayed?`。未使用代入・文字列・コメント・`if false` を単独負例 | rb `uses_permission_api?`、負例 `:2053` / `:2063` / `:2073` / `:2083` |
| H4 | 正例は OFF・ON を同時 `Text`。片側三項・agent 固定・未使用 footer・固定3行を個別拒否 | rb `check_settings_view` `:965`–`:992`、正例 `:1579`、負例 `:2090`–`:2112` |
| H5 | `editor` / `bucketSection` / 導入文 / `choiceControl` / `control` を個別検査。Cursor 導入と Codex 生 `Text(option)` を負例 | rb `check_management` `:1040`–`:1094`、負例 `:2119` / `:2129` |
| H6 | 3 エージェント×通常・省略（named menu）と選択中チップを別検査。Cursor 通常メニューだけ explanation 欠落を負例 | rb `check_named_menu` `:810`、`cursorModeMenu` `:905`、負例 `:2137` |
| H7 | 環境 locale → `languageCode` 引数まで `check_locale_chain`。PhloxApp の注入も検査。未受信・`Locale.current`・引数無視を負例 | rb `:391` / `:527` / `:823`、負例 `:2144`–`:2159` |
| D1 | Codex/Cursor sandbox 未知値、Codex sandbox 英語 nil、Cursor approval 英語 nil、Cursor sandbox 日本語 nil、空白・改行の原文保持、agent だけ変えた未知扱い、起動説明の地域付き／未対応言語 | staged `:491`–`:529` |
| D2 | 説明箇所で `lineLimit` / 固定高 / 縮小を個別拒否 | rb `truncation_message` `:470`、`SettingsMenuRow` `:933`、負例 `:2166`–`:2180` |

## selftest 原文

```
$ ruby .claude/scripts/task50-wiring.rb --selftest
task50-wiring --selftest: OK
```

exit 0。

## parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptancePermissionWordingTests.swift
```

診断出力なし。`PARSE_EXIT:0`。型検査・パッケージビルドは未実行（指示どおり。PM が再凍結時に実パスへ戻してコンパイル RED を確認する）。

## 見送った点と理由

- M2 の再凍結は PM 工程。rb に task-48 正本の存在・接続検査だけを足した。
- M3: `task38-wiring.rb` は後続に適用しない。`ComposerModeMenuAcceptanceTests` 等の日英改訂は task-48 側。触っていない。
- 製品コード・契約・台帳、他担当の `tasks/frozen/staged/` ファイル、他の `taskNN-wiring.rb`、Sources 配下は未変更。
- 受け入れテストは退避先のまま編集し、実パスへコピー・移動していない。
=== REPORT COMPLETE ===
