---
status: active
last-verified: 2026-07-21
---

# ADR 0108: 圧縮中インジケーターの開始検知は手動 /compact のみ（stream-json に開始シグナルが無い）

## 文脈

compact（会話履歴圧縮）中の待ち時間を可視化するため、`ChatSessionViewModel.isCompacting` と
シマーアニメーション（CompactingIndicatorCell、ThinkingAnimation 転用）を導入した。
Claude Code stream-json が運ぶ圧縮関連イベントは `system/compact_boundary`
（`compact_metadata.trigger: "auto"|"manual"`, `pre_tokens`）のみで、これは**完了境界**であり
開始シグナルではない。実装時調査（`~/.claude` 全域の grep）でも stream-json 上の
「圧縮開始」イベントは確認できなかった（フック層の PreCompact は CLI 内部で Phlox には届かない）。

## 決定

- `compact_boundary` を `NormalizedChatEvent.compactionBoundary(trigger:preTokens:)` へ正規化する
  （metadata 欠落時も nil で yield し silent drop しない）。
- `isCompacting` の開始は**手動 `/compact`（引数付き含む）の submit 送信検知のみ**。
  解除は `.compactionBoundary` / `.turnCompleted` / `.turnInterrupted` / `.error` の全経路
  （フェイルセーフ）。
- 表示中は `CompactingIndicatorPresentation` が Thinking インジケーターを抑止し二重表示を防ぐ。

## 結果

- 契約: `AcceptanceCompactBoundaryTests`・`AcceptanceCompactingIndicatorTests`（凍結）。
- 既知の制限: auto-compact はプロトコル上開始を検知できず、`compact_boundary` 到着（完了）まで
  インジケーターは出ない。CLI が将来開始イベントを追加したら正規化を拡張する。
