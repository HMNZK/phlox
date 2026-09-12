---
status: completed

# task-38 受け入れテスト・配線検査（凍結用 RED）

HEAD: `374249e`。製品コード（SettingsView.swift・DesignSystem Sources）は未変更。契約・台帳・仕様は未変更。git commit なし。

## 作成ファイル

| パス | 内容 |
|---|---|
| `macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceSettingsGroupingModelTests.swift` | 成功基準 1。契約リテラルの 5 グループ表と 14 Section ID。`SettingsGroup.all` と比較。期待値は実装から生成しない |
| `.claude/scripts/task38-wiring.rb` | 成功基準 2。`--selftest` 付き。`TASK38_BASELINE` 必須・HEAD リテラル/実装後自己比較禁止 |
| `.claude/scripts/task35-wiring.rb` | PM 決定 1。SettingsView の残余丸ごと比較を Section 単位内容比較へ。テーマ見本・製品配色検査は維持。`--selftest` に移動 OK / 内容改変 NG を追加 |

`.claude/` は `.gitignore` されている。`task35-wiring.rb` は既に tracked。`task38-wiring.rb` は新規のため、凍結コミット時は `git add -f .claude/scripts/task38-wiring.rb` が必要。

## コマンド原文

### `ruby .claude/scripts/task38-wiring.rb --selftest`

```
task38-wiring --selftest: OK
```

exit 0。

### `TASK38_BASELINE=$(git rev-parse --short HEAD) ruby .claude/scripts/task38-wiring.rb`

未実装のため RED（exit 1）。`git rev-parse --short HEAD` は `374249e`。

```
task38-wiring: NG macos/Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift が存在しない
task38-wiring: NG SettingsGroup.swift が存在しない
task38-wiring: NG SettingsView の body に TabView が無い
task38-wiring: NG SettingsView が SettingsGroup.all を使っていない（モデル未使用）
task38-wiring: NG settings-group-* の AX identifier が無い
task38-wiring: NG タブ選択の @State 初期値が "general" ではない
task38-wiring: NG グループ general の描画分岐を切り出せない
task38-wiring: NG グループ appearance の描画分岐を切り出せない
task38-wiring: NG グループ agents の描画分岐を切り出せない
task38-wiring: NG 接続グループの描画分岐で MobileTokenSection を呼んでいない
task38-wiring: NG グループ advanced の描画分岐を切り出せない
```

SettingsGroup 不在・TabView 不在・identifier 不在が出ている。ハーネス欠陥ではない。

### `ruby .claude/scripts/task35-wiring.rb --selftest`

```
task35-wiring --selftest: OK
```

exit 0。

### `TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb`

```
task35-wiring: OK
```

exit 0。task-35 実装以降の ThemeRowView / ThemeAppPreview / ThemeSwatchStrip 差分は Section ブロック外のため除外された。既存のテーマ見本・製品配色検査も通過。

### `cd macos/Packages/DesignSystem && swift build --build-tests`

RED。`SettingsGroup` 不在によるコンパイルエラー（代表行）:

```
[4/6] Compiling DesignSystemTests AcceptanceSettingsGroupingModelTests.swift
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceSettingsGroupingModelTests.swift:44:17: error: cannot find 'SettingsGroup' in scope
 42 |     @Test("グループ数が 5 で、id / title / systemImage / sectionIDs の順序が契約表と一致する")
 43 |     func fiveGroupsMatchFrozenTable() {
 44 |         #expect(SettingsGroup.all.count == 5)
    |                 `- error: cannot find 'SettingsGroup' in scope
