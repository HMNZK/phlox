---
status: completed
last-verified: 2026-07-16
---

# 0003: 両サイドバー表示の右サイドバー見切れ修正＋エージェントカード縦積み — 作業ログ

> **このファイルの役割**: 本 run（agentic-loop / backend=external / feature/fix-dual-sidebar-layout）の作業経緯スナップショット。
> **書かないもの**: 決定の理由（→ [adr/0090](../adr/0090-dual-sidebar-pane-width-clamp-and-card-stacking.md)）、現行仕様（→ [architecture/dashboard-pane-layout.md](../architecture/dashboard-pane-layout.md)・[architecture/dashboard-empty-state-agent-cards.md](../architecture/dashboard-empty-state-agent-cards.md)）。

## 何をしたか

- **task-1（Cursor 実装・stage1 レビュー pass）**: `PaneWidthPolicy` 新設と `DashboardView` への配線（ウィンドウリサイズ・サイドバー開閉での自動クランプ、`*AtDragStart` 同期、min 定数の一元化）。
- **task-2（Cursor 実装・差し戻し1回→pass）**: `AgentStartCardsLayoutPolicy` 新設と `AgentStartCardsView` の横並び/縦積み切替（`GeometryReader` ルート計測・縦積み時 `ScrollView`・テストフック `onLayoutDecision`）。
  - 差し戻し#1: 当初契約が推奨した「兄弟計測行」方式を stage1 レビューが `ImageRenderer` 実測で反証（膨張後の幅に張り付き縦積みが発火しない）。**原因は PM の契約前提の誤り**（実装者の逸脱ではない）。契約を GeometryReader 方式へ改訂し、実ビュー配線テストを必須化して再実装 → 再レビュー pass。
- **フェーズ4（統合検証）**: DashboardFeature 全件 1351 tests（既知 flaky 1件を除き green、最終 run は全件 pass）／SessionFeature 全件 113 tests pass／`NSHostingView` による実ランタイム描画で 900pt（クランプ+縦積み+右サイドバー完全表示）と 1400pt（従来表示）を PNG 確認。
- **検証アーティファクト**: `AgentStartCardsRenderPNGTests.swift`・`DashboardPaneClampRuntimeTests.swift`（`/tmp/agent-start-cards-{narrow,wide}.png`・`/tmp/dashboard-both-sidebars-{900,1400}.png` を出力）。

## 観測事項（フォローアップ候補）

- **既存テストの load 依存 flaky**: `DashboardViewModelTests.swift` の `hookMultiplex_routesEventToCorrectSession` が全件並列実行時に稀に失敗する（単独実行は 5/5 pass・本 run の変更と無関係・dev 由来）。再発時は単独再実走で切り分ける。修正は本 run のスコープ外。
- **実ウィンドウでの手動ドラッグリサイズ確認は未実施**: 検証時に既存の Phlox インスタンス（debug ビルド）が稼働中で、二重起動はポート・状態の競合リスクがあるため見送った。`NSHostingView` ランタイム描画（同一の onChange 経路）で代替検証済み。リリース前の実機確認時に一度ウィンドウを狭めて確認するとよい。
- ブランドアイコン（`AgentBrandIcon`）はテストの headless 描画ではアセット/テーマ未初期化のため写らない（実アプリでは表示される・本修正と無関係）。

## 生成・更新したドキュメント

- [adr/0090](../adr/0090-dual-sidebar-pane-width-clamp-and-card-stacking.md)（新規）
- [architecture/dashboard-pane-layout.md](../architecture/dashboard-pane-layout.md)（新規）
- [architecture/dashboard-empty-state-agent-cards.md](../architecture/dashboard-empty-state-agent-cards.md)（縦積み対応を追記）
