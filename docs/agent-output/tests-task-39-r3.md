---
status: completed

# task-39 受け入れテスト・配線検査 改訂 2（独立レビュー指摘1）

HEAD: `4c343d2`（`4c343d2fe48f8c6aa94ef37915a59d1e7621e29b`）。製品コード・契約・台帳は未変更。git commit なし。現行 `TerminalView.makeCoordinator()` は `TerminalCoordinator` を返す（改訂 2 前の形）。

## 変更点

| 対象 | 内容 | file:line |
|---|---|---|
| テスト (a) | `let mount: TerminalMountCoordinator = TerminalView(coordinator: x).makeCoordinator()`。`attach(x, c)` → `attach(y, oldTile)` → `mount.current = y` → `attach(y, c)` → `dismantleNSView(c, coordinator: mount)`。Y 解放・C 空・旧タイル再接続を固定 | `AcceptanceTerminalMountOwnershipTests.swift:238` |
| テスト (b) | `mountA: TerminalMountCoordinator = TerminalView(coordinator: x).makeCoordinator()`。A→B 後に `dismantleNSView(containerA, coordinator: mountA)`。B の所有権が残る | `:264` |
| テスト 不変 | 事後条件 8 ケース・セッション切替・出力保持・2 端末ケースは未変更 | `:47`〜`:230` / `:281` |
| rb 検査追加 | `makeCoordinator` 戻り型 `TerminalMountCoordinator`、`updateNSView` で到達可能な `context.coordinator.current = coordinator` が attach 前、`dismantleNSView` 引数型 `TerminalMountCoordinator`。既存の `coordinator.hostingView` detach・Whitebox guard は維持 | `check_mount_coordinator` `:778`（呼出 `:1338`） |
| rb 正例 | `good_terminal_view_src` / helper fixture を新形へ更新 | `:961` / `:1036` |
| rb 負例 | makeCoordinator が `TerminalCoordinator` を返す（旧形）、current 更新が無い、dismantle が `coordinator.initial.hostingView` を使う | `:1115` / `:1118` / `:1124` |

## コマンド原文

### `TASK39_BASELINE=c8a2010 ruby .claude/scripts/task39-wiring.rb --selftest`

exit 0。変更は退避していない。

```
task39-wiring --selftest: OK
```

### `TASK39_BASELINE=c8a2010 ruby .claude/scripts/task39-wiring.rb`

exit 1。現行実装に対する RED（makeCoordinator の戻り型・current 更新）と、rb/テスト同一性 NG（再凍結待ち）。dismantle 引数型も新検査として NG。

```
task39-wiring: NG 基準時点の受け入れテストが現在と同一ではない
task39-wiring: NG 基準時点の rb 自身が現在と同一ではない
task39-wiring: NG makeCoordinator の戻り型が TerminalMountCoordinator ではない
task39-wiring: NG updateNSView で context.coordinator.current = coordinator が到達可能ではない
task39-wiring: NG dismantleNSView の引数型が TerminalMountCoordinator ではない
```

### `bash macos/scripts/run-swift-tests.sh TerminalUI`

exit 1。新 2 ケースが `TerminalMountCoordinator` 不在でコンパイルエラー（RED）。変更は退避していない。

```
=== swift test --package-path Packages/TerminalUI  [全数] ===
[0/1] Planning build
[1/1] Compiling plugin GenerateManual
[2/2] Compiling plugin GenerateDoccReference
Building for debugging...
[2/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/7] Emitting module TerminalUITests
[6/7] Compiling TerminalUITests AcceptanceTerminalMountOwnershipTests.swift
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:243:20: error: cannot find type 'TerminalMountCoordinator' in scope
241 |         let c = makeContainer()
242 |         let oldTile = makeContainer()
243 |         let mount: TerminalMountCoordinator = TerminalView(coordinator: x).makeCoordinator()
    |                    `- error: cannot find type 'TerminalMountCoordinator' in scope
244 |         #expect(c.window == nil)
245 | 

/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:268:21: error: cannot find type 'TerminalMountCoordinator' in scope
266 |         let containerA = makeContainer()
267 |         let containerB = makeContainer()
268 |         let mountA: TerminalMountCoordinator = TerminalView(coordinator: x).makeCoordinator()
    |                     `- error: cannot find type 'TerminalMountCoordinator' in scope
269 | 
270 |         #expect(TerminalMount.attach(x.hostingView, to: containerA) == true)
error: fatalError
run-swift-tests: FAILED -> TerminalUI
```

## 判断に迷った点

1. 契約の (a) は `attach(x,c)` → `current=y` → `attach(y,c)` だが、レビュアー再現は先に `attach(y, oldTile)` する。formerOwners に旧タイルが入らないと、破棄漏れでも新規コンテナへの takeover が成功し得るため、再現テスト側を採用して先に oldTile へ載せた。
2. `let mount = TerminalView(...).makeCoordinator()` だけだと推論型は現行の `TerminalCoordinator` になり、(b) はコンパイルが通る。改訂 2 の公開面と「TerminalMountCoordinator 不在で RED」を両立するため、両ケースに型注釈を付けた。
3. (b) は同一端末の A→B なので `mount.current = y` は置いていない。A の mount coordinator を破棄引数にする形だけを新形へ合わせた。
4. 通常検査の NG は指定の 2 項目＋同一性に加え、dismantle 引数型も出る。新検査の一部なので追加の握りつぶしはしていない。

=== REPORT COMPLETE ===
