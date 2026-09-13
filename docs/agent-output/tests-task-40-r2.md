指摘 1〜7 を契約の裁定どおり直しました。製品コード・契約・台帳は触っていません。コミットもしていません。

**Swift（退避先のみ）**
- `font(for:scale:)` の独立期待 `Font`（weight/design）
- `color(for:)` の独立期待 `DSColor`
- Font/Color は既存 API どおり Equatable

**配線検査**
- 残余比較の正例を「凍結製品 → 契約準拠製品」に変更し、委譲・`typographyRole`・DisclosureCard 外側 padding 除去・H4〜6 字体追加だけを正規化
- `body` 経由のヘルパー／`chatMarkdownTheme` 到達と要素ごとの必須修飾。struct 内未使用ヘルパーは負例
- 実 `transcriptStack` の直前ブロック・先頭持ち越し・gap 二重適用・倍率再適用
- 意味色・差分行間 0・操作 padding・料金 opacity 0.7 の凍結比較。数値×倍率と直値 padding/spacing を検出
- selftest は準拠 fixture の単一違反、解決可能な異なる SHA、本番と同じ構成
- 変更禁止に `DashboardViewModel.swift` と各 `Package.swift` を追加

```
ruby .claude/scripts/task40-wiring.rb --selftest
task40-wiring --selftest: OK
```

報告は `docs/agent-output/tests-task-40-r2.md` です。`swift build --build-tests` は指示どおり未実行で、正位置へもコピーしていません。
e/役割を検査。struct 内未使用ヘルパーを負例に | `collect_view_reachable`（`:605`）、`check_markdown_heading_fonts`（`:670`）、負例「未使用ヘルパー」（`:2047`） |
| 3 | DesignSystem テストに独立リテラルの期待 `Font` / `DSColor` を追加（Equatable）。rb 正例の `font` は weight/design を使い、`color` は 4 色を返す。weight/design 無視と primary 固定を単一変異 | `fontMatchesIndependentSystemFont` / `colorMatchesIndependentDSColor`（staged 単体 `:143` / `:238`）、rb `:533` と負例 `:2066` / `:2073` |
| 4 | `transcriptStack` の実境界計算を検査。常に `after: nil`、先頭の `index==0 ? nil` 欠落、親 Stack と gap の二重加算、`gap * scale` で NG。Swift の系列リテラルは正本×`typographyRole` の値検査として維持 | `check_gap_application`（`:870`）、負例 `:2004` / `:2010` / `:1998` / `:2019` |
| 5 | 変更可能な描画属性を要素単位に限定。意味色・差分行間 0・CodeBlock 操作 padding・料金 `opacity(0.7)` は凍結値と比較。一般の数値×倍率と対象直値 padding/spacing を検出（差分幅・表セルの既存 layout scale は例外） | `check_protected_frozen_attrs`（`:1165`）、`numeric_times_scale?`（`:803`）、負例 `:2077` / `:2081` / `:2085` |
| 6 | 準拠 fixture の一箇所だけを変える。凍結テスト改変は 2 ファイル中 1 件だけ。契約 SHA 不一致は `HEAD` と `HEAD~1` の解決済み SHA。製品検査は `inspect_like_prod`（本番と同じ `inspect_product`＋凍結＋変更禁止 blob） | `inspect_like_prod`（`:1941`）、SHA 不一致 `:2170` 付近 |
| 7 | 変更禁止に `DashboardViewModel.swift` と `macos/Packages/*/Package.swift` を追加し固定 SHA 比較。改変を負例に | `UNCHANGED_PATHS` `:263`、`package_swift_paths` `:266`、負例 `:2188` |

指摘 8〜12 は契約側裁定のため本修正の対象外。

## selftest 原文

```
$ ruby .claude/scripts/task40-wiring.rb --selftest
task40-wiring --selftest: OK
```

exit 0。

=== REPORT COMPLETE ===
