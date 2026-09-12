---
task: tests-task-35-36
status: completed
---
## 作成したファイルとテスト名一覧

- `tasks/frozen/staged/AcceptanceThemePreviewModelTests.swift`（最終配置先は `macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/`。PM が移す）
  - `phloxLayerRGBAndOpacityAreFrozen` — Phlox の背景・主文字・選択行・入力面・枠を字面で固定する
  - `phloxTerminalSwatchesAreFrozen` — Phlox の色帯 8 色と順序を字面で固定する
  - `githubLightBackgroundAndInputBorder` — GitHub Light の背景は白、inputBorder は opacity 0.86 で RGB は同テーマの textPrimary
  - `labelsIdentityAndMarker` — 文言 5 種、themeID/name、マーカー色を固定する
  - `tenRegisteredThemesMapFromCandidate` — 登録 10 テーマの ID・名前・順序を固定し、候補由来の背景・文字・選択行・枠・色帯へ写像する
  - `successiveMakesDoNotLeakPreviousCandidate` — Phlox → GitHub Light → Phlox の呼び出しで前の候補が混入しない
- `tasks/frozen/staged/AcceptanceAgentConsoleNavigationModelTests.swift`（最終配置先は `macos/Packages/AgentConfigKit/Tests/AgentConfigKitTests/Acceptance/`。PM が移す）
  - `agentRawValuesAndDisplayNames` — agent の rawValue と表示名を固定する
  - `nineteenSectionIDsAndTitlesMatchLiterals` — 3 対象の項目 ID・title・順序を 19 組のリテラル配列と比較する
  - `nineteenSectionUnionIsUnique` — 19 項目の和集合は 19 件で重複なし
  - `nilSelectionResolvesToStatus` — selection=nil なら各 agent の状態項目になる
  - `belongingSelectionIsKept` — 所属する各項目を渡すとそのまま保持する
  - `foreignSelectionResetsToStatus` — 他 agent 所属の selection は状態へ戻る
  - `locationTextExamplesAndPickerLabel` — locationText の例と Picker ラベルを固定する
  - `configLocationDetailAndSymbolNames` — configLocation・detail・symbolName を元コード由来のリテラル表で固定する
  - `statusSummaryFourCombinations` — StatusSummary の Bool 2 入力 4 組で 4 つの表示フィールドと CLI 詳細ラベルをリテラル比較する
- `.claude/scripts/task35-wiring.rb`
- `.claude/scripts/task36-wiring.rb`
- `docs/agent-output/tests-task-35-36.md`（本報告）

製品コードは変更していない。新 API 未実装のため、受け入れテストはコンパイル RED、配線検査は現状コードで exit 1 が正しい。

## 契約から読み取れず自分で決めた点

- 明色 4 テーマ（`catppuccin-latte` / `solarized-light` / `github-light` / `phlox-light`）は AppTheme の bg 実値から相対輝度 0.5 以上と判断し、10 テーマ写像の inputBorder 分岐をこの ID 集合で固定した。テストから `relativeLuminance`（internal）は呼ばない。
- GitHub Light の textPrimary は `fromPalette` のグレースケール＋補正で導出されるため、inputBorder の RGB は `AppTheme.githubLight.textPrimary` との等値だけを要求し、補正後の整数 RGB は字面固定しない。
- Phlox の `currentMarker` は契約成功基準 1 に数値が無いので、`AppTheme.phlox.accent` の実値 `RGB(217, 119, 87)`（`claudeCoral` = `0xD9,0x77,0x57`）で固定した。
- `ThemePreviewModel.Layer` の memberwise init は public と書いていないため、テストは `Layer(...)` を組み立てず `.rgb` / `.opacity` を読む。
- 配線の Layer 適用は契約の `.rgb.color.opacity(.opacity)` を compact 一致（`model.selectedRow.rgb.color.opacity(model.selectedRow.opacity)` など）で固定した。
- `ThemeAppPreview` の不透明下地は `model.background.color` が 2 回以上あることを要求した（選択行と入力欄）。
- SettingsView の「テーマ行・見本以外」は `ThemeRowView` / `ThemeAppPreview` / `ThemeSwatchStrip` を括弧対応で除いた残りを baseline SHA と compact 比較する。HEAD 自己比較は使わない。
- 対象 Picker は契約の「標準の menu 形式」を `.pickerStyle(.menu)` の存在として固定した。
- 行の title / help / 選択 trait / section AX id は `sidebar` 変数ではなく `AgentConsoleSectionRow` 本文を見る。`selection = section` は sidebar 側の ForEach クロージャに置く前提。
- WindowView の `init` は `func init` ではないので `init(` を括弧対応で切り出す。`isError: true` は `banner` 関数本文を見る。
- DisclosureGroup は標準の `DisclosureGroup(title, isExpanded:) { content }` を第一 trailing closure として切り出す。

