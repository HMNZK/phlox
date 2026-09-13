---
task: task-48
status: completed
---

task-48（UX-10a）の受け入れ検査を新規作成した。製品コード・契約・台帳は未変更。コミットしていない。他担当の未コミットファイルには触っていない。

## 作成物

- `tasks/frozen/staged/AcceptanceUIWordingTests.swift`（実パス `macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceUIWordingTests.swift`。先頭コメントに実パスを記載。Swift Testing。`UIWording` 未実装のコンパイル RED が正常）
- `.claude/scripts/task48-wiring.rb`（`TASK48_BASELINE` 必須、契約 `baseline_commit` 一致、HEAD/ブランチ名拒否、祖先確認、基準に `UIWording.swift` 不在、凍結テストと rb の blob 同一性、製品配線検査、`--selftest`）
- `docs/agent-output/tests-task-48.md`

## 期待値の出所

正本は `tasks/task-48.md`。製品の辞書・列挙・出力から期待値を生成していない。各行はテスト内の独立リテラル。

| 検査 | 契約 |
|---|---|
| 公開面 `UIWording` / `Key` / `text(_:languageCode:)` と数値 3 関数 | L54-63（文言キー・関数名・引数型は PM がテスト作成時に固定） |
| 一般文言 31 件の日英逐語 | L71-103 の表 |
| 3入力欄の共通キー `composerPlaceholder` | L73 と成功基準 1（L150） |
| 未対応言語の日本語フォールバック、地域付き Locale | L57-58 |
| 言語を変えて再取得 | 成功基準 1（L149） |
| 使用率・使用量・費用テンプレート（欠落・逆転・固定の検出） | L107-111、L151 |
| 命名規則（`Key` の case 名 = rawValue、`allCases` 順は表順） | L61 |
| 禁止語（`Ask Phlox anything...`、`XHigh`、`Effort` を英語見出しにしない、権限・状態説明） | L47-50、L115、仕様 UX-10 |
| 配線：直値置換、通常/省略メニュー、コピー前後 help/AX、言語受け渡し、action/Binding/tag/Plan/計算の不変 | 成功基準 2（L170-176） |
| `--selftest` の正例・負例 | L178-187 |

数値テンプレートの波括弧は挿入位置であり、画面へ出る記号ではない。日本語使用率は `使用 12%（残り 88%）`（全角括弧、`使用` の後に空白）。英語は `12% used (88% left)`。費用は `この応答の費用 $0.0123` / `Turn cost $0.0123`。

## `xcrun swiftc -parse` 原文

作業ディレクトリはリポジトリルート。構文のみ。モジュール解決・型検査はしない（`UIWording` 未実装のコンパイル RED は PM が凍結時に実パスへ移して確認する）。

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceUIWordingTests.swift
```

標準出力・標準エラーは空。終了コード 0。構文欠陥は無い。

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番関数を呼び、正例と負例の期待エラー集合を `==` で厳密比較する。

```
$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK
```

終了コード 0。

正例は、対象位置の正本接続、動的出力の保持、言語受け渡し、コメント/URL/補間の追加、固定 SHA が HEAD と同じでも実装前 blob なら拒否しない、を含む。負例は契約が列挙した「入力欄1箇所だけ旧文言」「誤ったキー」「省略メニューだけ未修正」「コピー後 AX ラベルだけ未修正」「未使用コード・if false・ダミー文字列」「コントロール削除」「言語固定」「数値の逆転」「action / Binding / tag / 既定値 / Plan 順序・排他の改変」「基準未設定・HEAD・ブランチ名・契約不一致・実装後自己比較・凍結テストと rb の改変」を、期待配列との `==` で固定している。

本番パス（`TASK48_BASELINE` 未設定 + 契約 `baseline_commit: "PM が凍結時に設定"`）は凍結後に通す。今回は指示どおり `--selftest` のみ。

## 契約の曖昧点（検査側の確定）

契約・製品は変更していない。テストが採った解釈だけを残す。

1. **公開 API**: `enum UIWording`、入れ子 `enum Key: String, CaseIterable, Equatable, Hashable, Sendable`（31 case、表順、rawValue は case 名）。`text(_:languageCode:)` と数値 3 関数。task-50 が拡張を足せる公開面。
2. **言語コード**: 主言語（最初の `-` / `_` の前）を大小無視。`en` は英語、`ja` は日本語、空・`zh`・`fr` 等は日本語。`ja-JP` / `en-US` / `en_GB` も同じ規則。
3. **3入力欄**: 同一キー `.composerPlaceholder`。View 接続は Ruby。
4. **Permission と Approval**: 日本語はどちらも `承認設定`、英語は `Permission` / `Approval`。別キー。
5. **言語名欠損**: `ChatCodeBlock` は `.missingCodeBlockLanguage`（テキスト / text）、`RichMarkdownView` は `.missingMarkdownLanguage`（コード / code）。
6. **`ComposerContextGauge.helpText`**: 契約表に無いため Swift 期待値に入れていない。`lines(usedTokens:windowTokens:languageCode:)` の 3 行だけを正本接続する。
7. **権限固有の値名**: `Accept Edits` / `Bypass` / `Agent` 等は task-50。配線の残余直値検査から除外。`Plan` と `Approval` と一般見出しは本タスク。
8. **`OK`**: 契約どおり翻訳対象外。アラートの `Button("OK")` は残してよい。
9. **`composerModeOptions` 等への `languageCode` 追加**: 契約が許可する言語引数。項目集合・`value`・`isPlan`・末尾 Plan・排他は baseline と比較。
10. **`baseline_commit`**: プレースホルダのまま。rb 本番は凍結 SHA 設定後。

## 凍結時メモ（PM）

- テストを実パスへ移し、`UIWording` 未実装のコンパイル RED を確認する。
- `.claude/scripts/task48-wiring.rb` は gitignore される。凍結コミットでは `git add -f .claude/scripts/task48-wiring.rb` と実パスのテストを同一コミットに入れる。
- そのコミット SHA を契約 `baseline_commit` と `TASK48_BASELINE` の両方に入れる。HEAD / ブランチ名は rb が拒否する。
- 成功基準 3 の既存検査改訂（`AcceptanceContextPopoverBranchTests`、mode メニュー、`task13-wiring.rb`）は本作成の範囲外。

=== REPORT COMPLETE ===
