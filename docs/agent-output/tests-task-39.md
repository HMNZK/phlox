---
status: completed

# task-39 受け入れテスト・配線検査（凍結用 RED）

HEAD: `510a512`（`510a512ad532dad43cf7445fef90fe92c7b2982b`）。製品コードは未変更。契約・台帳・仕様は未変更。git commit なし。

## 現行 `TerminalMount` API

`macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift` の `enum TerminalMount`（`@MainActor`、モジュール内）。

| 面 | 現状 |
|---|---|
| `static func attach(_ terminal: NSView, to container: NSView) -> Bool` | **ある**。`superview !== container` なら旧親から外して新親へ追加し `true`。同一親なら `false`。所有権・失効 mount の記録はない |
| `static func detach(_ terminal: NSView, from container: NSView) -> Bool` | **無い** |

`terminal` には既存テストと同じく `TerminalCoordinator().hostingView`（実 `NSView`）を渡す。ウィンドウは載せない。

## 作成ファイル

| パス | 内容 |
|---|---|
| `macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift` | 成功基準 1。Swift Testing / `@MainActor` / `@testable import TerminalUI`。事後条件表 8 行を各 1 ケース。成功基準 1 のセッション切替・出力保持を追加 2 ケース。superview は `===`。期待値は契約リテラル |
| `.claude/scripts/task39-wiring.rb` | 成功基準 2。`--selftest` 付き。`TASK39_BASELINE` 必須。`HEAD` / `HEAD~1` / ブランチ名 / 未設定はフォールバックせず NG。実装後の HEAD 自己比較は NG。実装前の freeze SHA==HEAD は許可 |

`.claude/` は `.gitignore` されている。凍結コミット時は `git add -f .claude/scripts/task39-wiring.rb` が必要。

## コマンド原文

### アサーション RED（契約 PM 決定 3）

`detach` が無く全体はコンパイルできない。`detach` を呼ぶ 5 ケースだけを一時的に `#if false` し、現行 `attach -> Bool` だけで実走した。記録後に `#if false` は取り除き、最終ファイルは全 8 行＋追加 2 ケース。

```
=== swift test --package-path Packages/TerminalUI  [全数] ===
…
✔ Test "未接続の端末を A に attach すると true で superview は A" passed after 0.179 seconds.
✔ Test "同じ端末を新 mount B に attach すると true で superview は B" passed after 0.085 seconds.
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:90:9: Expectation failed: (stale → true) == false
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:91:9: Expectation failed: (coordinator.hostingView.superview → <NSView: 0xa9b5c5900>) === (containerB → <NSView: 0xa9b5c5b80>)
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:92:9: Expectation failed: (containerB.subviews.first → nil) === (coordinator.hostingView → <TerminalUI.TerminalHostingView: 0xa9b5c5680>)
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:93:9: Expectation failed: (containerA.subviews → [<TerminalUI.TerminalHostingView: 0xa9b5c5680>]).isEmpty → false
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" failed after 0.003 seconds with 4 issues.
✔ Test "B の連続 update は false で superview・subview 数・有効制約は変わらない" passed after 0.005 seconds.
✔ Test "載せ替え後も coordinator・hostingView・terminalView と feed 済み出力を保持する" passed after 0.009 seconds.
✘ Suite "task-39: terminal mount ownership" failed after 0.283 seconds with 4 issues.
✘ Test run with 71 tests in 16 suites failed after 0.296 seconds with 4 issues.
run-swift-tests: FAILED -> TerminalUI
```

現行 `attach` は後着の A を新しい接続として受け入れ `true` を返し、`hostingView.superview` は A に戻る（奪い返し）。コンパイル失敗だけを効力の証拠にしていない。

### 最終ファイルで `bash macos/scripts/run-swift-tests.sh TerminalUI`

