---
task: task-44
status: completed
---

## 詰まった点

差し戻し r1 の HIGH（保存 transcript 復元で補足本文が derived に混入）は、ChatItem に由来フィールドがなく、allowed_paths 外のスキーマ変更なしに経路情報を残す必要があった。サーバー変換時に識別不能／識別済みを記録し、表示からは origin 添付を外し、永続化時に付け戻す形で契約 H1 を保存・復元へ通した。

## できた風だが実は未完

指定4命令はすべて GREEN。r1 の実装欠陥3件（HIGH 由来保持、MEDIUM 初回保存の load 後再確認、MEDIUM 改名の同値保存抑止）を allowed_paths 内で直した。

- GUI・課金セッションは起動していない（契約どおり Cursor は未実施。PM 目視ゲート）。
- ChatItem の associated value は増やしていない。由来は変換記録と origin 添付（表示からは除去）で持つ。

## 置いた前提・仮定

- task-41 の `SessionTitleDeriver.derive(from:)` を複製せず使う。
- サーバー履歴の由来識別は `ThreadItem.raw["originalText"]` の有無だけ。本文の見た目では推測しない。
- `chatItem(from:)` がユーザー項目を変換した時点で identified / unidentified を記録する。ローカル確定本文（origin 記録なし）だけを保存 transcript の元本文として採用する。
- 識別不能なサーバー補足は復元後も `receivingUserMessage` へ渡さない。ローカル履歴の未記録 ChatItem は従来どおり本文を元本文として扱う。
- derived/manual では `InputHistoryPolicy.entries` / 導出の前に `source == .flower` で return する。
- 初回 `persistSession` は `sessionStore.load()` の後に `deletedSessionIDs` と `liveTitleState` を再評価する。
- チャット明示 rename の二重 enqueue は `persistSessionName` の同値状態スキップで抑止する（`renameSession` の `persistSessionName` 接続は rb が要求するため残す）。
- `TASK44_BASELINE=361f7fa` は契約 `baseline_commit` と一致する。

## 契約からの逸脱

残る逸脱はない。テスト・rb・契約・台帳は変更していない。

## レビュー重点

- ローカル `/review` の識別不能サーバー補足を保存 transcript から復元しても flower のままか。
- 初回保存の await load 中に起きた rename / 削除が、書き込み時点の最新状態・非再作成になるか。
- チャット明示 rename が同値の二度目のストア全体保存をしないか（PTY は `renameSession` → `persistSessionName` のみ）。
- 早期ガードが `InputHistoryPolicy.entries` より前か。PID・H5 削除繰り越しを崩していないか。

## 検証原文

```
$ ruby .claude/scripts/task44-wiring.rb --selftest
task44-wiring --selftest: OK
```

```
$ env TASK44_BASELINE=361f7fa ruby .claude/scripts/task44-wiring.rb
task44-wiring: OK
```

```
$ ~/.agents/scripts/compact-test t44-rw bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 5.273 seconds.
```

（exit 0。compact-test は最終要約1行のみ。確認のため SessionFeature 全数も `bash macos/scripts/run-swift-tests.sh SessionFeature` で 954 tests GREEN / 1.210 seconds。）

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
