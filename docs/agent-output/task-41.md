---
task: task-41
status: completed
---

> PM 注記（2026-09-13）: run-headless.sh の第 2 引数（cursor-agent の stdout 先）に本ファイルを渡していたため、担当が書いた本文の先頭が終了時の最終メッセージで上書きされた（原因は `.claude/lessons.md` L-7）。先頭部（frontmatter・冒頭節）は復元不能。以下、最終メッセージの本文→残存した本文の順で残す。

指摘1に対応した。`SessionTitleDeriver` の空白判定を Character 比較から Unicode スカラー単位に変えている。

入力 `"A\u{3000}\u{301}B"` は `"A \u{301}B"` になる（U+3000 だけ半角空白、U+0301 は維持）。trim・内部圧縮・終了フェンスの残り判定も同じ3種（`" "` / `"\t"` / U+3000）のスカラー走査。公開面・幅変換・省略の Character 単位・純粋性は変えていない。テストと rb は未変更。allowed_paths 以外は触っていない。コミットしていない。

検証:
- `compact-test t41r swift test` — 462 tests GREEN
- `/tmp` スクラッチで再現ケース `match=true`（スカラー U+0041 U+0020 U+0301 U+0042）
- `TASK41_BASELINE=962ddb2 TASK41_SCOPE_CHECK=1` の wiring — OK
- `git diff --check` — exit 0

開示レポートは `docs/agent-output/task-41.md`（`status: completed`）。
白ならそのスカラーだけ `" "` へ置換し、同一 Character の残スカラー（結合文字）は維持する。連続する空白スカラーは半角空白1個へ圧縮する。
- 省略（32/33 Character）は従来どおり Swift `Character` 単位。入力は変更しない。
- 終了フェンスの「その後が空白だけ」も同じスカラー判定。空の残りは閉じとみなす（従来と同じ）。
- `DerivedSessionTitle` の memberwise init は同一モジュールの合成 init で足りる（公開 init は契約に無い）。
- 他担当の未コミット（SessionFeature / DesignSystem / DashboardFeature）には触っていない。

## 契約からの逸脱

- なし。公開面・導出順・幅変換・フェンス・除外接頭辞・純粋性は変更していない。task-41 の成立を UX-01 全体の完了とはしていない。

## レビュー重点（PM 用・レビュアーには渡さない）

- 指摘1の再現入力 `"A\u{3000}\u{301}B"` → `"A \u{301}B"`（スカラー U+0041 U+0020 U+0301 U+0042）。凍結テスト未被覆。
- trim を `.whitespaces` から3種スカラーへ揃えた点。NBSP 等を trim しなくなる。
- 終了フェンス残りが U+3000+結合文字のときは空白だけではないので閉じない（スカラー判定の帰結）。

## 差し戻し対応の内容

指摘1（結合文字を伴う全角空白が圧縮されない）への対応。`isCollapsibleWhitespace` を `Unicode.Scalar` 比較にし、`trimCollapsibleWhitespace` / `collapseInternalWhitespace` / 終了フェンス残り判定をスカラー走査にした。U+3000 に U+0301 が続く Character でも、空白スカラーだけ半角空白へ置換し結合文字は残す。幅変換・公開 API・I/O なしの純粋性は維持。テスト・rb は未変更。

## 検証原文

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41r swift test)`

exit 0。原文:

```
✔ Test run with 462 tests in 24 suites passed after 1.029 seconds.
```

### 指摘再現（リポジトリ外 `/tmp/t41-combining-check`、`swift run`）

入力 `"A\u{3000}\u{301}B"`。exit 0。原文（印字部）:

```
input_scalars=U+0041 U+3000 U+0301 U+0042
title=A ́B
fullTitle=A ́B
title_scalars=U+0041 U+0020 U+0301 U+0042
expected=A ́B
expected_scalars=U+0041 U+0020 U+0301 U+0042
match=true
character_count_input=3
character_count_title=3
```

### `env TASK41_BASELINE=962ddb2 TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb`

exit 0。原文:

```
task41-wiring: OK
```

### `git diff --check`

exit 0。標準出力は空。

=== REPORT COMPLETE ===
