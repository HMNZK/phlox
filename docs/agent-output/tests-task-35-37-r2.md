---
task: tests-task-35-37-r2
status: completed
---
## 変更点（ファイル別、指摘番号との対応）

- `tasks/task-35.md`（1, 3, 6, 9, 11）: `replace_struct` を空文字除去にする旨、make 代入先が両 View に渡ること、入力欄 ZStack 先頭の `model.background`、`terminalSwatches` の `.reversed()` / `.shuffled()` / 添字禁止、文字列安全なコメント除去、成功基準 3 冒頭に隔離 Debug App ビルドコマンド、PM 追記を「入力欄比較完了またはユーザー免除まで UI-06 を完了マークしない」に改訂。10 テーマループの文言 5 種と `requireEquatable` を成功基準 1 に明記。
- `tasks/task-36.md`（2, 3, 4, 5, 6, 7, 8, 10, 11）: `depends_on: [task-35]`。allowed_paths から 3 StatusPane を外す。目的に ADR-0121 置換（ADR 更新はフェーズ5・実装役対象外）。StatusSummary / 状態ペイン配線を削除。`TASK36_BASELINE` は task-35 完了後 SHA。reload / init / `.task` / messageBar の case ごと対応を baseline 比較に拡大。Picker set 完全一致、`.isSelected`、`MenuPickerStyle()`、`return` 省略 switch。成功基準 3 に App ビルド。60 組・`section.agent`・allCases 順序を成功基準 1 に明記。
- `tasks/task-37.md`（10, 3, 4, 6, 11）: 新規。`AgentConsoleStatusSummary.swift` と 3 StatusPane。`depends_on: []`。`acceptance_tests` は `AcceptanceAgentConsoleStatusSummaryTests.swift`。`baseline_commit: TBD`。make 実引数の完全一致、DisclosureGroup label 形、toolbar / 設定節 / Finder / `loadMCPServers()` の baseline 比較。成功基準 3 に App ビルド。
- `tasks/frozen/staged/AcceptanceThemePreviewModelTests.swift`（5）: 10 テーマループで `bodyText` / `selectedRowText` / `inputText` / `appLabel` / `terminalLabel` を検査。`requireEquatable(ThemePreviewModel.self)` と `ThemePreviewModel.Layer.self`。
- `tasks/frozen/staged/AcceptanceAgentConsoleNavigationModelTests.swift`（2, 5, 10）: タプル配列 `==` を id / title の別比較に変更。60 組ですべて agent・sections・selectedSection・locationText を検査。`section.agent` 19 組と `allCases` 順序を固定。StatusSummary テストを削除。`requireEquatable` を NavigationModel / Agent / Section に適用。
- `tasks/frozen/staged/AcceptanceAgentConsoleStatusSummaryTests.swift`（5, 10）: 新規。Bool 4 組のリテラル比較と `requireEquatable`。
- `.claude/scripts/task35-wiring.rb`（1, 3, 6）: 空文字 `replace_struct`、make 代入検査、入力欄/選択行 ZStack 先頭、色帯の順序改変拒否、文字列トークナイザ、`--selftest`。
- `.claude/scripts/task36-wiring.rb`（3, 4, 6, 7）: Picker set 完全一致、`.isSelected`、MenuPickerStyle、return 省略、messageBar / reload / init / `.task` の baseline 比較、StatusPane 検査を削除、`--selftest`。
- `.claude/scripts/task37-wiring.rb`（3, 4, 6, 10）: 新規。make 実引数完全一致、DisclosureGroup label 形、toolbar / 設定節 / Finder / `loadMCPServers()` の baseline 比較、`--selftest`。

製品コードは変更していない。

## 反映しなかった／変えた裁定（理由）

