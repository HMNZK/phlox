---
status: active
last-verified: 2026-07-17
---

# 0092: モバイル接続プロキシの Tailscale 遅延起動に対する自己回復（オンデマンド再解決＋起動後リトライ）

## 文脈

`MobileProxy` はアプリ起動時に `tailscale ip -4` を**一度だけ**解決し**一度だけ** bind するワンショットだった（`CompositionRoot.startMobileProxy`）。ログイン直後などで Tailscale デーモンがまだ上がっていないと `TailscaleIPResolver.resolveIPv4()` が `nil` を返し、`BindMode.resolve` が `.loopbackOnly`（127.0.0.1 限定・外部露出なし）に倒れる。その後 Tailscale が上がってきても**再解決しない**ため、モバイル接続（QR ペアリング）はアプリを再起動するまで不可のまま固定されていた。

加えて設定 UI の `MobileTokenViewModel` は起動時の `bindMode` / `mobileProxyPort` を**不変スナップショット**（`let`）として抱えており、仮にプロキシが後で回復しても UI へ反映されない。

ユーザー報告は「モバイル接続プロキシが起動していないため、QR コードを表示できません」。この文言自体は `bindMode == nil`（起動失敗＝ポート競合等）の分岐だが、根本は「起動時ワンショット＋リトライ／再解決なし＋UI がスナップショットを抱える」という同一の構造欠陥で、Tailscale 遅延起動でも `.loopbackOnly` 固定で同種の到達不能に陥る。

## 決定

1. **`MobileProxy.refresh()`（actor）を追加**。`.tailscale` / `.explicitHost` は no-op（冪等・利用者の明示ホストを尊重）、`nil` / `.loopbackOnly` は現行 listener を停止して**再解決・再バインド**する。
2. **`MobileProxy.recoverUntilReachable(maxAttempts:delay:sleep:)` を追加**。有限回だけ `refresh()` を試み、`.tailscale` 到達で早期打ち切り。試行間 `sleep` は DI シームでテスト時は実待ちを回避。
3. **トリガーは2系統**（NWPathMonitor による常時監視は入れない）:
   - **on-demand（主軸）**: 設定のモバイル接続セクション表示時に再解決（`SettingsView.MobileTokenSection` の `.task { await viewModel.refreshReachability() }`）。ユーザーが接続しようとした瞬間に必ず再確認する。
   - **起動後の短いリトライ**: `MobileTokenViewModel.startAutoRecovery()` が `recoverUntilReachable(maxAttempts: 5, delay: .seconds(2))` を一度だけ駆動。
4. **UI をライブ化**: `MobileTokenViewModel.bindMode` / `mobileProxyPort` を `@Published` 化し、回復を設定画面へアプリ再起動なしで反映する。`isPairingQREnabled` / `pairingQRDisabledReason` は既存ロジックのまま `@Published` を読むため自動追従。
5. **再バインドのソケットライフサイクル**: `POSIXSocketListener.stop()` は `shutdown(SHUT_RDWR)` + `close()` した後、accept ループの終了を `DispatchSemaphore` で確実に待ってから返す。固定ポート 8765 を loopback→tailscale で貼り替える際の fd 再利用レース・二重 accept・スレッド残存を構造的に封じる。

## 棄却した代替案

- **NWPathMonitor による常時ネットワーク監視で自動再バインド** — 常駐コストが増える。ユーザーの接続操作（設定を開く）が自然かつ十分なトリガーであり、on-demand 再解決＋起動後の短いリトライで目的（Tailscale 遅延起動からの回復）を満たすため不採用。
- **固定ポート 8765 使用中（EADDRINUSE）時の ephemeral ポートフォールバック** — QR ペイロードは port を運ぶため技術的には可能だが、8765 は iOS クライアントの既定接続先（`ConnectionConfig` の「固定ポート」契約）であり、フォールバックは別インスタンス／ペアリング済み端末の再スキャンを要する。本 ADR のスコープ（Tailscale 遅延起動の自己回復）から外し見送り（必要になれば別 ADR）。

## 結果

- `MobileProxyTests`（`MobileProxyRecoveryTests`）に自己回復テストを追加: `.loopbackOnly`→`.tailscale` 昇格（**再バインド後に実 TCP がスタブへバイト等価で透過**することまで検証）、`.tailscale` 済み no-op（resolver 呼び出し回数で立証）、`.explicitHost` 非上書き、`recoverUntilReachable` の早期打ち切り・sleep 回数、`maxAttempts=0`。`swift test` 68/68 green。
- 独立レビュー（クロスモデル）が `shutdown+close` による accept 解除を 200/200 ハング無しで実測し、再バインドのデッドロック不在を確認。
- App の Debug ビルド（`xcodebuild`, 署名なし）BUILD SUCCEEDED（配線のコンパイル整合を確認）。
- ライブ挙動（Tailscale 遅延起動 → 設定を開くと QR が有効化される）は実機の Tailscale 起動タイミング依存のため、オンデバイス確認を要する。
