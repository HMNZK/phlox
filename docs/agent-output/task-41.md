---
task: task-41
status: completed
---

## 詰まった点

- なし。確定 6 は trim 対象の拡張と内部圧縮の据え置きで実装できた。

## できた風だが実は未完

- 確定 6 の 5 期待（NBSP 単独 nil、先頭 NBSP 付き `/review` 除外、U+2003 の前後 trim、内部 NBSP 維持、U+3000+結合文字の内部圧縮）は凍結テストに無い。AgentDomain 全数 GREEN では未被覆。確認はリポジトリ外 `/tmp/t41r2-check` の印字のみ。
- 末尾 Character が「空白スカラー+結合文字」の trim（空白スカラーだけ落として結合文字を残す）は、上記 5 期待にも凍結テストにも無い。実装はあるが機械検査は未追加（新規テスト禁止）。
- 終了フェンスの「その後が空白だけ」は従来どおり半角空白・タブ・U+3000 の 3 種のまま。Unicode 空白全般には広げていない。凍結ケースは半角空白中心。

## 置いた前提

- 「`CharacterSet.whitespaces` 相当」は Foundation の `CharacterSet.whitespaces.contains(Unicode.Scalar)` そのものを使う。改行類（LF/CR 等）は含めない。
- 先頭 trim は「先頭 Character の先頭スカラーが空白ならそのスカラーを落とす」を繰り返す。これは先頭から空白スカラーを除く走査と同値。
- 末尾 trim は最後の Character の先頭スカラーだけを見る。最後のスカラーが結合文字でも、その Character の先頭が空白なら空白スカラーを落とし結合文字は残す。
- 内部圧縮は r1 どおり `" "` / `"\t"` / U+3000 のみ。NBSP・U+2003 等は圧縮しない。
- 導出順（trim → 幅変換 → 内部圧縮 → 空/接頭辞除外）は不変。公開面・幅変換・32/33 Character 省略・純粋性は不変。
- テスト・rb は改変禁止のため、確定 6 の回帰は契約側の再凍結待ち。

## 契約からの逸脱

- なし。確定 6 の trim/内部圧縮の切り分けに合わせた。task-41 の成立を UX-01 全体の完了とはしていない。

## レビュー重点

- `trimCollapsibleWhitespace` が `CharacterSet.whitespaces` で、`collapseInternalWhitespace` が 3 種スカラーのまま分離されているか。
- `"\u{00A0}"` → nil、`"\u{00A0}/review\nログインを修正"` → `ログインを修正`、`"\u{2003}説明\u{2003}"` → `説明`、`"A\u{00A0}\u{00A0}B"` 不変、`"A\u{3000}\u{301}B"` → `"A \u{301}B"`。
- 終了フェンス残りを Unicode 空白全般へ広げていないこと（意図）。
- 凍結テストは r1 時点の 3 種 trim でも GREEN になり得る。確定 6 の差はスクラッチ印字側。

## 差し戻し対応の内容（r1・r2）

- r1: `"A\u{3000}\u{301}B"` が Character 比較だと圧縮されなかった。空白判定を Unicode スカラー単位にし、内部圧縮で U+3000 だけ半角空白へ置換して U+0301 を残した。当時の trim も同じ 3 種だった。
- r2（今回）: 前後 trim を Unicode 空白全般へ拡大。内部圧縮は 3 種のスカラー走査を維持。終了フェンス残り判定の対象集合は変えていない（ヘルパ名だけ内部圧縮用に分離）。

## 検証原文

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41r2 swift test)`

exit 0。原文:

```
✔ Test run with 462 tests in 24 suites passed after 1.029 seconds.
```

### `/tmp/t41r2-check`（`swift run`、リポジトリに未追加）

exit 0。原文（印字部）:

```
case=nbsp_only
  input_scalars=U+00A0
  result=nil
  expected=nil
  match=true
case=nbsp_slash_review_then_login
  input_scalars=U+00A0 U+002F U+0072 U+0065 U+0076 U+0069 U+0065 U+0077 U+000A U+30ED U+30B0 U+30A4 U+30F3 U+3092 U+4FEE U+6B63
  result=title=ログインを修正 fullTitle=ログインを修正 fullTitle_scalars=U+30ED U+30B0 U+30A4 U+30F3 U+3092 U+4FEE U+6B63
  expected=fullTitle=ログインを修正
  match=true
case=em_space_around_setsumei
  input_scalars=U+2003 U+8AAC U+660E U+2003
  result=title=説明 fullTitle=説明 fullTitle_scalars=U+8AAC U+660E
  expected=fullTitle=説明
  match=true
case=internal_nbsp_preserved
  input_scalars=U+0041 U+00A0 U+00A0 U+0042
  result=title=A  B fullTitle=A  B fullTitle_scalars=U+0041 U+00A0 U+00A0 U+0042
  expected=fullTitle=A U+00A0 U+00A0 B
  match=true
case=ideographic_space_combining
  input_scalars=U+0041 U+3000 U+0301 U+0042
  result=title=A ́B fullTitle=A ́B fullTitle_scalars=U+0041 U+0020 U+0301 U+0042
  expected=fullTitle scalars U+0041 U+0020 U+0301 U+0042
  match=true
failed=0
```

5 期待はいずれも `match=true`。

### `env TASK41_BASELINE=962ddb2 TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb`

exit 0。原文:

```
task41-wiring: OK
```

### `git diff --check`

exit 0。標準出力は空。

=== REPORT COMPLETE ===
