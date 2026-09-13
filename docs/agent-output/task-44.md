---
task: task-44
status: completed
---

## 詰まった点

契約ファイル末尾に「契約の曖昧点の確定（レビュー r2 後の PM 裁定）」節は無かった（D4 で終了）。実装はディスパッチ指示の裁定に従った。ChatItem に isMeta が無く、ClaudeSessionHistory.swift は allowed_paths 外かつ loader の isMeta 項目化は凍結テストが要求するため、loader は変更していない。

## できた風だが実は未完

指定4命令はすべて GREEN。static 由来辞書と transcript マーカーは破棄した。r1 の初回保存 load 後再評価と rename 同値二重保存抑止は維持した。

- GUI・課金セッションは起動していない（契約どおり Cursor は未実施。PM 目視ゲート）。
- 履歴再開は `titleUserMessages`（isMeta 除外済み）から採用する。Phlox store へ flush された isMeta 項目を flower のまま復元する経路は、ChatItem に isMeta が無いため先頭行ヒューリスティックだけでは除外できない。

## 置いた前提・仮定

- task-41 の `SessionTitleDeriver.derive(from:)` を複製せず使う。
- ライブ経路の元本文はインスタンス辞書 `localOriginalUserTextByID` で項目 ID に対応付け、`terminate` で解放する。static は持たない。
- サーバー反映はローカル元本文または `originalText` だけ採用し、識別不能な表示本文は使わない。
- 復元・履歴再開の由来不明ユーザー項目は先頭行だけを候補にし、先頭行が `/` 始まりなら不採用。履歴再開の isMeta は `titleUserMessages` が非 nil なら ChatItem 走査をしないことで不採用。
- transcript 本文は改変しない。保存時の origin 添付を付けない。
- derived/manual では `InputHistoryPolicy.entries` / 導出の前に `source == .flower` で return する。
- 初回 `persistSession` は `sessionStore.load()` の後に `deletedSessionIDs` と `liveTitleState` を再評価する（r1 維持）。
- チャット明示 rename の二重 enqueue は `persistSessionName` の同値状態スキップで抑止する（r1 維持）。
- `TASK44_BASELINE=361f7fa` は契約 `baseline_commit` と一致する。

## 契約からの逸脱

残る逸脱はない。テスト・rb・契約・台帳は変更していない。ClaudeSessionHistory.swift は allowed_paths 外のため未変更。

## レビュー重点

- static `userMessageTitleOriginByID` と transcript マーカーが残っていないか。
- セッション A の復元→同一 ID の B の復元→A の flush で B の本文が A へ保存されないか。
- `startFromHistory` が loader の isMeta ユーザー項目を derived にしないか（`titleUserMessages` 優先）。
- `/review\nログイン画面を修正` を保存 transcript から復元しても flower のままか（先頭行 `/` 不採用）。
- 早期ガードが `InputHistoryPolicy.entries` より前か。初回保存の load 後再評価と rename 同値スキップが残っているか。

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
$ ~/.agents/scripts/compact-test t44-rw2 bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 5.123 seconds.
```

（exit 0。compact-test は最終要約1行のみ。）

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
