---
status: completed
last-verified: 2026-10-05
---

# 0041: 残差の判断と最終状態

見本合わせ（[0039](0039-design-alignment-worklog.md)）とシンタックスハイライト（[0040](0040-syntax-highlighting-worklog.md)）の後に残った小さな差を解消した。基準は [シンタックス仕様](../specs/syntax-highlighting.md) と [ファイル仕様](../specs/file-explorer-and-markdown-editing.md) §3.8。

## 判断
- CSS の `url(...)` は引数の境界を先に取り、内部の `:`・`/` を再分類しない（引数全体を文字列色）。
- ソース表示の寸法は見本 3c の CSS を正とする: 11pt・行間 19.25pt、番号欄の右端 42pt、本文の左端 56pt、上の inset 3.5pt（1 行目の文字上端がヘッダー下 13pt）。ブロック編集の寸法は変えない。HTML と AppKit の字形による約 0.5pt の画素差は許容する。
- Markdown のソース表示では ATX 見出しを等幅の太字にする（0039 の「太字なし」を撤回。ADR 0180 に追記）。太字の判定はフォントの weight トレイトで行い、日本語の代替字体も正しく解除する。`#` の後ろが ASCII 空白・タブ・行末のときだけ見出しとし、U+00A0・U+3000 は CommonMark どおり見出しにしない。
- 見出しのフォント変更は、バッチごとに `beginEditing`/`endEditing` で囲み、選択と入力属性を戻すより先に閉じる。見出し・フェンスの判定は UTF-16 配列の上で直接行う（1MB で約 20ms 短縮）。
- ブロック編集欄のインラインコードは、見本 4j どおり本文色にする。ソース表示とリンク先の文字列色は維持する。
- ソース表示の本文色は見本 3c の #D5D5DA に対応する既存トークンが無い（`textSecondary` は #ABABB1）。新しいトークンは足さず `textPrimary` を維持する。
- 4j の撮影で出ていた余分な空白は撮影側の不具合（ブロック末尾の空行の後に追記していた）。製品の動作は変えていない。

## 最終状態
- 全テスト: `bash macos/scripts/run-swift-tests.sh` で 4,081 件成功、失敗 0。
- 実機の UI テスト: FileTree・HTML・Markdown の 7 件すべて成功（`testSourceHighlightingKeepsUndoAndSavedBytes` を含む）。
- Debug ビルド・UI テストのビルド: 成功。既存の警告（AppIntents のメタデータ抽出省略、非推奨 API 等）あり。
- 見本との比較: 3c・3e・3f・3g・4j・4m・5g・syntax-* で、残りは以前からある低 2 件だけ（日本語本文がもともと太めで見出しとの差が見本より小さい、4m の選択色が画面外描画では灰色）。

## 性能（Release、Apple M4 Pro・macOS 26.6.2、2 回測定の最大値、単位 ms）
`PHLOX_SYNTAX_PERFORMANCE=1 swift test --package-path macos/Packages/DashboardFeature -c release --no-parallel --filter CodeSyntaxPerformanceTests`。基準は入力・属性適用 p95 ≤ 16、編集完了 p95 ≤ 150。

| 種類 | バイト数 | 入力 p95 | 属性適用 p95 | 編集完了 p95 | 初回完了 |
|---|---:|---:|---:|---:|---:|
| swift | 10,000 | 2.52 | 1.13 | 59.20 | 28.91 |
| swift | 100,000 | 3.16 | 3.29 | 67.06 | 89.16 |
| swift | 1,000,000 | 5.31 | 7.91 | 92.05 | 876.05 |
| ime.swift | 1,000,000 | 0.37 | 7.78 | 87.85 | 863.45 |
| json | 10,000 | 2.44 | 4.14 | 79.09 | 12.62 |
| json | 100,000 | 2.33 | 4.78 | 72.25 | 110.06 |
| json | 1,000,000 | 2.11 | 10.81 | 95.03 | 1083.57 |
| md | 10,000 | 2.47 | 1.36 | 61.45 | 16.37 |
| md | 100,000 | 3.77 | 3.07 | 72.90 | 136.09 |
| md | 1,000,000 | 8.09 | 7.96 | 104.11 | 1609.42 |
| mixed.md | 10,000 | 2.34 | 4.75 | 76.66 | 13.94 |
| mixed.md | 100,000 | 2.91 | 3.79 | 76.10 | 134.44 |
| mixed.md | 1,000,000 | 11.38 | 9.74 | 135.06 | 1346.73 |

## 再現
- 撮影: `PHLOX_DESIGN_SNAPSHOTS=1 swift test --package-path macos/Packages/DashboardFeature --no-parallel --filter DesignSnapshotRenderTests`（出力は worktree の `.build/design-snapshots/`）。

## 未検証
- 実際の日本語入力（IME）での色付けと太字、実画面での選択色。