## 契約と実コードの差異

- Phlox の契約数値は実コードと一致した。`background=(17,17,17)`（`0x11`）、`textPrimary=(230,230,230)`（`0xE6`）、`sidebarSelectedOpacity=0.10`、色帯 8 色は `terminalBackground` + `ansi[1...6]` + `terminalForeground` の実値どおり。
- GitHub Light の `background=(255,255,255)` も一致（`fromPalette` が `bg.grayscale` するが白のグレースケールは白のまま）。`preferredColorScheme` の閾値 `relativeLuminance >= 0.5` により inputBorder は明色枝（opacity 0.86、RGB=textPrimary）。
- 契約 `Tokens.swift:102,157` は行がずれている。選択面 10% は `fillSelected`（109 行）と `sessionRowSelected`（164 行）。102 行は `surfaceElevated`、157 行はコメント。配線検査は行番号ではなく compact したレシピ文字列で固定した。
- 契約 `AppTheme.swift:245,271` の 271 行は `terminalBackground`。ANSI 配列本体は 273 行以降。値自体の食い違いは無い。
- `AppTheme.sidebarSelectedOpacity` と `RGB.relativeLuminance` は public ではない。受け入れテストは 0.10 / 明色 ID 集合の字面で代替した。

## 現状コードに対する rb 実行結果（原文）

`ruby -c .claude/scripts/task35-wiring.rb` → Syntax OK  
`ruby -c .claude/scripts/task36-wiring.rb` → Syntax OK  

コマンド: `TASK35_BASELINE=HEAD ruby .claude/scripts/task35-wiring.rb; TASK36_BASELINE=HEAD ruby .claude/scripts/task36-wiring.rb`  
（個別の exit はどちらも 1。`;` 連結のシェル終了コードも 1）

