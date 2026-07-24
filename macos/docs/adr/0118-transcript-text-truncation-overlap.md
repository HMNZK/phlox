---
status: active
last-verified: 2026-07-24
---

# ADR-0118: transcript の切り詰めを廃止し、Markdown の折返し高さを非表ブロックで確保する

## 文脈

長いコマンド等のタイトルは `DisclosureCard` が `lineLimit(1)` と
`truncationMode(.middle)` を指定していたため、必ず 1 行へ切り詰められていた。これは
`NSHostingView` に幅 300pt でホストした受け入れテストでも、短文・長文とも高さ 34pt
となることで再現した。

Markdown 本文は `AgentMessageBody` から `RichMarkdownView` を経て MarkdownUI v2.4.1
の空 `Theme()` で描画される。空テーマの paragraph と heading 1〜6 は label をそのまま返す。
そのため、選択可能な本文が狭幅で複数行に描画されても、ブロック側が縦方向の必要サイズを
明示しない経路が残っていた。後続見出しと重なって見える症状は、この縦サイズ確保漏れと
一致する。

プログラム再現には `NSHostingView` を使い、長い日本語段落＋後続 `##` 見出しを 360pt と
1400pt で測定した。この隔離ハーネスでは修正前から狭幅の高さ増加自体は観測でき、実アプリで
報告された「クリック後に重なる」状態そのものは再現できなかった。したがって、クリック時の
全文展開を独立原因としては確認できていない。本文には `lineLimit` / `truncationMode` が無く、
選択機構を外す対症療法は採らない。

`GridChatColumn` の live-resize 幅凍結・`.clipped()`・`.equatable()` は ADR 0116 の
性能機構である。単一表示にも起き得る本文の高さ問題とは別であり、変更しない。

## 決定

1. `DisclosureCard` の title / subtitle から 1 行制限と切り詰めモードを除去し、
   `.fixedSize(horizontal: false, vertical: true)` で折返し行の高さを確保する。
2. `RichMarkdownView` の `.paragraph` と heading 1〜6 にのみ
   `.fixedSize(horizontal: false, vertical: true)` を付ける。これらは `.table` ブロックより前に置く。
   heading 4〜6 のフォントサイズなどは MarkdownUI 既定のままとする。
3. `.table` / `.tableCell` には fixedSize を付けない。MarkdownUI v2.4.1 の `TableCell` は
   table-cell label を直接描画し、この paragraph テーマフックを経由しないことを依存元で確認した。
   ADR 0045 の表レイアウト非収束を再導入しない。
4. ADR 0116 の幅凍結、クリップ、同値比較は維持する。

## 検証

- 受け入れテストは長い DisclosureCard の高さ増加、切り詰め指定の除去、狭幅 Markdown の
  高さ増加、表テーマへの fixedSize 非適用を確認する。
- 白箱テストは `NSHostingView` で日本語段落＋後続見出しの狭幅高さを測定し、paragraph と
  heading 4〜6 の fixedSize が `.table` より前に限定されていることを確認する。
- 実 GUI でのクリック後オーバーレイ再現は未検証。隔離 `NSHostingView` では当該状態を
  再現できなかったため、実アプリの選択操作を含む最終確認は別途必要である。
