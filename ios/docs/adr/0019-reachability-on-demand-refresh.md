---
status: active
last-verified: 2026-07-16
---

# ADR 0019: 到達性のオンデマンド再判定（refresh）で QR ペアリング直後の stale offline を解消する

> **このファイルの役割**: wave-8 で、QR ペアリング直後や手動「再接続を試す」で接続状態が更新されず「オフライン / Mac に到達できません」が残るバグを、`ReachabilityMonitor` にオンデマンド再判定 `refresh()` を追加して解消した決定を記録する。
> **書かないもの**: 到達性の二層判定（`resolve`）や UI 文言の詳細（実装は `PhloxReachability` / `UnreachableViewModel`）。

## 文脈

`ReachabilityMonitor`（actor, `PhloxReachability`）の接続状態 `_current` は、`NWPathMonitor.pathUpdateHandler`（ネットワーク経路の変化）が発火した時にだけ `handlePath()` 経由で更新される**キャッシュ値**だった。定期ポーリングも「今すぐ再判定する」API も無い。

このため次の症状が出た（実機検証）: アプリ起動時（まだ QR ペアリングしておらず接続先 config が空）の初回 path 発火で healthCheck が失敗し `_current = .unreachableHost` がキャッシュされる。その後 QR ペアリングを完了しても、ペアリング適用（`PairingApplyViewModel.apply`）は config/token 保存と独自の一発 probe（成功表示用）を行うだけで `ReachabilityMonitor` に触れず、完了ハンドラ（`AppRoot.qrScanOnApplied`）も画面遷移のみ。「再接続を試す」（`AppRoot.refreshReachability`）も `reachability.current` を**読むだけ**でキャッシュを返す。結果、ペアリング直後にオフライン表示が残り、NWPathMonitor が偶発的な経路変化を検知するまで（＝「少し経つと勝手に接続される」）解消しなかった。

## 決定

- **オンデマンド再判定 API を追加**: `ReachabilityMonitoring` protocol に `func refresh() async` を追加し、`ReachabilityMonitor.refresh()` を実装した。`refresh()` は**現在のネットワーク状態で healthCheck を即実行**し、`_current` を既存の `update(to:)` 経由で更新（購読 stream にも yield）する。NWPathMonitor の経路イベントを待たない。
- **ライブのネット状態を優先**（offlineNetwork と unreachableHost の取り違え防止・stage-2 レビュー対応）: `refresh()` は監視中なら NWPathMonitor の live な `currentPath.status` を読み、未起動時のみ最後に観測した状態（`lastNetworkSatisfied`）にフォールバックする（`let satisfied = monitor.map { $0.currentPath.status == .satisfied } ?? lastNetworkSatisfied`）。これにより「物理ネット圏外なら healthCheck を待たず offlineNetwork」「ネットあり・ホスト無応答なら unreachableHost」を正しく分岐する。テスト用に `init(healthCheck:initialNetworkSatisfied:)`（既定 true）で初期ネット状態を注入可能にした。
- **呼び出し配線**: `AppRoot` の①QR ペアリング完了 `qrScanOnApplied`（config 反映後に `Task { await reachability.refresh() }`）②手動「再接続を試す」`refreshReachability`（`await reachability.refresh()`）の**両方**から `refresh()` を呼ぶ。`StubReachability.refresh()` は固定値 stub のため no-op。

## 結果

- QR ペアリング完了直後と手動リトライで、最新 config を使った到達性再判定が即座に走り、到達可能なら online になる（stale offline が残らない）。
- 圏外（offlineNetwork）と Mac 無応答（unreachableHost）が正しく出し分けられ、回復導線の案内が適切になる。
- 凍結受け入れ `ReachabilityRefreshAcceptanceTests` が online / unreachableHost / offlineNetwork の3ケースを固定。`ReachabilityMonitorRefreshTests`（白箱）が再実行で最新結果を反映することを検証。
- **未検証**: `refresh()` のライブ `currentPath` 分岐は `NWPathMonitor` を注入できずユニットテスト不能（フォールバック分岐のみ検証）。加えて `NWPathMonitor.currentPath` は `start()` 直後・初回評価前に未確定ステータスを返しうる。この瞬間の正確性は統合検証・実機で担保する。

## 却下した代替案

- **定期ポーリングで to再判定する**: 電池消費と過剰リクエスト。イベント駆動＋オンデマンド refresh の方が軽い。
- **ペアリング成功を直接 `.online` に固定する**: `PairingApplyViewModel` の probe が成功しても healthCheck を通さず online にすると、実際の到達性と乖離しうる（config 保存と別経路の probe）。`refresh()` で本来の healthCheck を通す方が単一の正。
- **`refresh()` でキャッシュ `lastNetworkSatisfied` を常に使う**（初版）: 経路イベント未発火の窓で真オフラインを unreachableHost と誤分類しうると stage-2 レビューが指摘。ライブ `currentPath` 優先へ修正した。
