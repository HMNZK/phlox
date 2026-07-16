---
status: active
last-verified: 2026-07-08
---

# ADR 0047: セッション機密（token・秘密系 env）を sessions.json へ平文永続化しない

> **このファイルの役割**: 2026-07 コードベース監査（CWE-312 相当）への対応として「セッション機密の永続化を止める」と決めた理由・棄却案・帰結。
> **書かないもの**: 現行の保存データ仕様（→ `architecture/app-data-storage-and-flavor.md`）、run の作業経緯（→ `delivery/0025-pm2-domain-secrets-audit-remediation-worklog.md`）。

## 文脈

- `PersistedSessionDescriptor` は CLI セッションの認証トークン（`token`）と環境変数辞書全体（`env`。
  `PHLOX_TOKEN` や API キー類を含みうる）を、手書き `encode(to:)` で `sessions.json` に平文シリアライズ
  していた。書き込みはパーミッション指定なしの `.atomic` write（umask 依存で他ユーザー可読になりうる）。
- 調査（rg 全数列挙）の結果、永続化された token の消費箇所は DashboardFeature の4箇所のみで、
  復元経路 `DashboardViewModel.restoreSession` には既に `descriptor.token ?? makeToken()` の nil
  フォールバックがあった。復元は常に「孤児 reap → 新規プランで再 spawn」（cold restart）であり、
  再 spawn 時に新トークンが env へ注入されるため、**トークンを永続化しなくても復元機能は壊れない**。
- あわせて、全権モバイルトークンの NSPasteboard 無防備コピー（CWE-522）と、テスト用 Keychain 迂回
  ゲート（`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN`）が Release でも有効という周辺所見があった。

## 決定

1. **`encode(to:)` は `token` を一切出力しない**（案A）。`init(from:)`（decode）は後方互換のまま
   token を読み続ける。既存ファイルの旧 token は次回保存時に自然に消える（明示的マイグレーション不要）。
2. **`env` は encode 時に秘密系キーを除外**する。規則: キーの大文字化形が接尾辞
   `_TOKEN`/`_KEY`/`_SECRET`/`_PASSWORD`/`_CREDENTIAL`/`_CREDENTIALS`/`_PASSPHRASE` で終わる、
   または完全一致 `TOKEN`/`KEY`/`SECRET`/`PASSWORD`/`PASSPHRASE`/`CREDENTIALS`/`AUTHORIZATION`。
   decode ではフィルタしない（旧ファイル復元互換）。
3. **`JSONFileStore` は保存ファイルを 0600 に明示設定**し、無変更スキップは「バイト列一致＋書き込み後
   に記録した stat（サイズ・mtime・パーミッション）と実ファイルの一致」の両立時のみ（判定不能は書き込む側へ）。
4. **モバイルトークンのコピーは `SecurePasteboard`（AgentDomain）経由**に統一: `org.nspasteboard.ConcealedType`
   併記＋changeCount 照合つき 60 秒自動クリア（ユーザーの後続コピーは消さない）。
5. **`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN` ゲートは `#if DEBUG` で隔離**（Release バイナリから経路を物理的に排除）。
6. `KeychainMobileTokenStore` の `kSecUseDataProtectionKeychain` 属性追加は**見送り、doc 修正で乖離解消**
   （既存 Keychain 項目との互換リスクに対し、得られる保護が macOS ファイルベース Keychain では限定的なため）。

## 棄却案

- **案B: セッション token の Keychain vault 移行** — 現行の「同一トークンを復元」意味論を完全維持できるが、
  復元が常に再 spawn（新トークン注入）である以上維持する意味が薄く、実装・テストの複雑さに見合わない。
- **案C: 文書化のみ** — 平文漏出リスクが残るため不採用。
- **decode 側でもフィルタ** — 旧ファイルからの復元互換を壊すため不採用（encode のみで新規漏出は止まる）。

## 結果

- `sessions.json` に token キーと秘密系 env キーが出力されなくなる（受け入れテスト
  `SessionSecretsPersistenceAcceptanceTests` で固定）。既存ファイルは次回保存で自然スクラブ。
- **公開 API のシグネチャ変更なし**（encode セマンティクスのみの変更）。AgentDomain を import する
  7 パッケージ＋App は再コンパイルのみで追随する。
- 既知の残余: (a) 過去の `sessions.json.corrupt-*` 退避ファイルに旧 token が残っている可能性
  （ユーザーデータ側・コード修正のスコープ外）。(b) DashboardFeature の restore-error 再試行経路
  （`makeRestoreErrorSession`）は永続化 env をそのまま spawn に使うため、フィルタ後は `PHLOX_TOKEN` を
  含まない env で再 spawn される。hook 認証（PM-1 の導入後）で顕在化しうるため、DashboardFeature 側の
  対応候補として引き継ぐ（→ worklog 0025）。
