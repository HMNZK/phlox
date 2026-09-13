指摘 1・4・5・6 を `.claude/scripts/task17-wiring.rb` だけ直しました。製品コード・契約・台帳は未変更で、コミットしていません。

**指摘 1:** コメントと文字列を同時に見る字句走査に切り替えました。`// "` で `.disabled(true)` を隠す反例は負例、引用符・入れ子コメントは正例です。

**指摘 4:** 対象 3 Button それぞれで `.buttonStyle(.bordered)` がちょうど 1 件、かつ基準の `RichButtonStyle()` と同じ修飾位置であることを検査します。二重付与と位置移動は負例です。

**指摘 5:** 「スタイルだけ旧に戻す」「焦点抑制だけ残す」「対象のスタイルを別ボタンへ移す」に分け、それぞれ名指しの診断文言を必須にしました。

**指摘 6:** 実コミット SHA 同士の不一致、HEAD 同値かつ実装前 blob の正例、実装後 blob の負例を、通常実行と同じ関数で追加しました。

`ruby .claude/scripts/task17-wiring.rb --selftest` は **OK**（exit 0）です。

`env TASK17_BASELINE=3abd7d1 ruby .claude/scripts/task17-wiring.rb` は短絡せず、**凍結整合性 NG と製品 RED の両方**を出して exit 1 です。先頭は再凍結前として正常な `基準時点の rb 自身が現在と同一ではない`、続けて未実装の `RichButtonStyle` 残存・`.bordered` 0 件・焦点抑制が減らないことです。

報告は `docs/agent-output/tests-task-17-r2.md` です。selftest はどちらも **OK**（exit 0）でした。配線検査の修正と報告 `docs/agent-output/tests-task-17-r2.md` は、その結果を反映済みです。
�リーは変更していない。 |

## コマンド原文

### `ruby .claude/scripts/task17-wiring.rb --selftest`

```
task17-wiring --selftest: OK
```

exit 0。

### `env TASK17_BASELINE=3abd7d1 ruby .claude/scripts/task17-wiring.rb`

短絡せず、凍結整合性 NG と製品 RED の両方を出力して exit 1。先頭行は rb 自身の blob 不一致（再凍結前として正常）。続けて未実装の製品 RED。

```
task17-wiring: NG 基準時点の rb 自身が現在と同一ではない
task17-wiring: NG RichButtonStyle の定義が 1 件（期待 0）
task17-wiring: NG RichButtonStyle の使用が 3 件（期待 0）
task17-wiring: NG Button「通知テスト」の .buttonStyle(.bordered) が 0 件（期待ちょうど 1）
task17-wiring: NG Button「今すぐ確認」の .buttonStyle(.bordered) が 0 件（期待ちょうど 1）
task17-wiring: NG Button「エージェント管理を開く」の .buttonStyle(.bordered) が 0 件（期待ちょうど 1）
task17-wiring: NG .focusEffectDisabled() が 3 件で基準から 0 件減少（期待ちょうど 3）
task17-wiring: NG Button「通知テスト」に .focusEffectDisabled() が残っている
task17-wiring: NG Button「今すぐ確認」に .focusEffectDisabled() が残っている
task17-wiring: NG Button「エージェント管理を開く」に .focusEffectDisabled() が残っている
```

再凍結後は先頭の rb blob 不一致が消え、実装前なら製品 RED のみが残る想定。

## 未対応 / 範囲外

- 指摘 2・3（HIGH）は契約・目視ゲート側。本担当では触っていない。
- 製品実装・契約・台帳・コミットは行っていない。

=== REPORT COMPLETE ===
