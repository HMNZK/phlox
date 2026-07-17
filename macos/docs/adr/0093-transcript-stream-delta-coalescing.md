---
status: active
last-verified: 2026-07-17
---

# 0091: ストリーミング delta のコアレシング適用（イベント毎の即時 UI 無効化を廃止）

## 状況

チャット4面同時稼働で描画・スクロールがカクつく（perf-multi-chat-lag run）。原因は `ChatSessionViewModel` のストリーミング適用構造: delta イベント1件ごとに (a) `transcript.firstIndex(where:)` による **unbounded 配列の線形走査**、(b) `transcript` 書換＋ `transcriptRevision += 1` による **即時 View 無効化** が MainActor で走り、無効化回数がイベント数×セッション数に比例していた（無効化1回ごとに末尾窓 ≤200 セルの ForEach 再 diff が全可視タイルで発生）。定常負荷が軽い実測（chat-mode-ux-components「並行処理の現状」）は単一セッション基準で、N 面同時は未検証だった。

## 決定

1. **時間窓コアレシング**: delta は `TranscriptStreamCoalescer`（純ロジック・時刻/スケジューラ注入）に enqueue し、**50ms 窓でバッチ適用**する。UI 無効化（revision 増分）はイベント数から独立になる（受け入れ: 200 delta で増分 ≤50。実測は 2 回程度）。
2. **barrier flush**: 非 delta イベント（turn 境界・error・fileChange・subAgent 等の全 case）、`itemStarted/itemCompleted`（Codex thread stream）、interrupt の完了/失敗経路は、**transcript を変異する前に必ず pending delta を flush** する。イベントの観測順序（例: idle 観測時点で先行 delta 反映済み）を従来と同一に保つ。
3. **世代トークン**: close / rebuildTranscript / revert 切詰めで coalescer を invalidate し、予約済み flush の stale 適用を拒否する。
4. **O(1) 適用**: `transcriptIndexByID`（id→index 索引）で線形走査を除去。適用は transcript の **in-place 変異**（CoW 全コピー禁止。同一 MainActor ターン内の複数変異は SwiftUI 側で1フレームに合流する）。
5. `lastEventAt` / `lastOutputAt` / `rawEventLog` の更新も flush 節奏に束ねる（hangAssessment の stall 誤検出は起きない: 窓 50ms ≪ 判定粒度 1s）。

## 棄却案

- **イベント毎適用のまま走査だけ O(1) 化**: 無効化回数（支配項）が残るため不十分。
- **遅延 delta の世代タグ付き破棄**（interrupt 後に届く delta を捨てる）: 旧実装は表示していた内容を失う後退。旧挙動維持を優先。

## 受け入れたトレードオフ・既知の残余（スコープ外裁定 2026-07-17・decision-log 参照）

- **トークン表示の遅延 ≤50ms**（体感不能域として許容）。
- **既存レースの温存**: (1) normalized events と thread events を別 MainActor Task が消費するため、`itemCompleted` が先行 delta より先に処理されると本文が二重加算され得る（**旧実装と同一挙動**・実プロトコル順では起きにくい）。(2) interrupt 後に AsyncStream へ届く遅延 delta は idle 後も適用される（旧実装と同一）。いずれも本 run の契約「従来と観測的に同一」の範囲内として温存。根治するなら2ストリームの直列化（アダプタ側の単一ストリーム化）が筋。

## 検証

- 受け入れ: `AcceptanceStreamCoalescingTests`（意味論保存・barrier・revision コアレシング）。
- 合成再現（フェーズ4）: 4セッション×2,000 delta（計8,000 イベント）で UI 無効化 **8,000 回 → 8 回**。transcript 最終内容は完全一致。
- 二段独立レビュー pass（stage2 の差し戻し1回で interrupt 失敗経路の barrier 漏れを修正）。
