---
task: task-44
status: completed
---

## 詰まった点

今回の最終確認では製品修正は不要だった。過去報告のブロッカーは PM 承認のハーネス修理と基準再凍結（`8149005`）で解消済み。

- 凍結受け入れテストのコンパイル不能（`threadResume` の return 欠落、actor `resume()` の `await` 欠落）は修理版の再凍結で解消。
- rb 恒久検査 `check_no_name_ai` が基準由来の `Process()` を名前目的と誤検知していた件も、修理取り込み後は恒久検査 GREEN。

## できた風だが実は未完

指定4命令はすべて GREEN。製品の名前状態配線は allowed_paths 内で成立している。

- GUI・課金セッションは起動していない（契約どおり Cursor は未実施。PM 目視ゲート）。
- 指定の compact-test は2回 GREEN。確認のため `--full` で取り直した1回だけ、既存 `AcceptancePaneDefaultsIsolationTests`（`phlox.grid.paneLayout` の UserDefaults 隔離）が RED になった。task-44 の許可パス外・既存テストのため製品は触っていない。直後の指定コマンド再走は GREEN。

## 置いた前提・仮定

- task-41 の `SessionTitleDeriver.derive(from:)` を複製せず使う。
- サーバー履歴の由来識別は `ThreadItem.raw["originalText"]` の有無だけ。本文の見た目では推測しない。
- ローカル確定本文は `pendingInput + text` を ID マップに残し、同一 ID のサーバー補足より優先する。
- derived/manual では `InputHistoryPolicy.entries` / 導出の前に `source == .flower` で return する。
- 復元中の明示削除は `SessionPersistenceCoordinator` で件数減少抑止を維持し、`completeSessionRestore()` 後へ繰り越す。PID 書き戻しは現存 descriptor に `updating(pid:)` するだけで upsert しない。
- 花名の通常 `name` 代入はしない。生成・復元・復元失敗は `titleState:` で渡す。
- `TASK44_BASELINE=8149005` は契約 `baseline_commit` と一致する。

## 契約からの逸脱

残る逸脱はない。過去の「凍結テスト／rb 欠陥で合格ライン未達」は基準 `8149005` への再凍結と worktree rebase 後、指定検査 GREEN で解消。テスト・rb・契約・台帳は変更していない。

## レビュー重点

- initializer 正規化と旧 JSON legacy（欠落/null source は手動、花名・導出全文を捨てる）。未知 source は descriptor を破棄せず手動退避。
- 補足付きサーバー本文を混入させていないか。早期ガードが抽出より前か。
- 初回保存が live `titleState` を使うか。PID が古いスナップショット全体を書いていないか。削除済み ID を再作成しないか。
- H5: 復元中削除が要求時点では残し、復元終了後に消えるか。
- task-45 向け `titleState` 読み取りが両 VM / SessionNode にあるか。表示責務を先取りしていないか。

## 検証原文

```
$ ruby .claude/scripts/task44-wiring.rb --selftest
task44-wiring --selftest: OK
```

```
$ env TASK44_BASELINE=8149005 ruby .claude/scripts/task44-wiring.rb
task44-wiring: OK
```

```
$ ~/.agents/scripts/compact-test t44-final bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 5.500 seconds.
```

（exit 0。compact-test は最終要約1行のみ。同コマンドの直前走査も exit 0 / `5.085 seconds`。`--full` で見た内訳は AgentDomain 519、SessionFeature 953、DashboardFeature 本体＋実git 14。）

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
