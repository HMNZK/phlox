---
task: task-50
status: completed
---

# tests-task-50-r2

PM 承認（decision-log 2026-09-14「task-50 レビュー r1 裁定」）どおり、配線検査のハーネス欠陥 2 点を修理した。製品コード・契約・凍結テスト・台帳は未変更。

対象: `.claude/scripts/task50-wiring.rb`

## 修理内容

1. **1093 行付近の `Text(option)` 一律拒否**を、権限 2 キー（`approvalPolicy` / `sandboxMode`）の行と `choiceControl` の権限 kind 枝に限定して拒否する検査へ変更した。権限以外の行で `Text(option)` を使う正例を `good_codex_settings_src` の else 枝へ追加し、権限行で `Text(option)` を使う負例（H5）は維持した。
2. **1234 行付近の `codex_settings` / `cursor_settings`** に、Picker setter・保存 action（`CodexGeneralSettings.setValue` / `CursorGeneralSettings.setString` / `setBool`）の引数式を基準 blob と比較する検査を追加した。`setValue("never", ...)` の固定化を負例として selftest に追加し、good 同士の自己比較にはしていない。引数の切り出しは呼び出しの閉じ括弧位置（`match.end - 1`）を使い、コメント除去後のオフセットでは切らない。

## 検証原文

```
$ ruby .claude/scripts/task50-wiring.rb --selftest
task50-wiring --selftest: OK

$ env TASK50_BASELINE=e3dd2fb ruby .claude/scripts/task50-wiring.rb
task50-wiring: NG 基準時点のrb 自身が現在と同一ではない

$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK

$ env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb
task48-wiring: OK

$ (cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t50-ds swift test)
✔ Test run with 187 tests in 32 suites passed after 0.113 seconds.

$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t50-sf swift build)
t50-sf: OK（要約未対応）

$ cd macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t50-build -destination platform=macOS build 2>&1 | tail -3
** BUILD SUCCEEDED **

$ git diff --check
```

`TASK50_BASELINE` の NG は rb 自身の基準不一致のみ（再凍結前の想定内）。それ以外の NG は無い。selftest・task-48・Swift Testing・SessionFeature ビルド・App ビルド・空白検査は GREEN。

=== REPORT COMPLETE ===