- 指摘 9 の PM 追記は指定文に加え、「入力欄比較未達のまま代替合格にしない」を 1 文足した。成功基準 3・Rubric と矛盾しないため。
- `Layer` は契約の入れ子に合わせ `ThemePreviewModel.Layer` として凍結した（トップレベル `Layer` ではない）。
- task-37 配線の `UNCHANGED_PATHS` から SettingsView / WindowView を外した。並列の task-35/36 が触るため、凍結 SHA との `git diff --quiet` が統合後に偽陽性になる。変更禁止は契約と allowed_paths で担保する。
- `.claude/scripts/ui-ux-verify-task.sh` は指定対象外のため未更新（`TASK36_BASELINE=18bbcc4` のまま、task-37 分岐なし）。

## selftest と rb 実行結果（原文）

`ruby -c .claude/scripts/task35-wiring.rb`
`ruby -c .claude/scripts/task36-wiring.rb`
`ruby -c .claude/scripts/task37-wiring.rb`

```
Syntax OK
Syntax OK
Syntax OK
```

`ruby .claude/scripts/task35-wiring.rb --selftest`
`ruby .claude/scripts/task36-wiring.rb --selftest`
`ruby .claude/scripts/task37-wiring.rb --selftest`

```
task35-wiring --selftest: OK
task36-wiring --selftest: OK
task37-wiring --selftest: OK
```

`TASK35_BASELINE=HEAD ruby .claude/scripts/task35-wiring.rb; TASK36_BASELINE=HEAD ruby .claude/scripts/task36-wiring.rb; TASK37_BASELINE=HEAD ruby .claude/scripts/task37-wiring.rb`

（各スクリプト exit 1。`;` 連結のシェル終了コードも 1）

