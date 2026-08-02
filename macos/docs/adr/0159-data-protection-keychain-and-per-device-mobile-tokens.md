---
status: active
last-verified: 2026-08-02
---

# ADR 0159: Data Protection Keychain への移行と、端末別モバイルトークン

> **このファイルの役割**: ADR [0047](0047-session-secrets-not-persisted-to-sessions-json.md) の決定6（Data Protection Keychain 移行の見送り）を覆し、あわせてモバイルトークンを単一・全権から端末単位へ変えると決めた理由・棄却案・帰結。
> **書かないもの**: 現行の構成・データモデル（→ [architecture/mobile-device-pairing.md](../architecture/mobile-device-pairing.md)）、移行時の運用手順（→ [operations/mobile-per-device-token-migration.md](../operations/mobile-per-device-token-migration.md)）、run の作業経緯（→ [delivery/0032-keychain-hardening-per-device-tokens-worklog.md](../delivery/0032-keychain-hardening-per-device-tokens-worklog.md)）。

## 文脈

- ADR 0047 の決定6 では `kSecUseDataProtectionKeychain`（以下 DPK）の採用を**見送った**。理由は「既存 Keychain 項目との互換リスクに対し、macOS のファイルベース Keychain では得られる保護が限定的」だった。
- その後 ADR [0158](0158-debug-build-stable-code-signature.md) で Debug ビルドも証明書がある環境では正規署名するようにしたため、**開発ビルドでも entitlement とプロビジョニングプロファイルを載せられる**ようになった。DPK の前提条件（`keychain-access-groups` entitlement）が満たせる。
- モバイルトークンは**単一・全権**（ADR 0074 決定1）だった。端末が 2 台以上あっても Keychain 項目は 1 つで、「1 台だけ接続を切る」ができない。旧 UI の「トークンを再発行」は**全端末を一斉に切る**操作であり、粒度が粗い。
- 単一トークンでは、どの端末がいつペアリングされたかも記録されない（ユーザーが自分の接続状況を確認できない）。

## 決定

1. **Keychain アクセスを `KeychainItemAccessor`（AgentDomain）に集約し、DPK を優先する**。`kSecUseDataProtectionKeychain: true` で読み書きし、`errSecMissingEntitlement`(-34018) が返る環境ではファイルベース Keychain へ**自動フォールバック**する。どちらを使ったかは `backend()` で観測でき、起動ログに 1 行出す。
   - フォールバックを残すのは、entitlement を載せられないビルド（署名証明書の無い CI・アドホックな検証ビルド）でアプリが起動不能になるのを避けるため。
2. **モバイルトークンを端末単位にする**。`PairedDevice`（id・表示名・トークン・requester セッション・発行時刻・ペアリング時刻・有効期限）を `PairedDeviceStore` が Keychain 項目 1 つへまとめて永続化する。
3. **旧・単一トークンの Keychain 項目は起動時に削除する**（`deleteItemInAllBackends` で DPK 側とファイルベース側の両方から）。**既存のペアリング済み端末は 1 回だけ再ペアリングが必要**になる。
4. **「QR を表示」のたびに新しい端末を発行する**。既存端末の接続は切れない。旧「トークンを再発行」ボタンと、それに付随する説明文は削除し、**端末単位の失効**に置き換える。
5. **端末の発行・失効のたびに Dashboard の特権 requester 集合を更新する**。集合の算出規則の正本は `MobileBootstrap.privilegedRequesters(for:)` に置き、UI 層で再実装しない（起動時に一度だけ設定する実装では、起動後に発行した端末が非子孫セッションを失効できない）。
6. **DPK を有効にしたビルドは Automatic 署名を前提とする**（`PHLOX_DEBUG_CODE_SIGN_STYLE = Automatic`）。`keychain-access-groups` は開発用プロビジョニングプロファイルが認可しないと AMFI に SIGKILL されるため、Manual 署名（Developer ID）では成立しない。

## 棄却案

- **単一トークンを維持し、DPK 化だけ行う** — 保護レベルは上がるが「1 台だけ切る」が実現できず、ユーザーが抱える実際の困りごと（家族の端末・古い端末を個別に切りたい）が残るため不採用。
- **DPK 単独（フォールバックなし）** — entitlement を載せられない環境でモバイル機能どころかアプリ起動が失敗する。開発・CI の可搬性を失うため不採用。
- **旧トークンを新モデルへ引き継ぐ移行** — 旧トークンはファイルベース Keychain にあり、そのまま持ち込むと「保護レベルの違う端末エントリ」が混在する。移行コードとその検証コストに対し、再ペアリング 1 回のほうが安く確実なため不採用（この判断はゲート①でユーザー承認済み）。
- **`ControlServer` に端末モデルを持たせる** — 認証成立を記録するのに最短だが、下位層（ControlServer）が上位のドメインモデル（AgentDomain の `PairedDevice`）へ依存する向きになるため不採用。トークン文字列だけを渡すクロージャ注入にした。

## 結果

- **既存ユーザーは、このリリース後 1 回だけ iPhone の再ペアリングが必要**（QR 再スキャン）。手順は operations の移行 Runbook に置く。
- 端末ごとの失効ができるようになり、設定画面に端末一覧（名前・ペアリング日時・失効ボタン）が出る。
- 署名要件が上がる: DPK entitlement を載せた Debug ビルドは Automatic 署名＋`-allowProvisioningUpdates` が要る。Manual（Developer ID）設定のローカル `Signing.local.xcconfig` を使っている環境では、entitlement 付きビルドはそのままでは通らない。
- ADR 0047 の決定6 は**本 ADR で覆した**（0047 の他の決定は有効なまま）。
- 既知の未検証: 設定画面の端末一覧の**実機での見え方**（行が増えたときのスクロール・失効ボタンのはみ出し・Dynamic Type）は、この run では検証環境で Tailscale を検出できず実端末をペアリングできなかったため未確認。コードと白箱テストでの担保にとどまる。