```
task35-wiring: NG macos/Packages/DesignSystem/Sources/DesignSystem/ThemePreviewModel.swift が存在しない
task35-wiring: NG ThemeRowView 本文に Text(model.appLabel) が無い
task35-wiring: NG ThemeRowView 本文に Text(model.terminalLabel) が無い
task35-wiring: NG ThemeRowView 本文の ThemePreviewModel.make( が 0 回（期待 1）
task35-wiring: NG ThemeRowView 本文に ThemePreviewModel.make( が無い
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
task36-wiring: NG sidebar に .pickerStyle(.menu) が無い
task36-wiring: NG sidebar に accessibilityIdentifier("agent-console-agent-picker") が無い
task36-wiring: NG Picker の set が make(..., selection: nil) を呼んでいない
task36-wiring: NG Picker の set に AgentConsoleNavigationModel.make(agent: が無い
task36-wiring: NG sidebar に navigation.selectedSection == section が無い
task36-wiring: NG sidebar に selection = section が無い
task36-wiring: NG AgentConsoleSectionRow に .help(section.detail) が無い
task36-wiring: NG AgentConsoleSectionRow に常時表示の Text(section.detail) が残っている
task36-wiring: NG AgentConsoleSectionRow に accessibilityIdentifier("agent-console-section-\(section.rawValue)") が無い
task36-wiring: NG WindowView に Text(navigation.locationText) が無い
task36-wiring: NG WindowView に accessibilityIdentifier("agent-console-location") が無い
task36-wiring: NG detail の switch が navigation.selectedSection ではない
task36-wiring: NG messageBar の switch が navigation.agent ではない
task36-wiring: NG ClaudeStatusPane に @State private var showsCLIDetails = false が無い
task36-wiring: NG ClaudeStatusPane に AgentConsoleStatusSummary.make( が無い
task36-wiring: NG ClaudeStatusPane に summary.availabilityText が無い
task36-wiring: NG ClaudeStatusPane に summary.availabilityDetail が無い
task36-wiring: NG ClaudeStatusPane に summary.configurationText が無い
task36-wiring: NG ClaudeStatusPane に summary.configurationDetail が無い
task36-wiring: NG ClaudeStatusPane の先頭表示順検査に availabilityText / summaryTiles が足りない
task36-wiring: NG ClaudeStatusPane の DisclosureGroup を括弧対応で切り出せない
task36-wiring: NG CodexStatusPane に @State private var showsCLIDetails = false が無い
task36-wiring: NG CodexStatusPane に AgentConsoleStatusSummary.make( が無い
task36-wiring: NG CodexStatusPane に summary.availabilityText が無い
task36-wiring: NG CodexStatusPane に summary.availabilityDetail が無い
task36-wiring: NG CodexStatusPane に summary.configurationText が無い
task36-wiring: NG CodexStatusPane に summary.configurationDetail が無い
task36-wiring: NG CodexStatusPane の先頭表示順検査に availabilityText / summaryTiles が足りない
task36-wiring: NG CodexStatusPane の DisclosureGroup を括弧対応で切り出せない
task36-wiring: NG CursorStatusPane に @State private var showsCLIDetails = false が無い
task36-wiring: NG CursorStatusPane に AgentConsoleStatusSummary.make( が無い
task36-wiring: NG CursorStatusPane に summary.availabilityText が無い
task36-wiring: NG CursorStatusPane に summary.availabilityDetail が無い
task36-wiring: NG CursorStatusPane に summary.configurationText が無い
task36-wiring: NG CursorStatusPane に summary.configurationDetail が無い
task36-wiring: NG CursorStatusPane の先頭表示順検査に availabilityText / summaryTiles が足りない
task36-wiring: NG CursorStatusPane の DisclosureGroup を括弧対応で切り出せない
```

## 契約の疑問点・矛盾（PM 宛）

- `Tokens.swift:102,157` の行アンカーが現行とずれている。検査対象のレシピは 109 / 145-147 / 164 行。凍結前に契約の行を直すか、行ではなく記号名を正本にするか。
- `RGB.relativeLuminance` が internal のままなので、受け入れテストは輝度を再計算できない。明色 4 ID の固定で代替したが、テーマ追加や bg 変更で閾値を跨ぐとテスト側の集合が陳腐化する。public にするか、この 4 ID で凍結してよいか。
- GitHub Light の textPrimary 整数値を字面固定しなかった（導出値）。補正ロジック変更を見本テストで落とすなら、補正後 RGB を契約に書いてテストへリテラル追加が必要。
- 配線は DisclosureGroup の第一 trailing closure を本体とみなす。`DisclosureGroup { label } content: { ... }` 二段クロージャだと version/path 検査が落ちる。実装側の形を契約で一意にしてよいか。
- `.pickerStyle(.menu)` を必須にした。macOS 既定が menu でも modifier 無しで通したいなら契約追記が要る。
- `ThemePreviewModel.Layer` に public init が契約へ明示されていない。プロパティ比較で足りる前提。不足なら契約に `public init(rgb:opacity:)` を足す。

=== REPORT COMPLETE ===