```
task35-wiring: NG macos/Packages/DesignSystem/Sources/DesignSystem/ThemePreviewModel.swift が存在しない
task35-wiring: NG ThemeRowView 本文に Text(model.appLabel) が無い
task35-wiring: NG ThemeRowView 本文に Text(model.terminalLabel) が無い
task35-wiring: NG ThemeRowView 本文の ThemePreviewModel.make( が 0 回（期待 1）
task35-wiring: NG ThemeRowView 本文に ThemePreviewModel.make( が無い
task35-wiring: NG ThemePreviewModel.make の戻り値が変数に代入されていない
task35-wiring: NG ThemeRowView 本文に ThemeAppPreview( が無い
task35-wiring: NG ThemeAppPreview の struct 本文を括弧対応で切り出せない
task35-wiring: NG ThemeSwatchStrip 本文に model.terminalSwatches が無い
task36-wiring: NG AgentConfigKit の enum AgentConsoleAgent が 0 個（期待 1）
task36-wiring: NG AgentConfigKit の enum AgentConsoleSection が 0 個（期待 1）
task36-wiring: NG App 側に enum AgentConsoleAgent が残っている
task36-wiring: NG App 側に enum AgentConsoleSection が残っている
task36-wiring: NG macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift が存在しない
task36-wiring: NG AgentConsoleSection.swift が AgentConfigKit を import していない
task36-wiring: NG AgentConsoleSection.swift に extension AgentConsoleAgent が無い
task36-wiring: NG WindowView に AgentConsoleNavigationModel.make(agent: selection?.agent ?? .claude, selection: selection) が無い
task36-wiring: NG WindowView に agentGroup が残っている
task36-wiring: NG WindowView に AgentConsoleSection.sections(for: が残っている
task36-wiring: NG sidebar に ForEach(navigation.sections) が無い
task36-wiring: NG sidebar に Picker( が無い
task36-wiring: NG sidebar に navigation.agentPickerLabel が無い
task36-wiring: NG sidebar に .pickerStyle(.menu) も .pickerStyle(MenuPickerStyle()) も無い
task36-wiring: NG sidebar に accessibilityIdentifier("agent-console-agent-picker") が無い
task36-wiring: NG Picker の set が selection = AgentConsoleNavigationModel.make(agent: newAgent, selection: nil).selectedSection ではない
task36-wiring: NG sidebar に navigation.selectedSection == section が無い
task36-wiring: NG sidebar に selection = section が無い
task36-wiring: NG AgentConsoleSectionRow に .help(section.detail) が無い
task36-wiring: NG AgentConsoleSectionRow に常時表示の Text(section.detail) が残っている
task36-wiring: NG AgentConsoleSectionRow に accessibilityIdentifier("agent-console-section-\(section.rawValue)") が無い
task36-wiring: NG WindowView に Text(navigation.locationText) が無い
task36-wiring: NG WindowView に accessibilityIdentifier("agent-console-location") が無い
task36-wiring: NG detail の switch が navigation.selectedSection ではない
task36-wiring: NG messageBar の switch が navigation.agent ではない
task37-wiring: NG macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleStatusSummary.swift が存在しない
task37-wiring: NG ClaudeStatusPane に @State private var showsCLIDetails = false が無い
task37-wiring: NG ClaudeStatusPane に AgentConsoleStatusSummary.make( が無い
task37-wiring: NG ClaudeStatusPane に summary.availabilityText が無い
task37-wiring: NG ClaudeStatusPane に summary.availabilityDetail が無い
task37-wiring: NG ClaudeStatusPane に summary.configurationText が無い
task37-wiring: NG ClaudeStatusPane に summary.configurationDetail が無い
task37-wiring: NG ClaudeStatusPane の先頭表示順検査に availabilityText / summaryTiles が足りない
task37-wiring: NG ClaudeStatusPane の DisclosureGroup を括弧対応で切り出せない
task37-wiring: NG CodexStatusPane に @State private var showsCLIDetails = false が無い
task37-wiring: NG CodexStatusPane に AgentConsoleStatusSummary.make( が無い
task37-wiring: NG CodexStatusPane に summary.availabilityText が無い
task37-wiring: NG CodexStatusPane に summary.availabilityDetail が無い
task37-wiring: NG CodexStatusPane に summary.configurationText が無い
task37-wiring: NG CodexStatusPane に summary.configurationDetail が無い
task37-wiring: NG CodexStatusPane の先頭表示順検査に availabilityText / summaryTiles が足りない
task37-wiring: NG CodexStatusPane の DisclosureGroup を括弧対応で切り出せない
task37-wiring: NG CursorStatusPane に @State private var showsCLIDetails = false が無い
task37-wiring: NG CursorStatusPane に AgentConsoleStatusSummary.make( が無い
task37-wiring: NG CursorStatusPane に summary.availabilityText が無い
task37-wiring: NG CursorStatusPane に summary.availabilityDetail が無い
task37-wiring: NG CursorStatusPane に summary.configurationText が無い
task37-wiring: NG CursorStatusPane に summary.configurationDetail が無い
task37-wiring: NG CursorStatusPane の先頭表示順検査に availabilityText / summaryTiles が足りない
task37-wiring: NG CursorStatusPane の DisclosureGroup を括弧対応で切り出せない
```

## PM 宛の疑問点

- `.claude/scripts/ui-ux-verify-task.sh` は task-36 に `TASK36_BASELINE=18bbcc4` を渡したまま。task-35 完了後 SHA への更新と task-37 分岐の追加が必要。
- 新規ファイル（`tasks/task-37.md`、`.claude/scripts/task37-wiring.rb`、`tasks/frozen/staged/AcceptanceAgentConsoleStatusSummaryTests.swift`、本報告）は `.gitignore` の `/tasks/`・`.claude/`・`/docs/` に隠れる。追跡済みファイルの更新は差分に出る。コミット時は `git add -f` が必要。
- `TASK37_BASELINE` と `task-37` の `baseline_commit: TBD` を、どの SHA で固定するか。
- `ThemePreviewModel.Layer` をネスト型として凍結したが、トップレベル `struct Layer` にするならテストを直す必要がある。

=== REPORT COMPLETE ===
