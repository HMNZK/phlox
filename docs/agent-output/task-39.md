---
task: task-39
status: completed
---
## 詰まった点

なし。

## 実は未完

- PM 目視ゲート（再現 A/B/C・PNG）は契約どおり実装役の範囲外。未実施。アプリは起動していない。
- `TerminalCoordinator.swift` と `TerminalHostingView.swift` は未変更。所有権台帳（`TerminalMount.attach/detach`）は前回のまま。
- 受け入れテストは `mount.current = y` を直接代入して破棄を呼ぶ。製品の `updateNSView` がその代入を attach 前に行うことは配線検査とソースで確認したが、実 SwiftUI ライフサイクル上の `dismantleNSView` 呼び出しは単体では観測していない。

## 置いた前提

- **mount 同一性**: `makeCoordinator()` は mount ごとに `TerminalMountCoordinator` を 1 個生成する。SwiftUI が struct を再評価してもこのオブジェクトは差し替えない。セッションの `TerminalCoordinator` は `var current` に保持し、所有者 ID を再発行しない。コンテナ識別子は従来どおり `makeNSView` の NSView。
- **current 更新のタイミング**: `updateNSView` は `context.coordinator.current = coordinator` を `TerminalMount.attach` より前に実行する。破棄時の `coordinator.hostingView` は常に最後に update された端末（差し替え後の Y）を指す。whitebox が固定する `guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }` は `self.coordinator`（再評価後の端末）を渡す文字列のまま残した。代入後は `current.hostingView` と同じインスタンスになる。
- **公開面**: `TerminalMountCoordinator` は `public`。`public func makeCoordinator() -> TerminalMountCoordinator` の戻り型可視性のためで、契約の「`@testable` で可視」は満たす。外部向け API を広げる意図はない。
- **所有権台帳**: `NSMapTable<NSView, Record>.weakToStrongObjects()`、`weak var owner`、`formerOwners` の弱参照ハッシュ。プロセス寿命の強参照台帳は置かない。判定は subview 操作より先。連続 update と formerOwners の後着は false。owner が nil なら former を捨てて再接続を許す。
- `window == nil` / frame 0 では拒否しない。`scrollToBottom` は attach 成功時だけ。`[BUG01]` / `Bug01Trace` / 追加ログは入れていない。

## 契約からの逸脱

なし。許可パス外・テスト・rb・契約・台帳は変更していない。`dismantleNSView` は `TerminalMount.detach(coordinator.hostingView, from: nsView)`。TerminalMount の所有権規則は据え置き。

## テスト結果

```
task39-wiring --selftest: OK
```

```
task39-wiring: OK
```

```
✔ Test run with 79 tests in 16 suites passed after 0.332 seconds.
run-swift-tests: OK (TerminalUI / git別パス:WorktreeIsolationSpawnTests AcceptanceRestoreAbortNoSpawnTests / 直列:DashboardFeature)
```

```
Build complete! (12.60s)
```

`git diff --check` は空。製品差分は `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift` のみ（+16 / −4）。

## App ビルド結果

指定コマンドを `macos/` で実行。exit 0。

```
** BUILD SUCCEEDED **
```

ログ `/tmp/phlox-t13-visual.SPfR9c/build-t39c.log`。成果物 `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`。警告 `Metadata extraction skipped. No AppIntents.framework dependency found.` は既存の appintentsmetadataprocessor。アプリ起動なし。Release 不接触。

## レビュー重点

- 差し替え後の破棄: `makeCoordinator()` で得た同一 `TerminalMountCoordinator` に `current = y` したあと `dismantleNSView` が Y を外し、X を触らず、Y が旧タイルへ再 attach できるか（受け入れ `dismantleAfterCoordinatorSwapReleasesYNotX`、レビュー repro_test）。
- A→B のあと A の mount 破棄が B の所有権を残すか（`dismantleStaleADoesNotReleaseB`）。
- `updateNSView` の `current` 代入が attach より前か。guard 行の文字列が whitebox どおりか。
- `dismantle` が `coordinator.hostingView`（= `current.hostingView`）を渡し、初期 X の別プロパティを見ていないか。
- TerminalMount の formerOwners / 2 端末ケース / 連続 update が今回の Coordinator 差し替えで壊れていないか。

=== REPORT COMPLETE ===
