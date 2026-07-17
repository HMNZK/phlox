---
status: completed
last-verified: 2026-07-17
---

# 0003: perf-multi-chat-lag run 作業ログ（複数チャット同時稼働のカクつき・グリッド切替フリーズ）

> **このファイルの役割**: 本 run で何をしたか・検証状態のスナップショット。設計判断は ADR 0091/0092、現行仕様は architecture/chat-mode-ux-components.md が正本。

## 症状（ユーザー報告）

1. チャット4面同時稼働（グリッド表示・チャットモードのみ）でアプリが重く、描画・スクロールがカクつく。
2. グリッドの分割数変更・auto 切替で数秒フリーズし、しばらくすると復帰する（ゲート①で追加）。

## 実施内容

| タスク | 内容 | 実装 | レビュー |
|---|---|---|---|
| task-1 (deep) | delta 適用のコアレシング（50ms 窓）＋ O(1) 索引＋ barrier/世代トークン → ADR 0091 | Codex（差し戻し1回） | stage1 Claude pass ×2 / stage2 Codex（指摘4件 → 1件修正・3件スコープ外裁定） |
| task-2 (standard) | TranscriptWindow の文脈分化（single=200/gridTile=40）＋ hangAssessment 1Hz の viewport 停止 → ADR 0092 | Cursor | stage1 Claude pass（指摘ゼロ） |

- 受け入れテスト（凍結・実装前 red 実証済み）: `AcceptanceStreamCoalescingTests` / `AcceptanceGridRenderCostTests`
- 差し戻し#1 の裁定（既存レース2件の温存判断）: run の decision-log および ADR 0091「既知の残余」

## 検証状態（フェーズ4・2026-07-17）

- SessionFeature 134 tests / DashboardFeature 1353 tests（skip なし全数）green — 実走済み
- macOS アプリ Debug ビルド成功（統合ツリー・xcodegen + xcodebuild）
- 合成再現ベンチ（4セッション×2,000 delta を ViewModel 層へ注入・使い捨てテスト）: UI 無効化 **8,000 回 → 8 回**、最終 transcript 完全一致、経過時間は VM 層では同等（支配コストは描画側の無効化回数）
- **未検証（実機依存）**: 4面実ワークロードでの体感（スクロール応答・分割切替フリーズの解消度）、ADR 0030 の再レイアウトループ非再発（実行中タイル＋スクロールでの CPU 収束）。実運用での確認は verify ブランチの実機検証フローに委ねる。

## 積み残し・再計画条件

- グリッド構造変更時の remount 回避（ADR 0092 の棄却案）: 窓 40 化でフリーズが実用上残る場合に別 run で検討。
- ADR 0091「既知の残余」の2ストリーム順序レース: 実害が観測されたらアダプタ側の単一ストリーム化で根治。
