---
task: task-43
status: completed
---

敵対レビュー `docs/agent-output/task43-acceptance-adversarial.md` の採択項目（HIGH3・4・5・6・7・8、MEDIUM9・11・12）を退避先のまま反映した。製品コード・契約・台帳は未変更。コミットしていない。テスト2本は `tasks/frozen/staged/` のまま（実パスへコピー・移動していない）。

## 指摘ごとの反映

| 指摘 | 反映 | 該当行 |
|---|---|---|
| HIGH3 | 中間 View の実引数（`projectName` / `projectNames` / `taskName` / `rootProjectName`）を `labeled_arg` で経路追跡。nil・空辞書・`self.projectName = nil`・選択プロジェクト・GridChatColumn→GridComposerBar 未渡しを負例化 | rb `labeled_arg` :351、`check_single` :758、`check_grid` :857、selftest :1690–1700 |
| HIGH4 | 文字列・`if false` を除外してから型スコープで実参照を追跡（`collect_reachable` は struct 本文の var/func のみ）。グリッドは `GridComposerBar.body` 起点。body から呼ばれない helper・文字列だけ・`if false` を負例に | rb `collect_reachable` :309、`reachable_in_struct`、selftest :1705–1711 |
| HIGH5 | `TeamComposer` の `destination:` から action を逆追跡し `sendTeamMessage` を skip。phase / 開始可否は送信側と `compact` 同一比較。表示 action 削除・別 action・開始可否反転を負例に | rb `team_display_generation` :981、`check_team` :1006、selftest :1714–1720 |
| HIGH6 | 各ラベルの `hasDestination` / `isReadyForInput` / `hasContent` を既存送信条件へ結ぶ。否定欠落・`\|\|`→`&&`・trim 削除・readiness 直書き・宛先なしで true を負例化 | rb `has_content_defects` :551、selftest :1640 / :1723–1732 |
| HIGH7 | 宣言・条件式に加え footer `canSubmit:`・`.disabled`・`onSubmit`・`onFocusGained` の呼び出し引数を baseline 比較。独立負例を追加 | rb `INVARIANT_CALLS` :1130、`check_call_label_unchanged` :1179、selftest :1735–1741 |
| HIGH8 | 表示 Text の修飾・編集領域との順序・`proxy.size.height`→`composerHeight` を構造検査。`if let` と `if x != nil` の両方。幅計測だけ・AX 移動・`!= nil` 非表示を負例に | rb `destination_modifiers_ok?` :505、`height_geometry_covers?` :528、`hides_label_without_destination?` :541、selftest :1744–1750 |
| MEDIUM9 | `" \nPhlox\t "` → `Phlox / 入力欄改善`。作業名 `""` / `"\n\t"` → `作業名不明`、`" 調査 "` → `Phlox / 調査`。`.parentSession(projectName: nil, taskName: "全体作業")` → `プロジェクト名不明 / 全体作業 — 親セッションへの送信` | staged Session :93 / :113 / :121 / :129 / :227 |
| MEDIUM11 | 循環 resolver は a 開始→a のみ期待。`resolved == a` と `Phlox / 循環A — 親セッションへの送信` | staged Dashboard :362 / :380 |
| MEDIUM12 | 表示変数名を固定しない（`caption`・計算プロパティ `destinationCaption` の正例）。負例の action は実在 case（`.startDiscussion`→親送信、`.discussionUtterance`→`.legacyRootSend`）。`parens` をアサート | rb selftest :1617 / :1630 / :1637 / :1648 / :1651 |

## selftest 原文

```
$ ruby .claude/scripts/task43-wiring.rb --selftest
task43-wiring --selftest: OK
```

exit 0。

## parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceComposerDestinationLabelTests.swift
parse_session_exit:0
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceTeamComposerDestinationLabelTests.swift
parse_dashboard_exit:0
```

診断出力なし。型検査・パッケージビルドは未実行（指示どおり。PM が再凍結時に実パスへ戻してコンパイル RED を確認する）。

## 見送った点と理由

- MUST1（verify 入口）: 契約どおり PM が `ui-ux-verify-task.sh` に登録する。本担当の対象外。
- MUST2（コンパイル RED）: 契約で却下。触っていない。
- MEDIUM10（画面×状態がモデル単体）: 採択は記録のみ。テストはモデル単体のまま残し、実値の引き渡しは rb の HIGH3・5・6 で保護する。
- MEDIUM13（ADR 0046）: PM がフェーズ 5 で ADR 追記。検査側では高さ計測の構造検査のみ。

=== REPORT COMPLETE ===
