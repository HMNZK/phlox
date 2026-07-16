---
status: active
last-verified: 2026-07-08
---

# アプリのデータ保存とビルド種別（AppFlavor）

**今こう動いている**: Phlox のローカルデータ保存先とアプリ identity は、ビルド種別（`AppFlavor`）に応じて Release と Debug で分離される。なぜこう分けたかは ADR 0034 を参照。

## AppFlavor（`Packages/AgentDomain`）

`AppFlavor` はビルド種別を表す `enum`。`AppFlavor.current` は `#if DEBUG` により Debug ビルドで `.debug`、Release ビルドで `.release` に確定する（コンパイル時定数）。種別ごとに次を返す。

| | Release (`.release`) | Debug (`.debug`) |
|---|---|---|
| `appSupportDirectoryName` | `Phlox` | `Phlox-Debug` |
| `mobileTokenKeychainService` | `com.phlox.Phlox.mobileToken` | `com.phlox.Phlox.debug.mobileToken` |
| `runsLegacyMigration` | `true` | `false` |
| bundle id（`project.yml`） | `com.phlox.Phlox` | `com.phlox.Phlox.debug` |
| 表示名（`CFBundleDisplayName`） | `Phlox` | `Phlox (Debug)` |

## AppSupportLocator（`Packages/AgentDomain`）

アプリサポートのルート URL を解決する単一リゾルバ。`~/Library/Application Support/<flavor>` を返す（`<flavor>` は `Phlox` か `Phlox-Debug`）。2つのオーバーロードを持つ。

- `appSupportDirectoryURL(flavor:fileManager:)` — FileManager 経由。`CompositionRoot` が使用。
- `appSupportDirectoryURL(flavor:home:)` — home 起点で組み立て。`DashboardFeature` 側（テストで home 差し替え）が使用。

このデータディレクトリ配下に、セッション永続化・`transcripts/`・`messages.sqlite`・`workspace/`・`hooks.json`・`ports.json` 等が置かれる。かつて分散ハードコードされていた `Application Support/Phlox` 参照は、この locator 経由に統一済み（`CompositionRoot` / `AppEnvironment` / `ClaudeUsageProvider` / `ClaudeGlobalStatusLineCleanup` / `TranscriptStore`。`CursorShellSanitizer` の Caches 側 ZDOTDIR 親も flavor 名で分離）。

## インスタンス間の分離

- **データ**: Release は `Phlox`、Debug は `Phlox-Debug` を使う。互いのセッション・DB・`ports.json` を触らない。
- **ポート**: 各インスタンスは自分のデータディレクトリの `ports.json` を希望ポートに使い、埋まっていれば OS 任せの空きポートへフォールバックする。データディレクトリが別なので `ports.json` も別になり衝突しない。
- **セッションの hook/CLI 経路**: `ports.json` に依存しない。spawn 時に各セッションへ注入される env（`PHLOX_API_URL`/`PHLOX_TOKEN`/`CLAUDE_HOOKS_URL`）で、そのセッションを spawn したインスタンスのポートへ確実に届く。
- **アプリ identity / UserDefaults / Keychain**: bundle id が異なるため macOS 上で別アプリ扱いになり、`open` で独立起動でき、UserDefaults plist と Keychain も分離される。
- **移行**: Debug は `AgentDashboard→Phlox` のレガシー移行を実行せず、空の `Phlox-Debug` から始まる。

## 保存データの保護（2026-07 監査対応後の現行挙動）

なぜこうしたかは ADR 0047（セッション機密）・ADR 0048（メッセージ DB）を参照。

- **`sessions.json`**: セッションの認証トークン（`token`）は書き込まれない。`env` は encode 時に
  秘密系キー（大文字化形が `_TOKEN`/`_KEY`/`_SECRET`/`_PASSWORD`/`_CREDENTIAL(S)`/`_PASSPHRASE` で
  終わる、または `TOKEN`/`KEY`/`SECRET`/`PASSWORD`/`PASSPHRASE`/`CREDENTIALS`/`AUTHORIZATION` に
  完全一致）を除外して保存される。decode は旧ファイル互換（旧 token/env も読める。次回保存で自然スクラブ）。
  復元時のトークンは `DashboardViewModel.restoreSession` の `?? makeToken()` フォールバックで新規発行され、
  再 spawn 時に env へ注入される。
- **`JSONFileStore`（sessions.json / projects.json）**: 保存ファイルは 0600（所有者のみ）。同一内容の
  連続 save は「バイト列一致＋書き込み後 stat（サイズ・mtime・パーミッション）一致」の両立時のみスキップ
  され、プロセス外でファイルが変更・削除された場合は必ず書き込みへ倒れる。
- **`messages.sqlite`（SQLiteMessageStore）**: 開店手順は「列補修（スキーマ形状ベースの冪等 migration）
  → `idx_messages_in_reply_to` を含む索引作成 → user_version 確定 → 保持削除」の固定順。
  `created_at` が 30 日超の行は開店時に削除される（best-effort・既定 30 日は `init` の引数で変更可）。
  WAL＋`synchronous=NORMAL`。
- **モバイルトークン**: 保存は Keychain（`mobileTokenKeychainService`・上表）。設定画面のコピーは
  `SecurePasteboard`（AgentDomain）経由で `org.nspasteboard.ConcealedType` を併記し、changeCount 照合
  つきの 60 秒自動クリアが予約される。テスト用のインメモリ供給ゲート
  （`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN`）は Debug ビルド限定（Release バイナリには経路が存在しない）。
- **カスタムエージェント定義（`~/.config/phlox/agents.json`）**: 信頼できない入力として扱い、
  `agents` 配列の非辞書要素・不正 `colorHex`（符号付き hex 等）はエントリ単位で skip してログに残す
  （起動クラッシュしない）。

## スコープ外（共有されるもの）

下層 CLI エージェント（`claude`/`codex`/`cursor` 自身の `~/.claude`・`~/.codex` 等の home）は Phlox のデータ層の外で、両インスタンス間で共有される。Phlox が分離するのは自身のデータ層のみ。
