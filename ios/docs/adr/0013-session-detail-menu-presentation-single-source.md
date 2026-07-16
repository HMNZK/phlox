---
status: active
last-verified: 2026-07-15
---

# ADR 0013: セッション詳細の右上メニュー由来 presentation を .sheet/.alert の別 View 層分離＋enum 単一ソースにする

> **このファイルの役割**: wave-5（task-3）で、右上メニューの「モデル変更」「名前変更」が連続タップで開かなくなる症状を、presentation を単一 View に積み重ねない構造へ変更して修正した決定を記録する。
> **書かないもの**: モデル選択・rename の API 呼び出し詳細（→ [architecture/overview.md](../architecture/overview.md)）。ライブアクティビティ等の無関係な変更。

## 文脈

セッション詳細画面の右上メニュー（ellipsis）から開く「モデル変更」「名前変更」が、実機で複数回タップすると（あるいは初回から）シート/アラートが表示されないことがある症状があった。PM のコード解析による高確度仮説（task-3.md PM 支給）は次の複合:

- `SessionDetailView.swift` の外側 `ZStack` に `.sheet(isPresented: $viewModel.isModelSheetPresented)`・`.alert(..., isPresented: $viewModel.isRenamePresented)`・`.navigationDestination(item: $selectedSubAgentID)` が**すべて同一 View に併置**されていた。
- `.task(id: session.id)` の 3秒間隔ポーリングが `@Observable` の状態を更新し、body を高頻度で再評価していた。
- この2つの複合により、SwiftUI が modal presentation の提示フラグ変化を取りこぼす（同一 View への複数 presentation modifier 併置＋高頻度 body churn の既知の脆弱パターン）。

固定 delay 等の対症療法は task-3.md で明示的に禁止されていた。

## 決定

- `.sheet(isPresented: $viewModel.isModelSheetPresented)` を外側 `ZStack`（`.alert` と同じ階層）から、チャットスクロール＋`inputBarSection` を含む**内側 VStack へ移設**し、`.alert` とは別の View 階層に分離した。
- `SessionDetailViewModel` に `private enum MenuPresentation { case modelPicker, rename }` を新設し、`menuPresentation: MenuPresentation?` を**単一ソース**とした。`isModelSheetPresented`/`isRenamePresented` はこの enum への computed property（getter/setter）として再実装し、一方が立てば他方は自動的に `nil` へ戻る形で排他化した。
- `beginModelSelection()`/`beginRename()` は `menuPresentation` を直接設定する薄い API とした。

## 結果

- 2つの presentation modifier が同一 View インスタンスに積み重ならなくなり、SwiftUI の取りこぼしパターンを回避した。
- モデル選択と rename が状態上も排他化され、同時に両方 open される余地がなくなった。
- stage-1 レビューでは「コードは妥当だが症状を再現/ガードする自動テストが無い」として needs_changes、フェーズ4で新規 XCUITest `Wave5RegressionUITests.swift`（`testRenameReopensRepeatedly`＝連続3回開閉、`testModelChangeThenRenameBothOpen`＝モデル変更→名前変更の両方が開くこと）を実走し 3/3 pass。これをもって受理ゲートを満たし `done` 確定（decision-log wave-5 フェーズ4）。

## 却下した代替案

- **固定 delay / `DispatchQueue.main.asyncAfter` によるタイミング調整**: 対症療法であり、task-3.md のレビュー観点で明示的に不可とされた。
- **enum 単一化のみ行い View 層分離をしない（あるいはその逆）**: PM 仮説が「同一 View への複数 presentation 併置」と「頻繁な body 再評価」の複合を真因としていたため、いずれか一方だけでは再発余地が残ると判断し、両方を併用した。
