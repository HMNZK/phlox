---
status: completed

# task-39 受け入れテスト・配線検査 改訂（敵対レビュー指摘 1〜6）

HEAD: `a8ea61a`（`a8ea61aecd2b834948b589669893f12c47c7db62`）。製品コード・契約・台帳・仕様は未変更。git commit なし。

現行 `TerminalView.swift` に `dismantleNSView` は無い。`NSViewRepresentable` 既定の `Coordinator` は `Void`（コンパイルエラー `expected argument type 'Void'` で確認）。凍結テストは `makeCoordinator() -> TerminalCoordinator` を前提に `TerminalView.dismantleNSView(_:coordinator: TerminalCoordinator)` を直接呼ぶ。

## 指摘 1〜6 の対応表

| 指摘 | 対応 | テストケース / rb 関数 | file:line |
|---|---|---|---|
| 1 | HEAD 不一致による自己比較拒否を廃止。凍結検証は ①HEAD の祖先 ②基準時点 TV に `TerminalMount.detach` 無し ③基準時点のテストと rb が `git show <sha>:<path>` で現在と同一。凍結 HEAD 上の未コミット実装は拒否しない | `git_is_ancestor?` / `workdir_matches_git_blob?` / `baseline_tv_has_detach?` / `check_frozen_baseline` / `baseline_env_errors` | `.claude/scripts/task39-wiring.rb:164` / `:168` / `:286` / `:332` / `:419`（呼出 `:1225`） |
| 2a | X→Y 差し替え後の実破棄で Y 解放・X は影響なし | `dismantleAfterCoordinatorSwapReleasesYNotX` | `AcceptanceTerminalMountOwnershipTests.swift:238`（呼出 `:250`） |
| 2b | A→B 後の A 破棄が B の所有権を解放しない（`hostingView.superview === B`） | `dismantleStaleADoesNotReleaseB` | `AcceptanceTerminalMountOwnershipTests.swift:256`（呼出 `:265`） |
| 2 rb | dismantle 内の到達可能な detach（`if false`・コメント外）が `coordinator.hostingView` を引数にする | `strip_if_false_blocks` / `reachable_code` / `check_dismantle_reaches_detach` | `:173` / `:188` / `:733` |
| 3 | X: A→B、Y: A、X の A 再 attach は false、`X.superview === B`、`Y.superview === A` | `staleReattachOfXDoesNotRemoveYFromA` | `AcceptanceTerminalMountOwnershipTests.swift:272` |
| 4 | attach は TerminalView.swift 内のどの関数でも可。すべての `scrollToBottom` 予約が attach 成功（true）に条件付け | `check_terminal_mount` / `scroll_reservation_errors` / `all_scrolls_attach_gated?` | `:698` / `:261` / `:249` |
| 5 | 通常検査と `--selftest` を `check_extra_logs` に統一。コメント・文字列除去後に `print` / `os_log` / `Logger` 呼び出し数を baseline と比較 | `check_extra_logs` / `log_counts` | `:447` / `:437`（通常呼出 `:1261`） |
| 6 | 契約 frontmatter `baseline_commit` の欠落・プレースホルダ・不正値・`TASK39_BASELINE` 不一致を NG。現時点はプレースホルダのため NG。凍結時に PM が実 SHA へ置換する | `parse_contract_baseline_text` / `contract_baseline_errors` | `:296` / `:307`（通常呼出 `:1216`） |

## コマンド原文

### 最終テストファイルで `bash macos/scripts/run-swift-tests.sh TerminalUI`

`detach` 不在と、凍結した `dismantleNSView` の `Coordinator` 型（`TerminalCoordinator` vs 既定 `Void`）でコンパイル RED。

```
=== swift test --package-path Packages/TerminalUI  [全数] ===
[6/8] Compiling TerminalUITests AcceptanceTerminalMountOwnershipTests.swift
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
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:250:62: error: cannot convert value of type 'TerminalCoordinator' to expected argument type 'Void'
250 |         TerminalView.dismantleNSView(container, coordinator: terminalY)
    |                                                              `- error: cannot convert value of type 'TerminalCoordinator' to expected argument type 'Void'
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift:265:63: error: cannot convert value of type 'TerminalCoordinator' to expected argument type 'Void'
265 |         TerminalView.dismantleNSView(containerA, coordinator: coordinator)
    |                                                               `- error: cannot convert value of type 'TerminalCoordinator' to expected argument type 'Void'
error: fatalError
run-swift-tests: FAILED -> TerminalUI
```

### detach 関連を一時 `#if false` したアサーション RED

`TerminalMount.detach` を呼ぶ 5 ケースと、Coordinator 型不一致の dismantle 2 ケースを一時 `#if false`。記録後にすべて戻した。残した「A の後着 update」と新規「2 端末」はアサーション失敗（RED）。現行 `attach` は後着 A を受け入れ、A 上の別端末 Y を subview ループで除去する。

