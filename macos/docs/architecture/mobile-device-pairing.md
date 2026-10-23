---
status: active
last-verified: 2026-08-02
---

# モバイル端末ペアリング（端末別トークンと Keychain 保護）

> **このファイルの役割**: iPhone と Mac のペアリングを支える**現行の**構成・データモデル・I/F（端末別トークン、Keychain のバックエンド選択、起動シーケンス）。
> **書かないもの**: なぜこの形にしたか（→ ADR [0160](../adr/0160-data-protection-keychain-and-per-device-mobile-tokens.md)）、QR ペイロード形式（→ [specs/qr-pairing-contract.md](../specs/qr-pairing-contract.md)）、移行手順（→ [operations/mobile-per-device-token-migration.md](../operations/mobile-per-device-token-migration.md)）。

## 全体像

```
SettingsView / MobileTokenViewModel   ← UI（端末一覧・名前変更・QR 表示・失効）
        │
        ▼
MobileBootstrap                       ← 起動シーケンスと特権 requester 規則の正本
        │
        ▼
MobileDeviceProvisioner               ← 端末の発行・名前変更・ペアリング記録・失効・期限切れ掃除
        │
        ▼
PairedDeviceStore (protocol)          ← 永続化の境界
   ├─ KeychainPairedDeviceStore       ← 本番
   └─ InMemoryPairedDeviceStore       ← テスト / Keychain 失敗時のフォールバック
        │
        ▼
KeychainItemAccessor (protocol)       ← Keychain バックエンドの選択と実アクセス
   ├─ SecItemKeychainAccessor         ← DPK 優先・ファイルベースへ自動フォールバック
   └─ InMemoryKeychainAccessor        ← テスト
```

`ControlServer` は `AgentDomain` の端末モデルに依存しない。認証成立時に**トークン文字列だけ**をクロージャで通知し、`MobileBootstrap.makeAuthenticatedTokenHook(...)` が受けて記録・UI 通知へ振り分ける。

## データモデル

`PairedDevice`（`Codable`・`Identifiable`）— 端末 1 台につき 1 件。全件をまとめて JSON 化し、Keychain 項目 1 つへ保存する。

| フィールド | 意味 |
|---|---|
| `id: UUID` | 端末 ID。失効の単位 |
| `name: String` | ユーザーが編集できる表示名 |
| `token: String` | 64 文字の16進小文字。Bearer 認証に使う。**UI・ログ・ペーストボードへ出さない**（QR 画像を除く） |
| `requesterSessionID: SessionID` | この端末からの操作を代表する requester。Dashboard の特権 requester 集合へ入る |
| `issuedAt: Date` | 発行時刻 |
| `pairedAt: Date?` | 初回の認証成立時刻。`nil` なら UI 上「未接続」 |
| `expiresAt: Date` | 有効期限。**未ペアリングの端末だけ**が期限切れで掃除される |

## Keychain のバックエンド選択

`SecItemKeychainAccessor` は `kSecUseDataProtectionKeychain: true`（Data Protection Keychain）で読み書きし、`errSecMissingEntitlement`(-34018) が返った場合にファイルベース Keychain へフォールバックする。判定結果は 1 回だけ探索してキャッシュし、`backend()` が `.dataProtection` / `.fileBased` を返す。`CompositionRoot` は起動ログにこの値を 1 行出す。

DPK を使うには `keychain-access-groups` entitlement と、それを認可するプロビジョニングプロファイルが要る（→ [operations/mobile-per-device-token-migration.md](../operations/mobile-per-device-token-migration.md)）。

`deleteItemInAllBackends(service:account:)` は DPK 側とファイルベース側の両方へ削除を投げ、`errSecSuccess` / `errSecItemNotFound` / `errSecMissingEntitlement` 以外が返ったときだけ失敗にする。旧・単一トークン項目の掃除に使う（どちらのバックエンドに残っているか分からないため）。

## 起動シーケンス

`MobileBootstrap.run(provisioner:tokenStore:)` が次を 1 関数で行う。`CompositionRoot` は手順を再実装しない。

1. `loadAndMigrate()` — 旧・単一トークンの Keychain 項目を削除し、期限切れの**未ペアリング**端末を掃除して現存端末を返す。
2. `syncRegistrations(into:)` — 現存する全端末のトークンを `SessionTokenStore` へ登録し直す（消えた端末の登録は取り消す）。
3. `privilegedRequesters(for:)` — 現存端末の requester 集合を返す。**未ペアリング端末も含む**（QR 発行直後にトークンが有効でなければならないため）。

Keychain アクセスが失敗しても起動は続行し、インメモリの `PairedDeviceStore` へ退避してその事実をログへ残す（トークン値は出さない）。

## 実行時の更新

- **QR を表示**するたびに `issueDevice(name:)` で新端末を発行する。既存端末の接続は切れない。発行と同時にその端末の requester を Dashboard の特権 requester 集合へ**追加**する。
- **認証成立**（`ControlServer` が Bearer トークンを解決）で `markPaired(token:)` が `pairedAt` を記録する。401 のときは呼ばれない。記録の成否は `Result` で返り、失敗はログへ回して処理は続行する（認証自体は既に成立しているため）。
  - `ControlServer` は UI 層より先に組み立てられるため、通知は `MobileDevicePairingRelay`（actor）が中継する。ハンドラ差し込み前に届いた通知は真偽のラッチで保持し、`setHandler` 時に 1 回だけ配送する。
- **失効**（`revoke(id:)`）でその端末を削除し、requester を特権集合から**取り除く**。

## 端末名の変更

設定の「モバイル連携」→「接続済みの端末」で「名前を変更」を押し、行内の入力欄で編集して「保存」する。「キャンセル」または Esc で変更を破棄する。前後の空白・改行は取り除き、空の名前は保存しない。保存失敗時はエラーを表示し、入力内容を残す。

`MobileDeviceProvisioner.rename(id:name:)` は既存操作と同じロックで最新の端末を読み直し、名前だけを更新して同じストアへ保存する。端末 ID・トークン・requester・発行日時・ペアリング日時は維持する。失効済みなど、対象が存在しない場合はエラーにする。

GUI が常駐プロセスの状態を表示している場合は `MobileRuntimeCommand.rename(id:name:)` を送り、常駐プロセス側で同じ保存処理を実行する。応答を待つ間は編集操作を無効にし、保存の成功を受けてから編集を閉じる。

## 並行性

`MobileDeviceProvisioner` の read-modify-write（`issueDevice` / `rename` / `markPaired` / `revoke` / `pruneExpired`）は `NSLock` で直列化し、`async` の `syncRegistrations` は内部の actor で直列化する。`KeychainPairedDeviceStore` の直列化ロックは**インスタンス変数**なので、同じ Keychain 項目を指すストアを 2 つ作るとロストアップデートが起きる。`CompositionRoot` で**単一インスタンスを生成して全消費者へ共有**すること。
