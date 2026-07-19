---
status: active
last-verified: 2026-07-19
---

# 0101: Markdown 箇条書きの行重なりを .listItem 限定の縦サイズ確保で直す（表への波及を避ける）

> **このファイルの役割**: チャットの箇条書きで折り返し行が次項目と重なるバグの修正方式（`.listItem` へ限定した `.fixedSize(vertical:)`）と、ADR 0045 の表 CPU 暴走を再発させないためのスコープ限定の理由を記録する。
> **書かないもの**: 現行のテーマ構造（→ コード `SessionFeature/RichMarkdownView.swift`・iOS `DesignSystemIOS/Markdown/DSMarkdownText.swift`）、run の作業経緯（→ `delivery/0007-thinking-recap-and-markdown-list-fix-worklog.md`）。

## 文脈

チャットの Markdown 箇条書きで、項目が折り返すと**折り返し2行目が次項目と縦に重なって描画**され、潰れて「…」で切れているように見えるバグがあった（macOS 単一ビュー・グリッドビュー両方で再現、ユーザースクショ確認済み）。当初は lineLimit truncation を疑ったが、全描画経路に本文 clamp が無いことを確認し、真因は**行の縦レイアウト確保漏れ**と特定した。MarkdownUI v2.4.1 の `ListItemView` は `Label { content } icon: { marker }` 構成で、項目 content に縦サイズ確保が無く、折り返し時に高さが1行分に固定されて overflow する。macOS `RichMarkdownView` / iOS `DSMarkdownText` の `chatMarkdownTheme` は `.text`/`.code`/`.link`/heading/blockquote/codeBlock/table を設定していたが、**list 系（bulletedList/listItem/paragraph）の縦スペーシングを設定していなかった**。

このテーマには既知ハザードがある: `.table`/`.tableCell` に `.fixedSize(horizontal: false, vertical: true)` を付けると、MarkdownUI のアンカーベース表測定と Phlox のチャット文脈で幅⇄高さの帰還ループを形成し CPU が 100% 固着する（**ADR 0045**）。素朴に Markdown 全体へ `.fixedSize(vertical:)` を掛けると表へ波及してこの暴走を再発させる。

## 決定

1. **修正は `.listItem` テーマフックに限定する**。`configuration.label.fixedSize(horizontal: false, vertical: true)` を list 項目にのみ適用し、折り返し全行分の高さを確保する。`.listItem` は list 項目にのみ適用され `.table`/`.tableCell` へは波及しないため、ADR 0045 の非収束ループとは無関係。コード内 NOTE でこの切り分けを明示し、table への fixedSize 再導入禁止（ADR 0045）を維持する。
2. **macOS（`RichMarkdownView`）と iOS（`DSMarkdownText`）に同方針で適用**する。list 以外のブロック（table/codeBlock/heading/blockquote）の見た目は変えない。
3. **自動回帰テストは置かない**。PM が隔離描画ハーネス（`ImageRenderer`／`NSHostingView.fittingSize`、フォント倍率 0.8〜2.0）で重なりを**再現できなかった**（未修正でも高さは常に正しい＝実アプリのフル描画コンテキスト依存）。検出力の無いテストは誤った安心感になるため凍結しない（ADR 0045 と同じ判断・テスト規律）。ゲートは PM のライブ目視検証とする。

## 棄却案

- **Markdown 全体／paragraph 層へ `.fixedSize(vertical:)`**: table セルへ波及し ADR 0045 の CPU 暴走を再発させる。棄却。
- **`lineLimit` の緩和／`.textSelection` 除去**: 症状は truncation でなく縦レイアウト確保漏れであり、対症療法。根本原因（list 項目の縦サイズ未確保）を直さない。棄却。
- **検出力の無い隔離ハーネス回帰テストの配置**: 未修正コードでも green になり品質シグナルを汚す。棄却（ライブ目視ゲートに委ねる）。

## 結果

- macOS/iOS 両テーマに `.listItem` 限定の縦サイズ確保を追加。`.table`/`.tableCell` は無改変（ADR 0045 の禁止を維持）。
- `swift test` 全数 green（SessionFeature 209／PhloxKit 413 ほか、0 failures）。表スタイル無改変のため既存表スモークも green。
- Debug ビルドでの目視（長い箇条書きの折り返し行が重ならず全行表示）はユーザーが確認済み（「確認できた」）。
