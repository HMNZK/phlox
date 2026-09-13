---
task: task-41
status: completed
---

## 詰まった点

- なし。r3 の要求（O(n) trim・終了フェンス残りの Unicode 空白・内部圧縮 3 種据え置き）は公開面を変えずに入れられた。

## できた風だが実は未完

- 確定 6 の 5 期待（NBSP 単独 nil、先頭 NBSP 付き `/review` 除外、U+2003 の前後 trim、内部 NBSP 維持、U+3000+結合文字の内部圧縮）は凍結テストに無い。AgentDomain 全数 GREEN では未被覆。確認はリポジトリ外 `/tmp/t41r3-check` の印字のみ。
- 終了フェンス行の「その後が空白だけ」を Unicode 空白全般へ広げたことも凍結テストに無い（既存ケースは半角空白中心）。NBSP / U+2003 だけの残りで閉じる入力はスクラッチ 5 期待にも入れておらず、機械検査は未追加（新規テスト禁止）。
- 100,000 スカラーの前後 trim が 1 秒未満なことも凍結テストに無い。スクラッチ印字のみ。
- r2 実装の「末尾 Character の先頭スカラーだけ落とす」（空白+結合文字の Character から空白スカラーだけ除いて結合文字を残す）は、r3 の「空白でない最後のスカラーまでを一回スライス」に置き換えた。`"A \u{301}"` のような末尾は、結合文字が非空白なので空白は内部扱いで残る。この差は凍結テストにも 5 期待にも無い。

## 置いた前提

- 「`CharacterSet.whitespaces` 相当」は Foundation の `CharacterSet.whitespaces.contains(Unicode.Scalar)` そのもの。改行類（LF/CR 等）は含めない。
- 前後 trim は先頭から空白でない最初のスカラー、末尾から空白でない最後のスカラーを一度求め、`UnicodeScalarView` を一回スライスする。除去のたびに `String` を再生成しない。
- 内部圧縮は r1 どおり `" "` / `"\t"` / U+3000 のみ。NBSP・U+2003 等は圧縮しない。
- 終了フェンス残りの `allSatisfy` は trim と同じ `isUnicodeWhitespace`。3 種限定は `collapseInternalWhitespace` だけ。
- `lines` の CRLF/CR 置換は各 O(n) の 2 パスで、除去ループでは二乗にならない。幅変換・内部圧縮もスカラー 1 走査。
- 導出順（trim → 幅変換 → 内部圧縮 → 空/接頭辞除外）は不変。公開面・幅変換・32/33 Character 省略・純粋性は不変。
- テスト・rb は改変禁止のため、確定 6 補足と O(n) の回帰は契約側の再凍結待ち。

## 契約からの逸脱

- なし。確定 6 とその補足（trim O(n)・終了フェンス残りを Unicode 空白全般）に合わせた。task-41 の成立を UX-01 全体の完了とはしていない。

## レビュー重点

- `trimCollapsibleWhitespace` が境界スカラーを一度求めて一回スライスしているか。`dropFirst` / 末尾 Character 再生成の while が残っていないか。
- `isClosingFence` の残り判定が `isUnicodeWhitespace`（`CharacterSet.whitespaces`）で、`collapseInternalWhitespace` が 3 種のままか。
- `"\u{00A0}"` → nil、`"\u{00A0}/review\nログインを修正"` → `ログインを修正`、`"\u{2003}説明\u{2003}"` → `説明`、`"A\u{00A0}\u{00A0}B"` 不変、`"A\u{3000}\u{301}B"` → `"A \u{301}B"`。
- `"A" + 半角空白 100,000` と `NBSP 100,000 + "A"` が 1 秒未満で `A` になること（スクラッチ側）。
- 凍結テストは r2 の二次時間 trim でも GREEN になり得る。r3 の差はスクラッチ印字側。

## 差し戻し対応の内容（r1〜r3）

- r1: `"A\u{3000}\u{301}B"` が Character 比較だと圧縮されなかった。空白判定を Unicode スカラー単位にし、内部圧縮で U+3000 だけ半角空白へ置換して U+0301 を残した。当時の trim も同じ 3 種だった。
- r2: 前後 trim を Unicode 空白全般へ拡大。ただし先頭/末尾 Character の先頭スカラーを 1 個ずつ落として `String` を再生成する while だった（空白 n 個で O(n²)）。内部圧縮は 3 種。終了フェンス残りは 3 種のまま。
- r3（今回）: trim を「空白でない最初/最後のスカラーを一度求めて一回スライス」に変更。終了フェンス残りの「その後が空白だけ」を trim と同じ Unicode 空白全般（スカラー単位）へ変更。内部圧縮は 3 種のまま。他関数に除去ごとの再生成ループは無い。

## 検証原文

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41r3 swift test)`

exit 0。原文:

```
✔ Test run with 462 tests in 24 suites passed after 1.028 seconds.
```

### `/tmp/t41r3-check`（`swift run`、リポジトリに未追加）

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
  expected=fullTitle=A  B
  match=true
case=ideographic_space_combining
  input_scalars=U+0041 U+3000 U+0301 U+0042
  result=title=A ́B fullTitle=A ́B fullTitle_scalars=U+0041 U+0020 U+0301 U+0042
  expected=fullTitle=A ́B
  match=true
failed=0
perf=A_plus_100000_spaces
  input_scalar_count=100001
  result=title=A fullTitle=A fullTitle_scalars=U+0041
  expected=title=A
  match=true
  elapsed_seconds=0.00713503360748291
  under_1s=true
perf=100000_nbsp_plus_A
  input_scalar_count=100001
  result=title=A fullTitle=A fullTitle_scalars=U+0041
  expected=title=A
  match=true
  elapsed_seconds=0.015024065971374512
  under_1s=true
```

5 期待はいずれも `match=true`。trim 2 件はいずれも `under_1s=true`。

### `env TASK41_BASELINE=962ddb2 TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb`

exit 0。原文:

```
task41-wiring: OK
```

### `git diff --check`

exit 0。標準出力は空。

=== REPORT COMPLETE ===
