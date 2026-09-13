---
task: task-48
status: completed
---

敵対レビュー `docs/agent-output/task48-acceptance-adversarial.md` の採択項目（MUST1・2、MUST3 の既存 Swift 3 本、HIGH4〜8、MED10・11）を反映した。製品コード・契約・台帳は未変更。コミットしていない。受け入れテストは `tasks/frozen/staged/AcceptanceUIWordingTests.swift` のまま（実パスへコピー・移動していない）。

## 指摘ごとの反映

| 指摘 | 反映 | 該当行 |
|---|---|---|
| MUST1 | 通常メニューから `permissionLabel`・`modeLabel` 見出し要求を外し、選択中 `ComposerControlChip`（`planOption` / `approvalLabel`）と省略メニュー見出しだけを検査。正例 fixture も同じ実在位置 | rb VIEW_SITES `:586`–`:597`、DISPLAY_BINDINGS `:626`、正例 chip `:1605` |
| MUST2 | `collect_reachable` を struct 優先＋ファイル直下ヘルパーへ拡張。正例 Markdown は `theme` → `chatMarkdownTheme`。未呼び出しヘルパーを負例に | rb `:307` / `:350`、正例 `:1416` / `:1425`、負例 `:1891` |
| MUST3 | `task13-wiring.rb` は PM 裁定どおり未改訂。既存 Swift 3 本は旧英語逐語を言語引数付き日英期待へ。項目集合・`value`・`isPlan`・計算・ブランチ操作は保持。権限表示名は固定しない。現行 API のまま GREEN | ComposerModeMenu `:30`–`:65`、Popover `:16`–`:55`（実パス DashboardFeatureTests）、Grid `:47`–`:64` |
| HIGH4 | `Text`/`Label`/`help`/`AX`/`ComposerControlChip`/`Menu` の引数キーを固定。effort 5 キーを通常・省略の両方へ。キー交換・AX 分岐逆転・未呼出しクロージャを負例に | rb VIEW_SITES `:590`–`:594`、DISPLAY_BINDINGS `:618`、`check_copy_ax`、負例 `:1914` / `:1924` / `:1934` |
| HIGH5 | 各 struct の `languageCode` を Environment locale まで追跡。TurnCost・構造化セル・省略メニュー・`ComposerContextIndicator` を追加。`themeCacheKey` に言語必須。プロパティ固定とキャッシュ欠落を負例に | rb `:483` / `:835` / `:888`–`:905`、正例 Indicator `:1543`、負例 `:1944` / `:1954` |
| HIGH6 | `respond`・`copyAndShowFeedback`・`selectCodexModeOption`・送信本体を `normalize_code` で baseline 比較。権限タイトル文字列は比較しない。空 `respond` と Plan 解除削除を負例に | rb `:1113`、負例 `:1964` / `:1971` |
| HIGH7 | トークン使用量引数・金額供給式・コマンド欠損条件・出力条件を baseline 比較。各 1 変更の負例 | rb `:1157`、負例 `:1981` / `:1991` / `:2001` / `:2011` |
| HIGH8 | 新設 `UIWording.swift` 以外の既存 blob 欠落はパス付き即 NG。単一欠落の selftest | rb `:491` / `:2053`、負例 `:2017` |
| MED10 | 同一呼出し同士・キー同士・期待値表だけの禁止語検査を削除。言語切替後は独立リテラル比較のみ | staged `:196`–`:208` / `:235`–`:251` / `:272`–`:284` |
| MED11 | `@testable import DesignSystem` を `import DesignSystem` に変更 | staged `:15` |

## selftest 原文

```
$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK
```

exit 0。

## parse 原文

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceUIWordingTests.swift
```

診断出力なし。`PARSE_EXIT:0`。型検査・パッケージビルドは未実行（指示どおり。PM が再凍結時に実パスへ戻してコンパイル RED を確認する）。

## 既存 3 テスト GREEN 原文

実パスはいずれも `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/`（`AcceptanceContextPopoverBranchTests.swift` は SessionFeatureTests には無い）。`UIWording` 未実装のため英語期待は現行製品に一致。

```
$ cd macos/Packages/DashboardFeature && swift test --filter 'ComposerModeMenuAcceptanceTests|GridComposerSettingsAcceptanceTests|popoverText_|branchSwitcher_|tokenText'
Test run with 15 tests in 2 suites passed after 0.391 seconds.
```

exit 0。

## 見送った点と理由

- MED9（ADR 0147 サブタイトル）: PM 裁定。単独コマンドセルの「実行中／出力あり」は現状維持。ADR 追記はフェーズ 5。検査側では翻訳のための復活・削除を要求していない。
- MUST3 の `task13-wiring.rb`: PM 裁定。task-13 の着手時検査で後続に適用しない。
- 既存 3 テストへ製品関数の `languageCode:` 引数は足していない。現行 `lines(usedTokens:windowTokens:)` / `composerModeOptions(for:codexProfileIDs:)` にその引数が無く、足すとコンパイル RED になり「現行製品で GREEN」に反する。日英期待はテスト側ヘルパーが持ち、製品呼び出しは現行英語出力と `languageCode: "en"` 期待を照合する。
- Grid の `composerModeOptionsForLanguage` は現行 API へ転送する（`languageCode` は将来の受け渡し口）。`isPlan` 検査のみで権限表示名は固定しない。
- 製品コード・契約・台帳・他担当の `tasks/frozen/staged/` 他ファイル・他 `taskNN-wiring.rb`・Sources は未変更。受け入れテストは退避先のまま。

=== REPORT COMPLETE ===
