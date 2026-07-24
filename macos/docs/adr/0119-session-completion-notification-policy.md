---
status: active
last-verified: 2026-07-24
---

# ADR-0119: 完了通知判定を SessionCompletionNotificationPolicy へ一元化し、ADR 0064 の idle 無視ガードは復元推定ターンのみ例外とする

## 文脈

「セッションが完了・待機しているのに iOS へ通知が来ない」取りこぼしが複数経路にあった:

1. turnCompleted 到着時の status が `.awaitingApproval` / `.awaitingUserQuestion` だと、
   `guard previousStatus == .running` により完了通知が丸ごと出ない。
2. Codex の `threadStatusChanged` が通知ロジックをバイパスして status を直接書く。
3. pty 型（SessionViewModel）はプロセス終了（completed/error）が通知対象外だった。
4. APNs 側は鍵未設定・トークン0件をサイレント no-op で握りつぶし、設定ミスとバグを
   区別できなかった。

一方で ADR 0064 は「ライブターン進行中に Codex が非同期で idle を報告する競合」への
対処として、`turnStartedAt != nil` 中の `threadStatusChanged(.idle)` 無視ガードを凍結
済み（DashboardFeature の ProcessingIndicatorWhiteboxTests）。当初実装はこのガードを
削除して通知を通したため、統合検証（フェーズ4）で既存凍結テストが fail した。

## 決定

- 完了通知の判定を純ポリシー **`SessionCompletionNotificationPolicy`** へ一元化する。
  - 2引数版（pty 用）: `previous == .running && isTerminal(next)`。
  - 3引数版（Chat 用）: `hasActiveTurn` が必須条件。previous ∈ {running,
    awaitingApproval, awaitingUserQuestion} かつ next が terminal（idle/completed/error）
    で通知。復元リプレイ・interrupt 由来の idle では鳴らさない。
- **ADR 0064 のガードは維持**する。ライブターン（実際に `turnStarted` イベントを受けた
  ターン）進行中の `threadStatusChanged(.idle)` は引き続き無視し、完了は turnCompleted
  を正とする。
- 例外として、**復元時に thread status から推定した running ターン**
  （`applyRestoredThreadStatus` が `turnIsRestoredInference = true` を立てる）に限り、
  `threadStatusChanged(.idle)` での終端＋完了通知を許す。復元後は turnCompleted の
  リプレイが保証されないため、これが無いと復元セッションの完了が無音になる。
- `threadStatusChanged(.systemError)` はライブターン中でも terminal として反映・通知する。
- APNsNotificationBridge のサイレント no-op 経路（sender 未設定等）に、イベント種別・
  sessionId・原因を含む構造化ログ（subsystem `com.phlox.Phlox` / category `APNs`）を
  追加し診断可能にする（AppBootstrapTests の NotificationBridgeDiagnosticsTests で凍結）。

## 棄却案

- **ガード全削除で idle 通知を常時許可**（当初実装）: ライブターン中の一時的 idle 報告で
  誤完了通知＋インジケータ消失が再発する。ADR 0064 の凍結テストと矛盾するため棄却。
- **status 遷移側の意味変更**: ADR 0064 と同じ理由（依存機能への波及）で棄却。

## 結果

- 受け入れテスト AcceptanceNotificationGapTests（遷移マトリクス）と白箱テスト
  NotificationGapWhiteboxTests（mid-turn idle 無視・復元 idle 通知・フラッピング抑制・
  pty 終了通知・systemError 通知）が凍結。
- 残余リスク: ライブターンで Codex が turnCompleted を送らず idle だけで終わる異常系は
  引き続き無通知（ADR 0064 で受容済みトレードオフと同一。次ターン開始でクリア）。
- APNs 実機 E2E は未検証（ユーザー実機での確認が必要）。
