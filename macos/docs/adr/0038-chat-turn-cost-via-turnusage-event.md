---
status: active
last-verified: 2026-07-06
---

# ADR 0038: チャットのターンコストは turnUsage イベントで運搬し USD 表示する

> **このファイルの役割**: ターン/セッションコスト表示のデータ経路と表示通貨の決定理由。
> **書かないもの**: 現行のデータフロー詳細（→ architecture/chat-mode-ux-components.md）。

## 文脈

Claude Code の stream-json `result` イベントには `total_cost_usd` / `usage`（トークン内訳）が含まれるが、`ClaudeChatClient.handleResultEvent` は読み捨てていた。チャットモードに「1ターンのコスト＋セッション累計」を表示する要望（chat-ux-batch 項目B）。

## 決定

1. **`NormalizedChatEvent` に `turnUsage(TurnUsage)` case を追加**し、`subtype=="success"` の result からパースして **`.turnCompleted` の直前に** yield する。エラー/interrupt 経路では yield しない（turnCompleted と同一ゲートの内側に置くことで正しさを継承）。
2. `ChatSessionViewModel` が `lastTurnUsage` / `lastTurnCostUSD` / `sessionTotalCostUSD` を累積し、ターン完了時に transcript へ `.turnCost` アイテム（右寄せ・小さく薄い `$0.0123`）を追加する。セッション累計は右サイドバーの SessionInfoPanel に表示。
3. **表示は USD のまま**（円換算しない）。ゲート①でユーザーが「固定レート/自動取得」より「USD のまま」を選択（当初要望の「円で」を上書き）。為替レート機構は作らない。

## 棄却案

- `turnCompleted(nativeSessionId:usage:)` への associated value 追加: 既存の全 exhaustive switch とテストの書き換えが波及するため、独立 case を選択。
- 円換算（固定レート/為替API）: ユーザー判断で不採用。外部依存・設定項目の増加を回避。

## 結果

- コスト供給は Claude のみ（Codex/Cursor の stream 形式は対象外・イベント型は共通）。
- `.turnCost` は ChatItem の custom Codable に追加済みで旧 transcript の decode と後方互換。
- 契約テスト: `AcceptanceTurnUsageTests` / `TurnCostAccumulationAcceptanceTests` / `TurnCostItemAcceptanceTests`。
