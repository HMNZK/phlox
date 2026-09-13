---
task: task-40
status: completed
---

## 詰まった点

- 残余マスクを `__DRAW__` 置換のまま拡張すると、基準 blob に無かった新規 `.font(...)` がプレースホルダとして残り、ChatCodeCard 等が再び NG になる。修飾子は削除（strip）しないと比較が成立しない。
- 全域で `FontSize(` を単純検索すると `bodyFontSize(` に誤マッチし、ChatTypography の委譲本文が壊れて残余 NG になる。裸識別子は単語境界付きで除去する必要があった。
- 契約項目 4 は rb 自身のバイト一致を要求するが、今回の作業は PM 承認の rb 修理そのものなので、生産検査の `check_frozen_baseline` では作業ツリー rb 同一性を見ない。`evaluate_frozen_baseline` の rb 不一致検出（selftest 負例「検査自身の改変」）は残した。
- `CodeBlockView` の `.padding(...)` は `check_protected_frozen_attrs` が凍結 blob と文字列比較するため、値は正本と同じでも識別子を `TranscriptTypography.codeContentInset` へ差し替えると NG になる。操作領域 padding は DSSpacing のままにした。

## できた風だが実は未完

- PM 目視ゲート A/B、App xcodebuild、`.claude/verify.sh` 全量は本手順の指定外。GUI は起動していない。
- `CodeBlockView` ヘッダー／コード本文の padding 識別子は DSSpacing.m/s のまま（値は card/code 正本と同一）。コピーボタンの padding は契約どおり未変更。

## 置いた前提

- `TASK40_BASELINE` / `baseline_commit` は `bdbf1d9`。
- マスク拡張は契約 12「描画属性と分類接続」に限定し、操作クロージャ・ID・コピー内容・条件分岐・スクロール処理・コード/差分処理の残余比較は維持する、という PM 裁定を正とした。
- `DisclosureCard` タイトル色は既存 `DisclosureCardPalette`（通常 primary / ツール tool）を維持。
- 料金 `opacity(0.7)`、差分行間 0、枠線、アイコン寸法、AX identifier、LazyVStack 不使用、本文・見出し・箇条書きの `.fixedSize(horizontal: false, vertical: true)` は維持。
- 凍結 Swift 受け入れテストと `tasks/frozen/staged/` は未改変。テスト新規作成なし。
- 並列作業由来の `board.md` / `status/task-41.json` / 未追跡 `AcceptanceHistoryTitleSourcesTests.swift` には触っていない。

## 契約からの逸脱

なし。前任が残余 NG を恐れて見送った項目（段落下 8 / 箇条書き下 4、外側余白の正本接続、履歴ボタンの `@AppStorage`）を接続した。

## レビュー重点

- 本文 15 / 処理要約 15 semibold / 補助 10 が実 View へ届いているか。
- `gap(after:before:)` が親 VStack spacing 0 + ブロック上側 padding のみか。履歴ボタン後 16、処理中・圧縮中の前 8、先頭持ち越し無し。
- Markdown 段落下 8（`withinAnswer`）と箇条書き項目下 4（`metadataGap`）、`.fixedSize` 維持、表へ未波及。
- トランスクリプト外側余白が `transcriptHorizontalInset` / `transcriptVerticalInset`。履歴ボタンが `@AppStorage(ChatFontSettings.scaleKey)` + `adjusted(from: chatScale, by: 0)`。
- Shimmer の Font と pointSize がともに body。差分意味色と行間 0。料金 opacity 0.7。
- rb が操作クロージャ・ID・コピー・条件分岐・スクロール・コード/差分の改変をまだ落とすか。

## rb 修理の内容

マスク拡張（`normalize_allowed_surface` 先頭で両側に適用。新規追加でも残余に残らないよう strip）:

- (a) `import DesignSystem` 行
- (b) `.font(...)` / `.padding(...)` / `.lineSpacing(...)` / `.foregroundStyle(...)` / `.foregroundColor(...)` / `.markdownMargin(...)`、および単語境界付きの `FontSize(` / `FontWeight(` / `ForegroundColor(`
- (c) 既存 `mask_typo_spacing`（`spacing: 2` および `DSSpacing.*` / `TranscriptTypography.*`）
- (d) `@AppStorage(ChatFontSettings.scaleKey)` 行

負例維持の根拠: 上記は描画属性と分類接続だけを消す。`RichMarkdownView("gone")` のようなコピー改変、`.id` / 操作クロージャ / `spacing: 0` / 差分意味色 / スクロール列挙はマスクしない。selftest の既存負例（接続削除・誤役割・子上書き・旧直値・倍率二重適用・gap 二重加算・直前誤参照・先頭持ち越し・gap 倍率・同一回答 24pt・コメントだけ・未使用ヘルパー・`if false`・必須ケース欠落・許可面外残余・color 固定・差分行間 0・意味色・料金 opacity・SHA/HEAD/契約不一致・DashboardViewModel / Package.swift・検査自身の改変）は残し、(a)〜(d) の正例を追加した。

生産検査のみ、承認済み rb 修理のために作業ツリー rb と基準 blob の同一性を見ない。

## 検証原文

### `t40-selftest`

```
t40-selftest: OK（要約未対応）
```

exit 0。コマンド: `~/.agents/scripts/compact-test t40-selftest ruby .claude/scripts/task40-wiring.rb --selftest`

### `t40-rb`

```
t40-rb: OK（要約未対応）
```

exit 0。コマンド: `~/.agents/scripts/compact-test t40-rb env TASK40_BASELINE=bdbf1d9 ruby .claude/scripts/task40-wiring.rb`

### DesignSystem `swift test`

```
✔ Test run with 158 tests in 30 suites passed after 0.086 seconds.
```

exit 0。コマンド: `(cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t40-ds swift test)`

### SessionFeature `swift test`

```
✔ Test run with 901 tests in 112 suites passed after 1.253 seconds.
```

exit 0。コマンド: `(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-sf swift test)`

### DashboardFeature `swift build`

```
t40-dash: OK（要約未対応）
```

exit 0。コマンド: `(cd macos/Packages/DashboardFeature && ~/.agents/scripts/compact-test t40-dash swift build)`

### `git diff --check`

出力なし、exit 0。

GUI は未起動。コミットしていない。

=== REPORT COMPLETE ===