```
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:90:9: Expectation failed: (stale → true) == false
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:91:9: Expectation failed: (coordinator.hostingView.superview → <NSView: 0x919ed7c00>) === (containerB → <NSView: 0x919ed7700>)
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:92:9: Expectation failed: (containerB.subviews.first → nil) === (coordinator.hostingView → <TerminalUI.TerminalHostingView: 0x919ed7980>)
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:93:9: Expectation failed: (containerA.subviews → [<TerminalUI.TerminalHostingView: 0x919ed7980>]).isEmpty → false
✘ Test "A の後着 update が再び attach しても false で superview は B のまま" failed after 0.006 seconds with 4 issues.
✘ Test "X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:293:9: Expectation failed: (stale → true) == false
✘ Test "X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:294:9: Expectation failed: (terminalX.hostingView.superview → <NSView: 0x919ed4f00>) === (containerB → <NSView: 0x919ed4a00>)
✘ Test "X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:295:9: Expectation failed: (terminalY.hostingView.superview → nil) === (containerA → <NSView: 0x919ed4f00>)
✘ Test "X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:296:9: Expectation failed: (containerA.subviews.first → <TerminalUI.TerminalHostingView: 0x919ed6f80>) === (terminalY.hostingView → <TerminalUI.TerminalHostingView: 0x919ed4c80>)
✘ Test "X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま" recorded an issue at AcceptanceTerminalMountOwnershipTests.swift:297:9: Expectation failed: (containerB.subviews.first → nil) === (terminalX.hostingView → <TerminalUI.TerminalHostingView: 0x919ed6f80>)
✘ Test "X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま" failed after 0.008 seconds with 5 issues.
✘ Suite "task-39: terminal mount ownership" failed after 0.309 seconds with 9 issues.
✘ Test run with 72 tests in 16 suites failed after 0.313 seconds with 9 issues.
run-swift-tests: FAILED -> TerminalUI
```

2 端末ケースは戻り値が true になるだけでなく、Y が A から外れる（指摘 3 の反証）。`#if false` は取り除き、最終ファイルは全ケースを含む。

### 新規ファイル退避後の既存テスト

`AcceptanceTerminalMountOwnershipTests.swift` を `/tmp` へ退避して同コマンド。終了後に戻した。

```
=== swift test --package-path Packages/TerminalUI  [全数] ===
✔ Test run with 66 tests in 15 suites passed after 0.329 seconds.
run-swift-tests: OK (TerminalUI / git別パス:WorktreeIsolationSpawnTests AcceptanceRestoreAbortNoSpawnTests / 直列:DashboardFeature)
EXISTING_EXIT:0
RESTORED:yes
```

### `ruby .claude/scripts/task39-wiring.rb --selftest`

```
task39-wiring --selftest: OK
```

exit 0。負例は主張どおり NG: `if false` の detach、detach 引数が `coordinator.hostingView` ではない、無条件 `scrollToBottom` 予約、追加 `print` / `os_log` / `Logger`、同一行への `os_log` 追加、契約 `baseline_commit` の欠落・プレースホルダ・不正、HEAD リテラル / `HEAD~1` / ブランチ名。正例: コメント内 `os_log` は追加ではない、attach が helper にあっても合格、HEAD と一致し得る SHA 形式は拒否しない。

### `TASK39_BASELINE=$(git rev-parse --short HEAD) ruby .claude/scripts/task39-wiring.rb`

`git rev-parse --short HEAD` は `a8ea61a`。exit 1。HEAD 一致の自己比較拒否は出ない（指摘 1）。

```
task39-wiring: NG 契約 baseline_commit がプレースホルダ（凍結時に実 SHA へ置換する）
task39-wiring: NG 基準時点の受け入れテストを git show できない（git show a8ea61aecd2b834948b589669893f12c47c7db62:macos/Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift）
task39-wiring: NG 基準時点の rb 自身を git show できない（git show a8ea61aecd2b834948b589669893f12c47c7db62:.claude/scripts/task39-wiring.rb）
task39-wiring: NG TerminalMount.detach(_:from:) -> Bool が無い
task39-wiring: NG dismantleNSView または同等経路から TerminalMount.detach に到達しない
```

| NG | 凍結・実装後に解消する見込み |
|---|---|
| 契約 `baseline_commit` プレースホルダ | 凍結時に PM が frontmatter を実 SHA へ置換する（契約変更は凍結作業。本改訂では触っていない） |
| 受け入れテストを `git show` できない | 凍結コミットにテストファイルを含める |
| rb 自身を `git show` できない | 凍結コミットで `git add -f .claude/scripts/task39-wiring.rb`（`.claude/` は gitignore） |
| `TerminalMount.detach` が無い | 実装が公開面どおり `detach(_:from:) -> Bool` を追加する |
| dismantle から detach に到達しない | 実装が到達可能な `dismantleNSView` から `TerminalMount.detach(coordinator.hostingView, …)` を呼ぶ |

凍結 HEAD 上で未コミット実装しても、基準 SHA==HEAD だけでは拒否しない。残るのは上記の内容検査だけ。

## 判断に迷った点

1. 現行 `dismantleNSView` の実シグネチャはプロトコル既定の `coordinator: Void`。rb が「現在の mount が扱う端末（`coordinator.hostingView`）」を要求するため、テストは `TerminalCoordinator` を渡す形で凍結した。実装は `makeCoordinator() -> TerminalCoordinator` が必要。
2. アサーション RED の一時 `#if false` は `detach` 呼び出しだけでなく dismantle 2 ケースも含めた（Coordinator 型不一致でコンパイルできない）。2 端末ケースは `attach` のみなので残した。
3. 契約 `baseline_commit` は `"PM が凍結時に設定"` のまま（契約変更禁止）。rb はプレースホルダを NG にする。凍結時に PM が実 SHA へ置換し、`TASK39_BASELINE` と一致させる。そのとき初めてこの NG は消える。

=== REPORT COMPLETE ===
