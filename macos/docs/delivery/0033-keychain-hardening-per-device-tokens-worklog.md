---
status: completed
last-verified: 2026-08-02
---

# 0032: Keychain 保護強化（Data Protection Keychain）＋端末別モバイルトークン

> **このファイルの役割**: 2026-08 の agentic-loop run（backend=codex・タスク6件）の作業経緯・状態スナップショット・積み残し。
> **書かないもの**: 恒久仕様（→ [architecture/mobile-device-pairing.md](../architecture/mobile-device-pairing.md)・[specs/qr-pairing-contract.md](../specs/qr-pairing-contract.md)）、決定の理由（→ ADR [0160](../adr/0160-data-protection-keychain-and-per-device-mobile-tokens.md)）。

## やったこと

| task | 内容 | 主なコミット |
|---|---|---|
| task-0 | `KeychainItemAccessor` の導入（DPK 優先・ファイルベースへフォールバック・`backend()` の観測点） | `9703079` |
| task-1 | `PairedDevice` / `PairedDeviceStore`（Keychain 項目 1 つへ全端末を永続化・旧トークン削除） | `a86bcfb` |
| task-2 | `MobileDeviceProvisioner`（発行・ペアリング記録・失効・期限切れ掃除。RMW を直列化） | `c91fb39` |
| task-3 | Dashboard の特権 requester を単数から集合へ拡張 | `26106f1` |
| task-4 | アプリへの配線（`MobileBootstrap`・設定 UI の端末一覧と失効・認証成立の記録） | `12df556` / `8caebcd` |
| task-5 | DPK 用 entitlements と署名変数（`PHLOX_CODE_SIGN_ENTITLEMENTS` 等） | `e0e7b1b` / `5f7a0fd` |

## 検証

- `swift test --package-path macos/Packages/AgentDomain` — 受け入れテスト（`AcceptancePairedDeviceStoreTests` / `AcceptanceLegacyTokenPurge` / task-2 の 3 件 / `AcceptancePairingLifecycleIntegrationTests`）を含めて green。
- `xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug build` — BUILD SUCCEEDED。
- DPK entitlement 付きビルド — BUILD SUCCEEDED。`embedded.provisionprofile` あり、`keychain-access-groups = <TEAMID>.com.phlox.Phlox.debug` を確認。別インスタンスとして起動し SIGKILL されないことを確認。
- `.claude/verify.sh` — 4 回連続 exit 0。

## 積み残し・未検証

- **設定画面の端末一覧の実機での見え方は未確認**。この検証環境は Tailscale を検出できず MobileProxy がバインドしないため、QR 発行 → iPhone でペアリング → 一覧更新を実地で再現できなかった。加えて、設定ウィンドウをスクリプトからモバイル接続セクションまでスクロールできず、一覧を画面上で目視できていない。行が増えたときのスクロール・失効ボタンのはみ出し・Dynamic Type の大きい設定は**コードと白箱テストでの担保にとどまる**。次に実機で触れる機会に確認すること。
- 起動中の DPK 署名ビルドから `keychain backend = ...` のログ行を観測できていない（起動自体は成功）。
- `CompositionRoot` の配線（`setHandler` の `[weak mobileTokenViewModel]` と MainActor ホップ）は App ターゲットにテストランナーが無く、自動テストで踏めていない。「記録 → 通知」の部分は `MobileBootstrap.makeAuthenticatedTokenHook` へ切り出して白箱テストで固定した。

## この run で拾った運用上の知見

- **Codex のレビューは read-only サンドボックスで `swift test` を実行できない**（xcrun が `/tmp/xcrun_db-*` を作れない）。そのままでは構造的にどのレビューも pass に到達しない。`agentic-loop-review-lock.sh on`（`apply_patch` を deny）＋ full モード＋PM 側での SHA-256 前後比較で、書き込みを封じたまま実行権を与える形にした。
- **Bash ツールの 10 分上限**で長いレビューが途中で殺され、出力 JSON が 0 バイトになる。`nohup … &` で起動してポーリングする。
- **凍結した受け入れテストが `@Sendable` クロージャで可変ローカルを捕捉していた**ため、テストターゲット全体がコンパイルできなくなった（2 回発生）。`TestClock`（`NSLock` 付き `@unchecked Sendable`）を用意して修理し、再凍結した。「本番 API から `@Sendable` を外す」という実装側の提案は却下した。
- 既存の flaky（`waitUntilDone_*` の 500ms 上限、`sessionVM_characterization_*`）が verify ゲートを確率的に赤くしていたため、検出力を保ったまま実時間の上限を広げた。
