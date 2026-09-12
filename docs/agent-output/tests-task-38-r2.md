---
status: completed

# task-38 受け入れテスト・配線検査 改訂 r2

HEAD: `26a426b`。製品コード（SettingsView.swift・DesignSystem Sources）は未変更。契約・台帳・仕様は未変更。git commit なし。受け入れテスト Swift は指摘該当なしのため未変更。

## 指摘 1〜7 の対応表

| 指摘 | 対応 | 検査関数（file:line） |
|---|---|---|
| 1 | `body` から `collect_reachable` で実際に呼ばれるヘルパー／struct だけを展開。未使用ヘルパー内の switch/Section は数えない。`if false { }` は `erase_if_false` で除去してから見出しを取る。タブ列挙は TabView 内の `ForEach(SettingsGroup.all)` 直列挙のみ（`.reversed()` / `sorted` / `filter` / `prefix` 等は NG）。`tabItem` クロージャが `group.title` / `group.systemImage` を使うこと。AX は `.accessibilityIdentifier(` の引数が `settings-group-\(group.id)` であること（`help(...)` 置換は NG） | `collect_reachable` `.claude/scripts/task38-wiring.rb:325`、`erase_if_false` `:344`、`reachable_from_body` `:362`、`group_drawing_src` `:369`、`foreach_all_errors` `:381`、`extract_foreach_all_closure` `:405`、`extract_modifier_closures` `:422`、`accessibility_identifier_on_group_id?` `:438`、`check_tab_and_sections` `:1014` |
| 2 | `@AppStorage` を属性・キー・変数名・既定値の宣言単位で切り出し、baseline の同名宣言と `text` 正規化比較。キー交換（両方 `true`）を検出。保護 struct に `AppIconRowView` を追加 | `extract_app_storage_units` `:640`、`check_invariants` `:1158`–`:1189`、`SHA_STRUCTS` `:867`–`:876`（`AppIconRowView` `:874`） |
| 3 | 保存対象（`@AppStorage` 変数の宣言以外の代入、`appUpdater.` 呼び出し／代入、`NSApp.applicationIconImage =`、`UserDefaults` 書き込み、`ThemeStore.` 代入）の箇所集合を baseline と比較。`onAppear` 等の新規代入は集合差分で NG。`SettingsGroup.all` は `[ SettingsGroup(...) , ... ]` リテラルのみ（クロージャ・`print`・イニシャライザ以外の要素は NG） | `storage_write_sites` `:687`、`check_invariants` `:1238`、`check_all_is_literal_inits` `:929`（`check_settings_group` から呼ぶ） |
| 4 | 同名 Section は重複 NG（`section_map` は先勝ちで上書きせず、比較前に重複を報告）。グループ見出し順は `.uniq` しない。Section 外は宣言単位で baseline と一致（`body` のみ分類構造として skip。新ヘルパー名は baseline に無いので許容）。task35 も同じ重複拒否と宣言単位比較（skip は `body` とテーマ3 struct） | task38: `section_title_duplicates` `:223`、`parse_switch_cases` `:277`、`non_section_decl_messages` `:616`、`DECL_SKIP` `:878`、`check_invariants` `:1222`–`:1236`。task35: `section_title_duplicates` `.claude/scripts/task35-wiring.rb:221`、`section_diff_messages` `:245`、`TASK35_DECL_SKIP` `:440`、`non_section_decl_messages` `:442`、本番 `:945`–`:950` |
| 5 | `TASK38_BASELINE` の検証を「HEAD 不一致」から凍結内容へ。① `git merge-base --is-ancestor` で HEAD の祖先（HEAD 自身可）② `git show` で基準時点に SettingsGroup.swift 不在かつ SettingsView に TabView 無し ③ `git show <sha>:<path>` と作業ツリーの受け入れテスト／rb が同一。リテラル `HEAD`・ブランチ名は従来どおり拒否。SHA が HEAD と一致しても未コミット実装の検査は拒否しない | `baseline_env_errors` `:880`、`check_frozen_baseline` `:898`、`workdir_matches_git_blob?` `:736`、本番 `:1646`–`:1652` |
| 6 | 負例は正例 fixture に違反を1つだけ加えたもの。本番の `check_tab_and_sections` / `check_invariants` / `check_settings_group` で NG を確認（重複分岐・並べ替え・未使用ヘルパー・未使用コード偽装・`if false` 包み・reversed・help 置換・キー交換・onAppear 書き込み・all クロージャ）。task35 の selftest も `section_diff_messages` / `non_section_decl_messages` を使用 | task38 `run_selftest` `:1425` 以降（重複分岐 `:1505`、並べ替え `:1514`、未使用ヘルパー `:1518`、`if false` `:1526`）。task35 selftest `:632`–`:679` |
| 7 | 対象外（契約側で対応済み。rb 変更なし） | — |