```
=== swift test --package-path Packages/TerminalUI  [全数] ===
[6/7] Compiling TerminalUITests AcceptanceTerminalMountOwnershipTests.swift
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:124:38: error: type 'TerminalMount' has no member 'detach'
124 |         let detached = TerminalMount.detach(coordinator.hostingView, from: containerA)
    |                                      `- error: type 'TerminalMount' has no member 'detach'
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:139:41: error: type 'TerminalMount' has no member 'detach'
139 |         let firstDetach = TerminalMount.detach(coordinator.hostingView, from: containerB)
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:140:42: error: type 'TerminalMount' has no member 'detach'
140 |         let secondDetach = TerminalMount.detach(coordinator.hostingView, from: containerB)
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:156:31: error: type 'TerminalMount' has no member 'detach'
156 |         #expect(TerminalMount.detach(coordinator.hostingView, from: containerB) == true)
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:174:31: error: type 'TerminalMount' has no member 'detach'
174 |         #expect(TerminalMount.detach(coordinator.hostingView, from: containerB) == true)
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:201:42: error: type 'TerminalMount' has no member 'detach'
201 |         let staleRelease = TerminalMount.detach(terminalX.hostingView, from: container)
error: fatalError
run-swift-tests: FAILED -> TerminalUI
```

### 新規ファイル退避後の既存テスト

`AcceptanceTerminalMountOwnershipTests.swift` を `/tmp` へ退避して同コマンド。終了後に戻した。

```
=== swift test --package-path Packages/TerminalUI  [全数] ===
✔ Test run with 66 tests in 15 suites passed after 0.278 seconds.
run-swift-tests: OK (TerminalUI / git別パス:WorktreeIsolationSpawnTests AcceptanceRestoreAbortNoSpawnTests / 直列:DashboardFeature)
EXISTING_EXIT:0
RESTORED:yes
```

既存テストは壊していない。

### `ruby .claude/scripts/task39-wiring.rb --selftest`

```
task39-wiring --selftest: OK
```

exit 0。

### `TASK39_BASELINE=$(git rev-parse --short HEAD) ruby .claude/scripts/task39-wiring.rb`

`git rev-parse --short HEAD` は `510a512`。未実装のため RED（exit 1）。

```
task39-wiring: NG TerminalMount.detach(_:from:) -> Bool が無い
task39-wiring: NG dismantleNSView または同等経路から TerminalMount.detach に到達しない
```

未設定と `HEAD` リテラルもフォールバックせず NG（併記）。

```
task39-wiring: NG TASK39_BASELINE が未設定（HEAD にフォールバックしない）
task39-wiring: NG TerminalMount.detach(_:from:) -> Bool が無い
task39-wiring: NG dismantleNSView または同等経路から TerminalMount.detach に到達しない
```

```
task39-wiring: NG TASK39_BASELINE に HEAD は使えない（自己比較禁止）
task39-wiring: NG TerminalMount.detach(_:from:) -> Bool が無い
task39-wiring: NG dismantleNSView または同等経路から TerminalMount.detach に到達しない
```

## 事後条件表 → テストケース

| 操作（契約表） | テスト |
|---|---|
| 未接続の端末を A に attach → `true`、superview は A | `unconnectedTerminalAttachesToA` |
| 同じ端末を新 mount B に attach → `true`、superview は B | `newMountBTakesOwnership` |
| A の後着 update が再び attach → `false`、superview は B のまま | `staleOwnerACannotStealFromB` |
| B の連続 update → `false`、superview は B のまま | `consecutiveUpdateOnBIsNoOp`（subview 数・有効ピン制約の不変も含む） |
| B 所有中に A が detach → `false`、B 維持 | `staleOwnerACannotDetachWhileBOwns` |
| B が detach → `true`、superview は `nil` | `ownerBDetachReleasesAndSecondDetachFails`（再 detach `false` も含む） |
| B 解放後に生存している A が改めて attach → `true`、superview は A | `survivingACanReattachAfterBRelease` |
| B 解放後に新しい C が attach → `true`、superview は C | `newCCanAttachAfterBRelease` |

成功基準 1 の追加:

| 必須ケース | テスト |
|---|---|
| 単一コンテナのセッション切替 X→Y→X。X の遅れた detach は Y を外さない | `sameContainerSessionSwitchXYX` |
| 固定文字列 `KEEP-OUTPUT-TASK39` を feed し、coordinator / hostingView / terminalView の同一性と出力保持 | `remountKeepsIdentityAndFedOutput` |

コンテナは実ウィンドウに載せない。`window == nil` でも B / C へ接続できることを `#expect(container.window == nil)` で固定。

