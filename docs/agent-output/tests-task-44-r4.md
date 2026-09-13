---
task: task-44
status: completed
---

# tests-task-44-r4

PM 裁定（decision-log 2026-09-13「H5 裁定の帰結」）どおり、既存回帰 1 本だけを新契約へ更新した。製品コード・契約・凍結テスト・台帳・rb は未変更。他のテストは未変更。

## 変更行と理由

対象: `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/E2EPersistenceTests.swift`（find 確認。E2E サブディレクトリは無い）

- `:257` doc コメント 1 行に H5 を記す。テスト名は維持（復元中の destructive save は件数を減らさない）。
- `:292-296` 2 回目の `removeSession(descriptors[0].id)` を削除。`completeSessionRestore()` の直後に `waitForPendingWrites()` し、繰り越し削除で `count == 4`・`saveCount == 1` を期待する。実装は復元中削除を終了後へ 1 回保存するため、同一 ID の再削除は 2 回目の save になり旧期待と衝突する。
- `:286-289` 復元中の抑止検査（count 5・saveCount 0・projects 3・saveCount 0）は維持。
- `:298-301` 復元後に別 ID（`descriptors[1]`）を削除し `count == 3`・`saveCount == 2`。ADR 0024 の「復元後は従来どおり」を維持する。

## 検証原文

```
$ ~/.agents/scripts/compact-test t44-e2e bash macos/scripts/run-swift-tests.sh DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 5.508 seconds.
```

（成功時 compact-test は最終要約 1 行。本体パスの GREEN を取るため同一コマンドを `--full` で再走）

```
$ ~/.agents/scripts/compact-test --full t44-e2e bash macos/scripts/run-swift-tests.sh DashboardFeature
=== swift test --package-path Packages/DashboardFeature --no-parallel --skip WorktreeIsolationSpawnTests --skip AcceptanceRestoreAbortNoSpawnTests [本体] ===
✔ Test run with 1768 tests in 175 suites passed after 57.857 seconds.
=== swift test --package-path Packages/DashboardFeature --no-parallel --filter WorktreeIsolationSpawnTests --filter AcceptanceRestoreAbortNoSpawnTests [実git] ===
✔ Test run with 14 tests in 2 suites passed after 5.541 seconds.
run-swift-tests: OK (DashboardFeature / git別パス:WorktreeIsolationSpawnTests AcceptanceRestoreAbortNoSpawnTests / 直列:DashboardFeature)
```

```
$ git diff --check
(出力なし、exit 0)
```

=== REPORT COMPLETE ===
