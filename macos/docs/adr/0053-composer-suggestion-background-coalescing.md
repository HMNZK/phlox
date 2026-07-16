---
status: active
last-verified: 2026-07-08
---

# 0053: @ サジェスト走査の背景化と coalescing（in-flight 1本＋最新 pending 1枠）

> **このファイルの役割**: composer の @ ファイル候補走査を MainActor 非ブロックにする決定と、並行走査を抑える coalescing 状態機械の rationale。
> **書かないもの**: 現行の実装仕様（→ `architecture/chat-mode-ux-components.md`）。

- **文脈**: 監査所見 P5。@ サジェストのファイル候補はキャッシュ miss 時に MainActor 上で同期 FS 走査され、大きいリポジトリでキー入力をブロックしていた（TTL 5秒の `ComposerSuggestionSourceCache` は導入済みだが miss 時は同期のまま）。
- **決定**:
  1. **走査は背景 Task**（`asyncFileProvider`）: `update(text:cursorUTF16:)` は走査完了を待たず即返る。走査中は前回候補を保持（空 flicker しない）。warm キャッシュ hit は従来どおり同期即応答の fast-path。
  2. **coalescing 状態機械**: `runningScanCount`（0/1）＋`pendingScan` 1枠。**running 中はいかなるクエリも走査を新規起動せず、最新クエリだけを pending に上書き**。走査完了時に pending を1本だけ起動する。FS 走査は非協調（Task.cancel が届かない）ため、「cancel＋世代破棄」だけでは stale 反映は防げても**走査コストの並行増殖は防げない**——起動数そのものを絞るのが根本対処（stage2 レビューが同一ターン限定の初版・跨ターンの穴を2ラウンドで棄却した経緯）。
  3. **世代トークン**: 結果採用は「起動時世代＝現在世代」のときのみ（dismiss・新クエリで世代前進）。採用判定は MainActor 単一ジョブ内（await 1点の後・他の await を跨がない）で行い、順序逆転による stale 採用を排除。
- **棄却案**: (a) cancel のみ（非協調走査に届かない）、(b) 並行走査＋世代破棄のみ（stale は防げるが CPU/IO が連打で増殖）、(c) 同一 MainActor ターン限定の coalescing（実タイピングはターンを跨ぐため主経路で無効）。
- **証拠**: 受け入れ6（非ブロック・前回候補保持・stale 非採用・dismiss 復活なし・同一/跨ターン coalescing・slash 同期）＋白箱6 green（912 全体 green）。実機で @ 入力のタイプ体感スムーズをユーザー確認（2026-07-08）。
- **補足**: レビュー過程で PM 著述の受け入れ2件（並行走査モデル前提の stale テストと coalescing テスト）が論理矛盾していたことが検出され、coalescing モデルへ統一裁定した（decision-log 2026-07-08）。
