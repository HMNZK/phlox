---
status: completed
last-verified: 2026-07-17
---

# 0004: モバイル接続プロキシ自己回復 worklog

## 概要

「モバイル接続プロキシが起動していないため、QR コードを表示できません」報告の調査と修正。根本原因は **MobileProxy が起動時ワンショットで、Tailscale 遅延起動時に `.loopbackOnly` へ倒れたまま再解決せず、設定 UI も不変スナップショットを抱える**こと。オンデマンド再解決＋起動後リトライ＋UI ライブ化で自己回復させた。

## 根本原因（調査）

- 「起動していない」は `MobileTokenViewModel.pairingQRDisabledReason` の `bindMode == nil` 分岐＝ `MobileProxy.start()` が throw（bind 失敗＝ポート使用中）のとき。調査時の実機は Phlox 2 プロセスによる固定ポート 8765 競合が観測された。
- ユーザー指摘により、より一般的な同型欠陥＝ **Tailscale 未起動→`.loopbackOnly` 固定→リトライ／再解決なし**を確認（`MobileProxy`/`CompositionRoot` に retry/observer/re-resolve のコードはゼロ）。両者とも「起動時ワンショット＋UI スナップショット」という同一構造欠陥。

## 変更

- **task-1（MobileProxy パッケージ, Codex 実装）**: `refresh()` / `recoverUntilReachable(maxAttempts:delay:sleep:)` / `boundPort` を追加。`POSIXSocketListener.stop()` を `shutdown()`+`close()`+accept ループ終了待ち（`DispatchSemaphore`）に強化。`MobileProxyRecoveryTests` を追加。
- **task-2（App ターゲット, Cursor 実装）**: `MobileTokenViewModel.bindMode/mobileProxyPort` を `@Published` 化、`refreshReachability()` / `startAutoRecovery()` 追加、`CompositionRoot` で `proxy` 注入＋`startAutoRecovery()` キック、`SettingsView` に `.task { refreshReachability() }`。

## 検証

- `swift test`（MobileProxy）: 68/68 green（新規回復テスト5件含む）。`--parallel` 5回も全 pass。
- 独立レビュー（Claude persona-reviewer）: task-1 / task-2 とも pass。task-1 は `shutdown+close` の accept 解除を 200/200 ハング無し実測。MUST/HIGH/MEDIUM=0。
- App Debug ビルド（`xcodebuild`, 署名なし）: BUILD SUCCEEDED。
- 未検証（要オンデバイス）: Tailscale 遅延起動→設定を開くと QR 有効化、という実機タイミング依存のライブ挙動。

## 生成物

- 決定: [ADR 0091](../adr/0091-mobile-proxy-self-heal-on-tailscale-late-start.md)
- 構造更新: [architecture/mobile-proxy.md](../architecture/mobile-proxy.md) の「自己回復」節・QR 配線メモ

## 積み残し / スコープ外

- 固定ポート 8765 使用中（EADDRINUSE）時の ephemeral フォールバックはユーザー合意で今回スコープ外（ADR 0091 参照）。
