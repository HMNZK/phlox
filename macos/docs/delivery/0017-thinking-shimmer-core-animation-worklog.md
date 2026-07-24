---
status: completed
last-verified: 2026-07-24
---

# 0017: Thinking シマー Core Animation 化 worklog（agent-grid-jank run / task-1）

複数セッションのグリッド表示で CPU が暴走・スタックする問題の主犯である Thinking シマーの駆動を、SwiftUI `TimelineView`(30fps) から Core Animation 駆動の `NSViewRepresentable` へ置換した。シマーの見た目は維持したまま、SwiftUI がアクセシビリティ木／依存グラフを毎フレーム再構築する経路を根絶した。backend=codex(gpt-5.6-terra) の agentic-loop（N=1・deep）で実施。

## 決定・成果物
- 決定: **ADR 0117**（Thinking シマーの CA 駆動化）。ADR 0067 に前方参照の追記。
- 実装（`macos/Packages/SessionFeature`）:
  - 新規 `Sources/SessionFeature/ThinkingShimmerView.swift`（CA 駆動 `NSViewRepresentable`＋DEBUG テストフック）。
  - 変更 `Sources/SessionFeature/ChatMessageCells+Structured.swift`（`ThinkingIndicatorCell` のシマー経路を置換。`shimmeringThinkingText` 削除、`.accessibilityLabel("Thinking...")` 付与）。
  - 新規 `Tests/SessionFeatureTests/ThinkingShimmerViewWhiteboxTests.swift`（白箱）。
  - PM 著の凍結受け入れ `Tests/SessionFeatureTests/AcceptanceThinkingShimmerViewTests.swift`（コミット 41fb9d6）。
- 不変（凍結・変更なし）: `ThinkingAnimation.swift` の純関数、`AcceptanceThinkingShimmerTests`（DashboardFeature）。

## 状態スナップショット（検証）
- SessionFeature: 328 tests / 44 suites 全 pass。ThinkingShimmer フィルタ 9 pass、DashboardFeature 凍結純関数 12 pass。
- アプリ Debug 統合ビルド（xcodebuild -scheme Phlox）: BUILD SUCCEEDED。
- 視覚: 実装同一ロジックで「Thinking...」を実描画し、局所ハイライトが左→右へ流れ両端で画面外＝原実装のシマー忠実再現・コントラスト保持を確認。
- CPU 前後比較（隔離ハーネス 9枚・駆動方式のみ差異）: 旧 TimelineView×9 ~24%（AG::Graph::UpdateStack + CoreText 毎フレーム）→ 新 CA×9 0.0%（メイン parked）。

## 二段独立レビューの経緯（差し戻し2回・いずれも実欠陥）
1. 初版（Codex）: `CAGradientLayer.locations` を 0..1 外へアニメ → 未定義動作・オフスクリーン描画で空。ステージ2 Codex が MUST 指摘、PM がオフスクリーン `render(in:)` 実測で裏取りし差し戻し。
2. 修正（Codex）: locations 固定 0..1・幅広勾配を並進で被覆は解消したが、明度バンプを勾配全幅に張り帯が約3.2倍に拡大しシマーのコントラスト消失（PM 精読＋実測で検出）。差し戻し。
3. 再修正（PM が該当1関数を host 幅換算バンプへ変更）→ 再レビュー: ステージ1(Claude)=pass(9+12 実走)、ステージ2(Codex)=テスト未実走のみの留保、独立2機序の test pass 証拠で通過裁定。

## 残余・後続候補
- 同じ 30fps 病理を持つ `CompactingIndicatorCell` / `ChatConnectingIndicator` は未対処（同 CA 化パターンを横展開可能）。
- CPU は隔離ハーネスの n=1 点推定。シマー描画自体は描画サーバー側へ移動（WindowServer 負荷は未計測）。
- 別トラック（本 run 対象外）: ADR 0116（`.appServer` グリッドの live-resize カクつき）、前 run で凍結受け入れテストを承認なく 40→16 に書き換えた手続き未解決。

参照: ADR 0117、ADR 0067（拡張追記）、ADR 0116（別トラック）、`architecture/chat-mode-ux-components.md`。
