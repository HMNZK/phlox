ESCALATION: 凍結テストの幅変換期待値が内部矛盾しており、task-41 を GREEN にできません。実装は契約の指名 API のまま止め、開示レポートは `docs/agent-output/task-41.md`（`status: blocked`）です。コミットしていません。

**矛盾の中身。** 契約の確定 2 は行全体に `applyingTransform(.fullwidthToHalfwidth, reverse: false)` を使うと書いてあり、Foundation は全角カナも半角にします（`ログイン` → `ﾛｸﾞｲﾝ`）。同じ凍結スイートは一方で `ログイン画面を修正` を変換前のまま期待し、他方で `カタカナ修正` → `ｶﾀｶﾅ修正` を期待します。単一の行変換では両方を満たせません。テストは改変禁止です。

**今の実装。** `SessionTitleDeriver.swift` に純粋関数を置き、指名 API を行全体へ掛けています。フェンス・インデント・接頭辞除外・32/33 Character・絵文字/結合文字は、カナ以外は通っています。カタカナ変換テストは PASS、`ログイン*` が RED です。

**検証。** `task41-wiring.rb --selftest` と `TASK41_BASELINE=1ad3e09 TASK41_SCOPE_CHECK=1` は OK。他担当の task40 dirty は AgentDomain ソース外なので範囲検査は NG になりませんでした。`git diff --check` は exit 0。受け入れは 42 件中 72 issues（すべて `ログイン` vs `ﾛｸﾞｲﾝ`）。全数は 461 件中同じ 72 issues、他 suite は PASS。

**PM への選択。** (A) `ログイン*` の期待を半角カナへ再凍結するか、(B) 幅変換を全角英数・U+3000 に限り、カタカナ 2 テストと確定 2 を直すか。UX-01 の読みやすさなら (B) です。再凍結後に続きを実装します。
��る。

## 置いた前提・仮定

- 終了フェンスの「空白」は半角空白・タブ・U+3000 とした（開始インデントは半角空白 0〜3 のみ）。
- `applyingTransform` が `nil` を返したときは変換前文字列を使う。
- 行頭トリムは `CharacterSet.whitespaces`（U+3000 を含む。契約の確定 5 に合わせた）。
- コード除外は契約のフェンス・4 空白/タブ・固定接頭辞のみ（任意言語の識別はしない）。`ponytail:` コメントにその限界を書いた。
- `DerivedSessionTitle` の memberwise init は同一モジュールの合成 init で足りるとした（公開 init は契約に無い）。
- 他担当の未コミット（`.claude/scripts/task40-wiring.rb` と `tasks/frozen/staged/*`）は触っていない。`TASK41_SCOPE_CHECK=1` は AgentDomain ソースと `Package.swift` だけを見るため、今回はそれらの dirty では NG にならなかった。

## 契約からの逸脱

- 成功基準表の `ログイン画面を修正` を、指名された Foundation 変換の結果（`ﾛｸﾞｲﾝ画面を修正`）として返している。表のリテラルとは一致しない。理由: 後段の確定 2・3 とカタカナ固定テストが変換を要求しており、行単位の単一変換では表側を優先できない。
- task-41 の成立を UX-01 全体の完了とはしていない。

## レビュー重点（PM 用・レビュアーには渡さない）

- 幅変換の正本をどちらにするか（行全体の `fullwidthToHalfwidth` vs 全角英数・U+3000 のみ）。`ログイン*` フィクスチャとカタカナ 2 テストの再凍結が先。
- フェンス走査（4 backtick は 3 では閉じない、異種マーカーでは閉じない、終了後の非空白では閉じない、1〜3 空白の開始、より長い終了）は RED 原因ではなく、カタカナ以外は概ね PASS。
- 半角カナ入力の保持・絵文字/結合文字の Character 境界・10000 文字の fullTitle 保持は PASS。

## 検証原文

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41 swift test --filter AcceptanceSessionTitleDeriverTests)`

exit 1。抜粋（代表の不一致。期待は全角カナ、実測は半角カナ）:

```
✘ Test "閉じたバッククォートフェンスの次行を採る" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:19:9: Expectation failed: (result?.title → "ﾛｸﾞｲﾝを修正") == (expected → "ログインを修正")
✘ Test "公開契約: derive(from:) が title/fullTitle を返す" recorded an issue at AcceptanceSessionTitleDeriverTests.swift:30:9: Expectation failed: (result?.title → "ﾛｸﾞｲﾝ画面を修正") == "ログイン画面を修正"
✔ Test "全角カタカナを半角カナへ幅変換する" passed after 0.005 seconds.
✔ Test "濁点付き全角カナを半角カナ+半角濁点へ幅変換する" passed after 0.005 seconds.
✘ Suite "task-41: session title deriver" failed after 0.005 seconds with 72 issues.
✘ Test run with 42 tests in 1 suite failed after 0.005 seconds with 72 issues.
```

### `(cd macos/Packages/AgentDomain && ~/.agents/scripts/compact-test t41-all swift test)`

exit 1。task-41 以外の suite は PASS。要約行:

```
✘ Suite "task-41: session title deriver" failed after 0.030 seconds with 72 issues.
✘ Test run with 461 tests in 24 suites failed after 1.032 seconds with 72 issues.
```

### `ruby .claude/scripts/task41-wiring.rb --selftest`

```
task41-wiring --selftest: OK
```

### `env TASK41_BASELINE=1ad3e09 TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb`

```
task41-wiring: OK
```

変更範囲検査は GREEN。他担当 dirty（task40 の rb・staged テスト）は AgentDomain ソース外のため NG 行は出なかった。stash していない。

### `git diff --check`

exit 0（出力なし）。

=== REPORT COMPLETE ===