```

以降も同ファイルの `cannot find 'SettingsGroup' in scope` が続く。exit 1。

### 既存テストが壊れていないこと

`AcceptanceSettingsGroupingModelTests.swift` を一時的に `.swift.bak` へ退避して `swift test`:

```
✔ Test run with 143 tests in 28 suites passed after 0.089 seconds.
```

green。退避は `.swift` に戻した（確認: 当該ファイルが Acceptance ディレクトリに存在）。

## 契約との対応表

### 凍結表「グループ順序と所属」（成功基準 1 + 配線）

| 順序 | id | title | systemImage | sectionIDs | テスト | rb |
|---|---|---|---|---|---|---|
| 1 | `general` | `一般` | `gearshape` | `language`, `sessions`, `notifications`, `updates` | `expectedGroups[0]` と `SettingsGroup.all[0]`。`map(\.id/title/systemImage)` の先頭 | `GROUP_ORDER[0]`、`GROUP_TITLES[0]`、`GROUP_IMAGES[0]`、`GROUP_SECTION_TITLES["general"]` → 見出し 言語/セッション/通知/アップデート |
| 2 | `appearance` | `外観` | `paintpalette` | `theme`, `app-icon` | `expectedGroups[1]` | 同上 + 見出し 外観/アプリアイコン |
| 3 | `agents` | `エージェント` | `wrench.and.screwdriver` | `permissions`, `agent-management` | `expectedGroups[2]` | 見出し 権限/エージェント |
| 4 | `connection` | `接続` | `network` | `mobile-connection`, `paired-devices` | `expectedGroups[3]` | 接続分岐で `MobileTokenSection` を1回。内部見出し モバイル接続/接続済みの端末 |
| 5 | `advanced` | `詳細` | `slider.horizontal.3` | `discussion`, `usage`, `privacy`, `about` | `expectedGroups[4]` | 見出し チームビュー討論/使用量/プライバシー/このアプリについて |

グループ数 5、ID/title/systemImage の配列比較、`sectionIDs` の順序一致は `fiveGroupsMatchFrozenTable`。初期グループ `general` は `groupIDsAreUniqueAndInitialIsGeneral`（`all.first?.id`）。繰り返し取得は `repeatedAllReadsAreEqual`。`requireEquatable` / `requireIdentifiable` は `modelIsIdentifiableEquatableAndSendable`。

### 凍結表「14 Section ID」（成功基準 1 の和集合）

リテラル `expectedSectionIDs`（theme … about）。連結は `expectedGroups.flatMap(\.sectionIDs)`（実装の `all` から作らない）。`fourteenSectionIDsAreUniqueUnion` で件数 14・`Set` 14・実装の連結と一致・集合一致。

rb 側の見出しリテラル `ALL_SECTION_TITLES` が同じ 14 件（現状見出し文字列）。欠落・契約外見出し・所属順を `check_tab_and_sections` が拒否。

### 各 Section のコントロール・footer（成功基準 2）

| Section ID | 見出し | rb の検査箇所 |
|---|---|---|
| `theme` | 外観 | `SECTION_CONTROLS`（ForEach(ThemeStore.all), ThemeRowView）。footer 契約文。struct `ThemeRowView`/`ThemeAppPreview`/`ThemeSwatchStrip` を baseline と正規化比較 |
| `app-icon` | アプリアイコン | ForEach(AppIconStore.all), AppIconRowView。footer |
| `language` | 言語 | Picker 選択肢 システム→日本語→English と Label。footer なし（新設拒否） |
| `sessions` | セッション | チャット→ターミナル→Label。footer |
| `discussion` | チームビュー討論 | 3 TextField、自由発言→ラウンドロビン→スケジューラ Label。footer |
| `permissions` | 権限 | ForEach(agentCatalog.allDescriptors, id: \.ref), BypassToggleRow。footer。struct SHA |
| `mobile-connection` | モバイル接続 | TextField 端末名、QR Label。footer。表示条件 `showsSettingsConnectionSection` |
| `paired-devices` | 接続済みの端末 | ForEach(viewModel.devices), MobileDeviceRow。条件 `!viewModel.devices.isEmpty`。footer なし |
| `notifications` | 通知 | 2 Toggle Label と Button("通知テスト")。footer なし |
| `usage` | 使用量 | 4 Toggle Label。footer |
| `agent-management` | エージェント | Label エージェント管理を開く。footer。`openWindow(id: AgentConsoleCommands.windowID)` |
| `privacy` | プライバシー | URL `https://phlox.cc/privacy` と Label。footer なし |
| `updates` | アップデート | 自動確認 Label、今すぐ確認、disabled。footer なし |
| `about` | このアプリについて | 3 LabeledContent。footer なし |

