---
status: active
last-verified: 2026-07-17
---

# 0092: グリッドタイルの transcript 窓分化（40件）と hangAssessment 1Hz の viewport 停止

## 状況

グリッド（分割表示）は非 Lazy `ForEach` で全タイルを常時実体化し、各タイルが単一表示と同じ `ChatTranscriptView`（非 Lazy VStack・末尾 200 件窓 = ADR 0030/0051）を持つ。このため (1) ストリーミング無効化のたびに最大 200 セル×タイル数の再 diff、(2) **分割数変更・auto 切替時に全タイルの同期全再レイアウトが走り数秒の UI フリーズ**が発生していた（perf-multi-chat-lag run・ユーザー報告）。加えて hangAssessment（実行中ターンの経過表示）の `TimelineView(.periodic(by: 1))` は viewport pause の対象外で、実行中セッション×可視タイル分が並走していた（ADR 0067 の既知残余）。

## 決定

1. **表示文脈で窓の既定件数を分ける**: `TranscriptPresentationContext`（`.single` = 200 / `.gridTile` = 40）を導入し、`TranscriptWindow` は自文脈の既定値で開始・`reset()` も自文脈へ復帰する。グリッドタイル（`GridChatColumn`）のみ `.gridTile` を渡し、単一表示は既定 `.single` で従来と完全同一。`expand()`/`reveal()` の意味論（ユーザー操作のみで拡張・スクロール量非連動 = ADR 0030 の一線）は不変。
2. **hangAssessment 1Hz の viewport 停止**: `HangStatusTimelineSchedule(isVisible:)`（非表示時はエントリ列を空にする。`ThinkingTimelineSchedule` と同設計）を導入し、既存の `isTimelineVisible`（viewport×ライフサイクル×シーン合成）で駆動する。ADR 0067 の既知残余を解消。

## 棄却案（見送り・再計画条件つき）

- **グリッド構造変更時の remount 自体の回避**（autoGrid の ZStack 化・`.id(session.id)` identity 設計の変更）: ADR 0010/0030 の再レイアウトループと NSViewRepresentable attach 競合（`SessionGridView.swift` コメント）の再発リスクが高く、unit テストで担保できないため本 run では見送り。窓 40 化でフリーズが実用上残る場合に別 run で再検討する。
- 窓件数の動的算出（タイル高さ連動）: 可視領域への連動は ADR 0030 の一線に抵触。固定 40（タイル可視件数の3〜4倍）で開始しチューニングは実測後。

## 検証

- 受け入れ: `AcceptanceGridRenderCostTests`（文脈別既定・reset 復帰・非表示時エントリ空・1Hz 間隔）。
- 効果の構造的見積り: 分割変更時の同期レイアウト対象 200→40 セル/タイル（1/5）。実機の体感（フリーズ解消度）は実運用ワークロードで要確認。
- 二段独立レビュー pass（指摘ゼロ）。