## コマンド原文

### `ruby .claude/scripts/task38-wiring.rb --selftest`

```
task38-wiring --selftest: OK
```

exit 0。負例はいずれも本番関数が主張どおりの NG を返してから OK。所要約 59s。

### `TASK38_BASELINE=$(git rev-parse --short HEAD) ruby .claude/scripts/task38-wiring.rb`

`git rev-parse --short HEAD` は `26a426b`。未実装のため RED（exit 1）。

```
task38-wiring: NG 基準時点の受け入れテストが現在と同一ではない
task38-wiring: NG 基準時点の rb 自身が現在と同一ではない
task38-wiring: NG macos/Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift が存在しない
task38-wiring: NG SettingsGroup.swift が存在しない
task38-wiring: NG SettingsView の body に TabView が無い
task38-wiring: NG SettingsView が SettingsGroup.all を使っていない（モデル未使用）
task38-wiring: NG タブ選択の @State 初期値が "general" ではない
task38-wiring: NG グループ general の描画分岐を切り出せない
task38-wiring: NG グループ appearance の描画分岐を切り出せない
task38-wiring: NG グループ agents の描画分岐を切り出せない
task38-wiring: NG 接続グループの描画分岐で MobileTokenSection を呼んでいない
task38-wiring: NG グループ advanced の描画分岐を切り出せない
```

凍結内容のうち ①祖先（HEAD 自身）②基準時点で SettingsGroup 不在・SettingsView に TabView 無し、は NG になっていない（通過）。

「基準時点の rb 自身が現在と同一ではない」は `.claude/` が gitignore のため `git show 26a426b:.claude/scripts/task38-wiring.rb` が失敗する。凍結コミットで `git add -f .claude/scripts/task38-wiring.rb` すればこの 1 項目は通る。

「基準時点の受け入れテストが現在と同一ではない」も、`AcceptanceSettingsGroupingModelTests.swift` が未追跡のため `git show` が失敗する。同じく凍結コミット（通常の `git add`）後に通る。指示は rb の 1 項目としたが、契約③は両方を見るため現状は 2 項目が同一性 NG。

実装不在の NG（SettingsGroup / TabView / SettingsGroup.all / 描画分岐）はハーネス欠陥ではなく未実装 RED。AX は TabView 内 ForEach クロージャで見るため、TabView 不在時は「タブ側に identifier が無い」を重ねて出していない。

### `ruby .claude/scripts/task35-wiring.rb --selftest`

```
task35-wiring --selftest: OK
```

exit 0。移動 OK・内容改変 NG・同名重複 NG・`body` TabView 化は宣言単位で許容・header 改変 NG を本番関数で確認。

### `TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb`

```
task35-wiring: OK
```

exit 0。

### `cd macos/Packages/DesignSystem && swift build --build-tests`

テストファイルは指摘該当なしのため未変更。再確認せず（前回 r1 の SettingsGroup 不在 RED がそのまま）。

## 判断に迷った点

1. **受け入れテストの同一性 NG。** 指示は rb の 1 項目だけ未コミット NG とし、他の凍結内容は通るとした。契約③はテストと rb の両方を `git show` 比較する。テストも未追跡なので現状は 2 項目が同一性 NG。凍結後はテストは通常 add、rb は `git add -f` で通る。
2. **未実装時の AX NG。** 到達経路検査に合わせ、identifier は TabView 内 ForEach クロージャでだけ見る。TabView が無い未実装 RED では AX 欠落を別行で出さない。TabView があるのに `help(...)` へ置換した場合は selftest で NG を確認済み。
3. **`body` を宣言比較から外す。** 指摘4は Section 外を狭めない一方、指摘1の TabView 化は `body` を変える。baseline にある宣言は一致、`body` と新規グループヘルパーだけ許容、とした。
4. **task35 の skip。** 094f86a 以降の SettingsView 差分は ThemeRowView / ThemeAppPreview / ThemeSwatchStrip。`AppIconRowView` は差分に含まれないので宣言比較の対象のまま（指摘2の task38 保護とは別）。`TASK35_BASELINE=094f86a` は OK。
5. **`extract_var_body`。** 名前の後ろの「最初の `{`」だと `@AppStorage` 変数が後続の Binding/`body` を本体として拾い、到達展開が肥大化して selftest が数十秒になった。型注釈の直後に `{` がある場合だけ本体とするよう狭めた。

=== REPORT COMPLETE ===
