---
task: task-44
status: completed
---

# tests-task-44-r5

PM 裁定（decision-log 2026-09-13「task-44 レビュー r1 裁定」）どおり、凍結受け入れテストの待機条件だけを修理した。製品コード・契約・rb・台帳・他テストは未変更。期待値（`expectState` の四フィールド）は弱めていない。

対象: `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift`

## 変更行と理由

- `:423-431` `userMessageText` を追加。同一 ID の本文がイベント処理後にどう変わったかを待つため（投入前から真の `id` 存在検査を置き換える）。
- `:617` / `:623-626`（`ローカル_review_の補足付き送信文字列…`）投入前から真だった `text == "/review"` と `source == .flower` を捨て、`transcriptRevision` 増加かつ当該 ID 本文が `ログイン画面を修正` を含むこと（補足付き `itemCompleted` 反映後に初めて成立）を待つ。H1。
- `:645` / `:651-654`（`ローカル本文と対応付くitemCompleted…`）既存 `userID` の存在待ちを捨て、revision 増加かつ当該本文が `/review` を含むこと（補足付きサーバー本文の置換後）を待つ。H1。
- `:683` / `:689-692`（置換）既存 `userID` の存在待ちを捨て、revision 増加かつ当該本文が `通知を修正` を含むことを待つ。H2 の置換完了。
- `:706` / `:712-715`（再読込）`.restored` だけでは履歴差替の反映を保証しない。revision 増加・`.restored`・`u-reload` 新規エントリを待つ。H2。
- `:726-728`（巻き戻し）履歴を `u-reload` へ置換したあとの古い `userID` への `revert` は対象不在で `nil`。現存 ID `u-reload` を渡し、戻り値が非 nil かつ `通知を修正` であることを検査する。タイトル四フィールドの期待は不変。H2。
- `:882` / `:888-891`（由来無しサーバー履歴）`restoreState != .restoring` は投入前の `.notRestored` でも真。revision 増加・`.restored`・`srv-1` 新規エントリを待つ。同型欠陥。
- `:901` / `:907-910`（由来ありサーバー履歴）`.restored` だけでなく revision 増加と `srv-2` 新規エントリを待つ。同型欠陥。
- `:931` / `:937-940`（由来不能の後の採用）`.restored` だけでなく revision 増加と `good` 新規エントリを待つ。同型欠陥。
- `:957` / `:963-966`（`originalText` が `/review`）`!= .restoring` の事前成立を捨て、revision 増加・`.restored`・`srv-review` 新規エントリを待つ。同型欠陥。

577–578 行の `a1` / `e1`、596 行の `q1` は投入前に存在しない ID を待っており同型ではないので未変更。

## 検証原文

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t44-tfix swift test --no-parallel --filter AcceptanceSessionTitleLifecycleTests)
✔ Test run with 23 tests in 1 suite passed after 0.382 seconds.
```

exit 0。現行実装で RED になったケースは無い（レビュー HIGH「保存 transcript の由来喪失」に対応する RED は今回の待機修理では未検出）。

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
