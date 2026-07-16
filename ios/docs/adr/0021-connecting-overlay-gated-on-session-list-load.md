---
status: active
last-verified: 2026-07-16
---

# ADR 0021: QR ペアリング直後に「接続中…」オーバーレイを出し、閉じ判定をセッション一覧のロード成功でゲートする

> **このファイルの役割**: wave-9 で、QR ペアリング直後にオフライン画面が一瞬出てから接続される体験を、全画面「接続中…」オーバーレイで隠し、その閉じ判定を「到達性」ではなく「セッション一覧の取得成功」に結びつけた決定を記録する。
> **書かないもの**: 到達性再判定 `refresh()` 自体の仕様（→ [ADR 0019](0019-reachability-on-demand-refresh.md)）・オーバーレイの見た目詳細（実装は `AppRoot.ConnectingOverlayView`）。

## 文脈

wave-8（[ADR 0019](0019-reachability-on-demand-refresh.md)）で QR ペアリング完了時に到達性を即再判定するようにしたが、実機では「ペアリング直後にオフライン画面（『Mac に到達できません』）が一瞬出て、少し待つと接続される」体験が残った。Mac / Tailscale の起き上がりに数秒かかるため、ペアリング直後の最初のプローブが失敗しやすいことが原因。

まず全画面「接続中…」オーバーレイ（`AppModel.isConnecting`）を追加し、`ReachabilityMonitor.refresh()` が `.online` を返すまで表示する実装を入れたが、**オーバーレイが即座に閉じてオフライン画面が出る**症状が消えなかった。調査で判明した核心:

- オフライン画面は **到達性モニタ（`AppModel.reachability`）ではなく、セッション一覧の取得状態 `SessionListViewModel.state`（`SessionsState`: `.loading/.loaded/.empty/.offline/.error`）** で駆動される。`state` は `SessionRepository` の定期ポーリング（既定3秒）で更新される。`reachability` はオフライン画面の**文言の出し分け**にしか使われていなかった。
- 到達性チェック（`HostHealthChecker` の GET /sessions・5s タイムアウト）は一覧取得（リポジトリの本取得＋デコード）より軽く速く通る。そのため「接続中…」を `reachability.refresh()==.online` で閉じると、**一覧がまだ読めていないのにオーバーレイが閉じ→オフライン画面が一瞬出て→次のポーリングで一覧が入る**、という取り違えが起きていた。

## 決定

「接続中…」オーバーレイの**閉じ判定を、到達性ではなくセッション一覧の取得成功に結びつける**。

- **判定を純関数に切り出す**: `PairingConnectGate.shouldContinueConnecting(listState: SessionsState, elapsed: TimeInterval, timeout: TimeInterval) -> Bool`（`Features` に public・副作用なし・現在時刻に触れない）。規則:
  - `elapsed >= timeout` → false（**最優先**。無限スピナー防止。到達不可なら閉じてオフライン案内＝Mac スリープ解除の導線を出す）。
  - `listState` が `.loaded` / `.empty` → false（接続完了 → 一覧へ）。
  - `listState` が `.loading` / `.offline` / `.error` かつ `elapsed < timeout` → true（まだ → 接続中を継続）。
- **配線**: `AppRoot.connectAfterPairing()` は、ペアリング完了からの経過秒を測りつつ一覧を再取得し、`PairingConnectGate` が false を返すまで `isConnecting=true` を保つ（タイムアウト約20秒）。到達性 `refresh()` は**文言出し分け用に `model.reachability` を更新するためだけ**に残し、閉じ判定には使わない。
- 純関数の振る舞いは凍結受け入れテスト `PairingConnectGateAcceptanceTests`（5ケース）で固定。

## 結果

- QR ペアリング直後は、Mac / Tailscale が起き上がって**一覧が実際に読めるまで**「接続中…」が出続け、読めたら一覧へ、約20秒読めなければオフライン画面（スリープ案内）へ落ちる。オフライン画面の一瞬のちらつきが解消。
- 「接続完了」の単一の正がセッション一覧のロード成功に一本化された（到達性の healthCheck と一覧取得の乖離に依存しない）。
- **前提/劣化**: 閉じ判定の実地正当性は `SessionListView` がマウントされ `SessionListViewModel.observe()`（`state` を駆動する定期ポーリング）が走っていることに暗黙依存する。`connectAfterPairing` は `AppRoot`（View）のため、この統合パスはユニットテスト外で、実機/統合検証で担保する（純関数の判定表のみユニットで固定）。
- **スコープ**: 修正の主経路は初回セットアップ完了（`AppRoot.qrScanOnApplied` が `setupRequired` のみフック）。設定タブからの QR 再ペアリングは対象外（同症状があれば別タスク）。

## 却下した代替案

- **到達性 `refresh()` の `.online` で閉じる**（初版）: healthCheck が一覧取得より速く通り、一覧未ロードのままオーバーレイが閉じてオフライン画面が一瞬出た（本 ADR の修正対象）。
- **固定時間（N秒）スピナー**: 実際の接続完了と無関係に閉じるため、遅い Mac では早すぎ・速い Mac では無駄に待つ。一覧ロードでゲートする方が実挙動に忠実。
- **オフライン画面を `AppModel.reachability` 駆動へ作り替える**: 一覧取得（`SessionsState`）とは別系統の状態を二重管理することになり、取り違えの温床が増える。既存の単一ソース（一覧状態）に閉じ判定を寄せる方が単純。
