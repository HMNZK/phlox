---
status: accepted
last-verified: 2026-07-21
---

# ADR 0104: スラッシュコマンドの発火位置を空白区切りトークン先頭に統一（@ と対称）

> **このファイルの役割**: チャット入力欄で `/command` のハイライトとサジェスト発火を「入力の先頭のみ」から「空白区切りトークンの先頭ならどの位置でも」へ広げ、`@` ファイル参照と同じ規則に統一した決定と、単語境界方式を却下した理由。
> **書かないもの**: サジェスト走査の非同期 coalescing（→ [ADR 0053](0053-composer-suggestion-background-coalescing.md)）、composer コンポーネントの全体構成（→ [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md)）。

## 文脈

`/command` のハイライト（`ComposerHighlight.spans`）とサジェスト発火（`SuggestionTrigger.query`）は、いずれも「入力の先頭のときだけ」に制限されていた（前者は `tokenStart == text.startIndex`、後者は `text.hasPrefix("/")`）。一方 `@` ファイル参照は「カーソル直前の空白区切りトークンの先頭ならどの位置でも」発火していた。このため本文の後ろに `/skill` を並べる使い方（例: `ベンチマークを作成してください /frontend-design /design-engineering`）でハイライトも候補ポップアップも出ず、`/` だけ `@` と非対称という UX の穴があった。

## 決定

`/` を `@` と同じ**空白区切りトークン先頭**の規則に統一する。位置は問わない。

- ハイライト: `ComposerHighlight.spans` から先頭限定条件を外し、トークン先頭が `/` のものを各1件 `.slashCommand`。
- サジェスト: `SuggestionTrigger.query` の入力全体先頭の特別扱いを撤去し、カーソル直前トークンの先頭文字で `switch`（`/` → slash、`@` → file、他 nil）。`tokenRange`・`searchTerm` の算出は `@` パスを流用。
- トークン途中の `/`（`src/main`・`http://x`）は発火させない（トークン先頭が `/` でないため）。

### 却下: 単語境界方式（句読点の直後でも発火）

ユーザーのスクショは `。/frontend-design` のように句読点に直付けだった。これも拾う「単語境界」方式（空白に加え句読点の後でも発火）も検討したが、次の理由で却下し、発火境界＝空白・行頭の直後に確定した（ユーザー承認済み）:

- URL(`http://`)・パス(`src/main`)を誤検出しないためには `:`・`/` 等の直後を個別に除外する必要があり、規則が場当たり的になる。
- CJK の「文字」と「記号」の境界判定（`です/skill` は非発火、`です。/skill` は発火など）がエッジケースを増やし予測不能になる。
- `@` と同じ規則に揃える方が学習コストが低く堅牢。句読点直付けは間に半角スペースを入れれば発火する。

## 結果

- 描画側（`ChatComposer.applyComposerHighlights` / `updateSuggestions`）は純関数結果を無条件に消費するため、純関数の変更だけで文中どの位置でもハイライト・候補表示が連動する。
- 受け入れテスト（`AcceptanceComposerHighlightTests` / `ComposerSuggestionAcceptanceTests`）を新契約へ更新し、トークン途中の `/` を無視する回帰ガードを追加。既存の先頭 `/`・`@`・CJK テストは不変で pass。
- `@` の挙動・件数・`tokenRange`・`searchTerm` は不変。
