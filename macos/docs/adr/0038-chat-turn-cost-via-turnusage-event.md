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

## 追記（2026-09-24）: `total_cost_usd` はセッションの累計だった

UI 再設計（[delivery 0037](../delivery/0037-ui-redesign-worklog.md) の F7）で、インスペクタの総コストを調べて誤りに気づいた。保存済みの会話の `.turnCost` は 0.50 → 0.71 → 0.90 → … → 2.50 と単調に増えており、Claude CLI の `result.total_cost_usd` は 1 ターン分ではなく、セッションの累計である。`--resume` で再開した新しいプロセスでも累計は 0 に戻らず、再開前の分を含む（実測: 2.50 の会話を再開した次のターンが 2.94）。上の決定 1 はそれを 1 ターンのコストとしてそのまま流していたため、会話の下のターンのコストは累計を出し、`sessionTotalCostUSD` は累計を足し重ねて膨らんでいた。

**決定 1（`ClaudeChatClient` は `total_cost_usd` をそのまま流す）と決定 2（ViewModel が足す）は変えない**。差を取るのは ViewModel にした。クライアントはプロセスをまたぐ基準を知らないため。

- `ChatSessionViewModel` は、Claude から届いた累計と直前に届いた累計との差を 1 ターンのコストにする。累計が基準より減ったときは届いた値をそのまま使う。取り消し（`revert`）で CLI の会話をリセットしたら基準を 0 に戻す。エラーで終わったターン（`turnUsage` を出さない契約）の費用は次のターンの差に含まれる。
- CLI の履歴（JSONL）から再開したときは再開前の累計がわからない。最初に届いた累計をそのまま総コストにし、そのターンのコスト行は出さない。
- 総コストと最後に届いた累計（取り消しがあると両者は食い違う）を `TranscriptStore.saveSessionTotalCost`（`<id>.cost.json`・`SessionTotalCost`）へ直列に保存し、`flushTranscriptNow()` と `terminate()` は保存の完了を待つ。復元時は両方を読む。保存が無い以前の会話は最後の `.turnCost` を総額かつ基準とみなす（コストを送るのは Claude だけ）。保存に失敗した新しい会話ではこの推定が外れる（その会話の最後のターンの額になる）。
- 以前に保存した会話のコスト行は累計のまま表示される（書き換えない）。

回帰テストは `RestoredSessionTotalCostTests`（8 件: 保存した総額の復元／保存が無い旧データ／0.5 → 0.75 の 2 回目が 0.25／保存 2.5 から再開して 3.25 が届くと 0.75／総額 2.7・累計 0.2 を復元して 0.25 が届くと 0.05／取り消し後の最初の累計はまるごと 1 ターン分／履歴から再開すると最初の累計が総コスト／ファイルへの保存）。
