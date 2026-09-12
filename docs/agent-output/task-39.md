---
task: task-39
status: completed
---
## 詰まった / 完了できなかった点

なし。前回の Stop フック 2 本は、PM 承認のハーネス修理 2 点のあと、`--selftest` は OK、本検査は「基準時点の rb 自身が現在と同一ではない」の 1 項目だけ NG。後者は PM の rb 単独コミットと再凍結待ち。

## できた風だが実は未完（最重要）

- PM 目視ゲート（再現 A/B/C・PNG）は契約どおり実装役の範囲外。未実施。
- `makeCoordinator()` はセッションの `TerminalCoordinator` を返す。SwiftUI が同一 representable で coordinator を X→Y に差し替えたあと、`dismantleNSView` に渡るのが make 時点の X だと、rb が要求する `coordinator.hostingView` 経路では Y を明示 detach しない。受け入れテストは現在の Y を直接渡すので緑になる。コンテナ破棄時は owner の弱参照が nil になり、次の正当な attach は受け入れる。同一コンテナの X→Y→X は `TerminalMount.attach` 側で解放・再接続する（テスト済み）。

## 置いた前提・仮定（所有権の保持方法、mount 同一性の担保方法を明記）

- **所有権の保持**: `TerminalMount` 内の `NSMapTable<NSView, Record>.weakToStrongObjects()`。キーは `hostingView`（terminal）。値は現所有者 `weak var owner` と、所有権を奪われた旧コンテナの `NSHashTable.weakObjects()`（formerOwners）。プロセス寿命の強参照台帳は置かない。`TerminalCoordinator` / `TerminalHostingView` は未変更（`setFrameSize` / `sizeChanged` を baseline と一致させる）。
- **判定**: 所有権確認を subview 除去より先に行う。`owner === container` なら連続 update で false（制約を足さない）。`owner != nil` かつ container が formerOwners にいるなら旧 mount の後着で false（別端末を消さない）。owner が nil のときは former を捨て、生存 A も新 C も attach 可。新コンテナ（former に無い）からの接続は、現所有者からの正当な載せ替えとして true。同一コンテナへ別端末を載せたときは、旧端末を所有者 detach 相当で解放してから新端末を載せる。
- **mount 同一性**: `makeCoordinator() -> TerminalCoordinator` がセッション coordinator を返し、struct 再評価で所有者 ID を新規発行しない。コンテナは `makeNSView` の NSView が mount の識別子。`dismantleNSView` は `TerminalMount.detach(coordinator.hostingView, from: nsView)` のみ。旧コンテナの破棄は、そのコンテナが現所有者でない限り false。
- `window == nil` / frame 0 では拒否しない。`scrollToBottom` は既存どおり `guard TerminalMount.attach(...) else { return }` の後だけ。PTY・バッファ・`setFrameSize`→refresh・ADR-0116 は未変更。`[BUG01]` / `Bug01Trace` / 追加ログは入れていない。

## 契約からの逸脱

製品 API・事後条件・allowed_paths からの逸脱は無い。`TerminalHostingView.swift` と `TerminalCoordinator.swift` は触っていない。公開面を `attach/detach -> Bool` 以外に広げていない。

ハーネス修理 2 点は PM 裁定（decision-log 2026-09-13T04:19:00+0900）で承認済み。契約「ハーネス欠陥は PM 承認のうえハーネス部分に限り修理可」に基づき、`.claude/scripts/task39-wiring.rb` のみを次のとおり直した。他の検査・負例・製品コード・テスト・契約は変更していない。

1. `--selftest` の正例「現行 TerminalView 基準は detach 無し」が作業ツリーを `File.read` していたのを、`TASK39_BASELINE` または契約 `baseline_commit` の blob を `git show <sha>:macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift` で読むようにした。基準 SHA が無ければその正例だけ「基準未指定のためスキップ」と明示し、他の正負例は実行する。
2. 契約 frontmatter の `baseline_commit` 読み取りを、引用符あり（`baseline_commit: "a43113a"`）と引用符なし（`baseline_commit: a43113a`）の両方を受理するようにした。プレースホルダ・欠落・不正値・環境変数不一致の NG は維持。

**rb 自身の同一性 NG は PM の再凍結待ち。** `TASK39_BASELINE=a43113a ruby .claude/scripts/task39-wiring.rb` は「基準時点の rb 自身が現在と同一ではない」の 1 項目だけ NG。PM が rb を単独コミットして `baseline_commit`・`TASK39_BASELINE`・`BASELINES.txt` を更新すれば解消する。製品側の NG は無かった。

## テスト結果（rb 2 本・TerminalUI 全数・SessionFeature build の要約行を引用）

```
task39-wiring --selftest: OK
```

```
task39-wiring: NG 基準時点の rb 自身が現在と同一ではない
```

```
✔ Test run with 79 tests in 16 suites passed after 0.324 seconds.
run-swift-tests: OK (TerminalUI / git別パス:WorktreeIsolationSpawnTests AcceptanceRestoreAbortNoSpawnTests / 直列:DashboardFeature)
```

```
Build complete! (6.50s)
```

`git diff --check` は空。本ラウンドの rb 差分は上記 2 点のみ。製品差分は前回からの継続で `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift` のみ（+70 / −10）。本ラウンドでは製品コードを変更していない。

## App ビルド結果（xcodebuild 末尾）

本ラウンドでは製品コード未変更のため App 再ビルドは未実施。前回（製品差分投入後）:

```
** BUILD SUCCEEDED **
```

exit 0。ログ `/tmp/phlox-t13-visual.SPfR9c/build-t39.log`。成果物 `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`。アプリ起動はしていない。Release Phlox には未接触。

## レビュー重点（PM 用）

- B 接続後の A 再 attach が false で superview が B のままか（受け入れ `staleOwnerACannotStealFromB`）。再描画や待ち時間で隠していないか。
- formerOwners が「新コンテナの正当な takeover」と「旧コンテナの後着」を分けているか。X を A→B、Y を A に載せたあと X の A 再 attach が Y を消さないか。
- 所有者 detach のあと A／C が再接続できるか（永久禁止にしていないか）。同一コンテナ X→Y→X と、X の遅延 detach が Y を外さないか。
- `dismantleNSView` が到達可能な `detach(coordinator.hostingView, from:)` か。A の後着破棄が B を解放しないか。
- Whitebox の `guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }` と非同期 `scrollToBottom` 文字列が残っているか。
- rb の残 NG は製品差分ではなく、修理後 rb と凍結 blob の不一致。PM の rb 単独コミットと再凍結を先に見るべき。

=== REPORT COMPLETE ===
