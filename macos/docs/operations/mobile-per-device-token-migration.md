---
status: active
last-verified: 2026-08-02
---

# Runbook: 端末別モバイルトークンへの移行と、DPK 署名要件

> **このファイルの役割**: 端末別トークン導入リリースの移行手順（ユーザー影響・確認方法・切り戻し）と、Data Protection Keychain（DPK）を有効にしたビルドを作るときの署名手順。
> **書かないもの**: 採用理由（→ ADR [0160](../adr/0160-data-protection-keychain-and-per-device-mobile-tokens.md)）、現行の構成（→ [architecture/mobile-device-pairing.md](../architecture/mobile-device-pairing.md)）。

## ユーザー影響（このリリースで 1 回だけ）

- **既にペアリング済みの iPhone は接続できなくなる。再ペアリングが必要**。旧・単一トークンの Keychain 項目は初回起動時に削除される。
- 手順: Mac の 設定 → モバイル接続 → 「QR を表示」→ iPhone アプリで再スキャン。
- 以降は「QR を表示」するたびに**新しい端末**が発行される。既存端末は切れない。1 台だけ切りたいときは端末一覧の失効ボタンを使う。
- 旧「トークンを再発行」ボタンは無くなった（全端末を一斉に切る操作が、端末単位の失効に置き換わったため）。

## 移行が済んだかの確認

1. アプリの起動ログに `keychain backend = dataProtection`（entitlement 未付与のビルドでは `fileBased`）が 1 行出る。
2. 設定のモバイル接続に端末一覧が出る。移行直後は 0 件（＝旧トークンが消えている）。
3. QR を再スキャンすると一覧に 1 件現れ、認証が成立した時点で「未接続」からペアリング日時へ変わる。

## 切り戻し

旧バージョンへ戻すと、削除済みの旧トークン項目は**復元されない**。旧バージョン側で「トークンを再発行」してから iPhone を再スキャンすること。

## DPK entitlement を有効にしてビルドする

DPK は `keychain-access-groups` entitlement を要求し、これは**プロビジョニングプロファイルが認可していないと AMFI がプロセスを SIGKILL する**。したがって Automatic 署名が前提になる（Manual / Developer ID では成立しない）。

```bash
xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug \
  PHLOX_CODE_SIGN_ENTITLEMENTS=App/Phlox-DataProtectionKeychain.entitlements \
  PHLOX_DEBUG_CODE_SIGN_STYLE=Automatic \
  PHLOX_DEBUG_CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build
```

- `CODE_SIGN_STYLE=Automatic` を**コマンドラインで直に渡さない**。SPM のパッケージターゲットまで巻き込んで "requires a development team" で落ちる。上のように `PHLOX_DEBUG_*` 変数だけを上書きする。
- 成功したら次を確認する:
  - `<app>/Contents/embedded.provisionprofile` が存在する
  - `codesign -d --entitlements - <app>` に `keychain-access-groups = <TEAMID>.com.phlox.Phlox.debug` が出る
- ローカルの `macos/Config/Signing.local.xcconfig` が `PHLOX_DEBUG_CODE_SIGN_STYLE = Manual`（Developer ID）の場合、entitlement 付きビルドはそのままでは通らない。**このファイルは編集せず**、上のように変数を上書きして検証する。
- 受け入れスクリプト `macos/scripts/tests/test_signing_entitlements_variants.sh` は `SKIP_BUILD=1` で構造チェックのみ実行できる。ビルドを伴う検査は上記の署名条件が揃った環境でのみ通る。