8 footer は `SECTION_FOOTERS`。残り 6 は `NO_FOOTER_TITLES`。

### 成功基準 2 の検査項目

| 項目 | 実装 |
|---|---|
| 1. 字句と構造 | `protect_strings` → コメント除去 → `extract_balanced`。URL 内 `//`・補間・文字列中括弧を selftest |
| 2. タブと Section | body の `TabView`、`SettingsGroup.all`、AX `settings-group-<id>`（タブ側。本文だけは NG）、`@State` 初期値 `"general"`、所属順、`MobileTokenSection` 1 回 |
| 3. 欠落・変更防止 | 14 見出し・コントロール表・footer。`TASK38_BASELINE` の同見出し Section を空白正規化（文字列内空白は保持）して比較。Binding / `@AppStorage` / 独自 View 内部 / `.frame(520,640)` / Form 修飾 |
| 4. 表示時書き込み禁止 | SettingsGroup は標準ライブラリのみ。`@SceneStorage` 拒否。body/init からの UserDefaults 書き込み拒否。既存 action は baseline 比較で許可 |
| 5. 固定基準 | 未設定 NG。リテラル `HEAD`・非 SHA（ブランチ名）NG。実装後に baseline==HEAD なら自己比較 NG。フォールバックなし |

### PM 決定 1（task35）

`remainder_without_theme_structs` による SettingsView 丸ごと比較を、見出しリテラルで Section を切り出す内容比較へ置換。Form 間移動・順序変更は `section_contents_match?` が同一内容なら OK。内容改変は NG。`MobileTokenSection(viewModel:)` 呼び出しの存在を確認。テーマ見本（ThemeRowView 本文・make 配線・ZStack 下地・色帯）と Tokens/AppTheme/ChatComposer/GridChatColumn の製品配色検査は維持。`--selftest` に「Section 移動は OK」「Section 内容改変は NG」。

## 判断に迷った点

1. **凍結時に `TASK38_BASELINE=$(git rev-parse --short HEAD)` を許すか。** 契約は HEAD 自己比較を禁止する。リテラル `HEAD` と「実装済み（SettingsGroup.swift があり TabView がある）かつ baseline SHA が HEAD」を拒否し、未実装の短 SHA は通して未実装 NG を出す。凍結確認コマンドと実装後の自己比較防止を両立するため。
2. **14 Section ID リストの順序。** 成功基準 1 は「集合が一致」。連結順はグループ表の `sectionIDs` 連結（language 始まり）であり、現状順表（theme 始まり）とは違う。集合比較とグループ内順序の両方をテストし、現状順配列そのものとの順序一致は要求しない。
3. **コントロール針の順序。** Picker は実ソースでは選択肢クロージャが先、`label:` が後。契約表の「Label が先」に合わせると実ファイルが RED になるため、検査順は SettingsView の字句順にした。欠落検出は維持。
4. **接続グループの所属検査。** 内部 2 Section は `MobileTokenSection` 内に残る。接続分岐では呼び出し 1 回を要求し、見出しはファイル全体の Section 切り出しで固定する。
5. **task35 の比較単位。** 094f86a 以降の差分はテーマ 3 struct のみ。Section 本体（ForEach + ThemeRowView 呼び出し）は変わらないので Section 比較は HEAD で OK。これがテーマ見本検査を残したまま UX-06 の Form 移動を許す、という PM 決定の意図と一致する。
6. **期待値の出所。** テストの `expectedGroups` / `expectedSectionIDs` と rb の定数は契約表からの転記。`SettingsGroup.all` や実装ソースから期待配列を作っていない。

=== REPORT COMPLETE ===