## rb 検査項目 → 実装箇所

| 成功基準 2 | 関数 |
|---|---|
| `TASK39_BASELINE` 未設定・空・`HEAD`・`HEAD~*`・ブランチ名・不正 SHA。実装後の HEAD 自己比較禁止。フォールバック禁止 | `baseline_env_errors` / 通常検査本体 |
| 契約 `baseline_commit` が hex SHA のとき一致を要求 | 通常検査本体（プレースホルダの間はスキップ） |
| DashboardView の詳細呼び出し・モード変更・選択変更が baseline と同じ | `check_dashboard_paths` + `UNCHANGED_PATHS` の `check_normalized_unchanged` |
| DashboardDetailView の single/grid/team・`selectedSession`・`focusedID`・PTY/appServer | `check_detail_branches` + 同上 |
| SessionView / SessionGridView / PaneLayoutView の `TerminalView` と coordinator | `check_session_terminal_calls` + 同上 |
| TerminalView の attach が `TerminalMount` 経由のみ。成功時だけ非同期スクロール。迂回 `addSubview` 禁止 | `check_terminal_mount` |
| attach 追加は TerminalView.swift 内に限り許容。他ファイルは baseline と一致 | `check_foreign_mount_calls` / PM 決定 4 |
| dismantleNSView または同等から `TerminalMount.detach`。テスト専用では不合格 | `check_dismantle_reaches_detach` |
| SessionViewModel の直接 attach/detach は 0。`bindCoordinator` / `handleResize` / feed | `check_session_vm_paths` + ファイル不変 |
| `setFrameSize`→非同期 refresh、`sizeChanged`→`onResize` | `check_size_drawing` + `check_func_unchanged` |
| ADR-0116 `GridChatColumn` の live resize 幅保持・開始終了通知 | `check_grid_chat_live_resize` + ファイル不変 |
| `[BUG01]`・`Bug01Trace` 不在。baseline からの追加 `os_log` / `Logger` / `NSLog` | `check_investigation_walk` + `check_extra_logs_via_git` |
| `TerminalOpenAtBottomWhiteboxTests` の弱体化なし（ガード文字列・2 ケース名） | `check_whitebox` + ファイル不変 |
| `--selftest` の正例・負例（分岐削除、coordinator 差し替え、迂回、戻り値破棄、文字列偽装、baseline 不正） | `run_selftest` |

## 判断に迷った点

1. 契約は表 8 行と成功基準 1 の 6 必須ケースの両方を求める。8 行を各 1 ケースにし、表に無い「X→Y→X」と「feed 保持」だけ追加した。表 4 行に制約不変、表 6 行に再 detach を織り込み、必須ケース 3・4 と二重にしない。
2. 契約 `baseline_commit` はまだ `"PM が凍結時に設定"`。hex SHA のときだけ一致検査する。プレースホルダとの不一致で通常検査を止めない（契約変更禁止のためプレースホルダは直せない）。
3. 実装前の freeze では `TASK39_BASELINE` が HEAD SHA と一致する。`detach` が無い間は自己比較拒否しない。`detach` / `dismantleNSView` が見えたあとに HEAD を baseline にするのは拒否する。
4. 追加ログ検査から `print(` は外した。既存の正当な `print` を追加分と誤認しやすい。`os_log` / `Logger` / `NSLog` と `[BUG01]` を対象にした。
5. DashboardFeature 全ファイルを Ruby の文字列状態機械で読むと数十秒かかる。不変ファイルは normalize 比較、調査コードは 3 パッケージの cheap `include?` と `git grep` にした。呼び出しの有無はコメント・文字列をマスクしたうえで `TerminalView` / `SessionViewModel` / `DashboardView` を見る。

=== REPORT COMPLETE ===
