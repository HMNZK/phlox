---
status: active
last-verified: 2026-07-06
---

# ADR 0034: Release/Debug 同時併用を AppFlavor 分離で実現する

- Status: Accepted
- Date: 2026-07-06
- 関連: `AgentDomain.MobileTokenStore`、`CompositionRoot`（AppSupportMigrator）、`project.yml`

## 背景

Release 版と Debug 版の Phlox を**同時に起動できない**という制約があった。安定版（Release）で日常開発を回しながら、コード変更を Debug 版で確認したいという要求に応えられない。原因は3つの共有点にある。

1. **データディレクトリ `~/Library/Application Support/Phlox`**: env 上書きが無く、少なくとも5モジュール（`CompositionRoot` / `AppEnvironment` / `ClaudeUsageProvider` / `ClaudeGlobalStatusLineCleanup` / `TranscriptStore`）に分散ハードコードされ、両ビルドが同じセッション永続化・transcripts・message DB・workspace・`ports.json` を読み書きしていた。
2. **bundle id `com.phlox.Phlox`**: UserDefaults plist と Keychain サービス（`com.phlox.Phlox.mobileToken` リテラル）を共有。さらに macOS LaunchServices が同一 bundle id を同一アプリ扱いするため、`open` で2つ目のインスタンスが独立起動できなかった。
3. **`ports.json`**: 上記1の一部。ポートはハードコードでなく前回値を希望ポートとして使い、埋まっていれば OS 任せの空きポートへフォールバックするが、同じファイルを奪い合っていた。

分離を現実的にする鍵は、**セッションの hook/CLI 送信先が `ports.json` ではなく spawn 時に各セッションへ注入される env（`PHLOX_API_URL`/`PHLOX_TOKEN`/`CLAUDE_HOOKS_URL`。`scripts/phlox`・`scripts/hook-dispatcher.sh` はこれを読むだけ）で決まる**という事実である。つまりデータディレクトリを分ければ、各インスタンスのポートも `ports.json` も、セッションの通信経路も自動的に分離される。

## 決定

Debug ビルドに独立したアイデンティティを与え、Release の値・挙動は完全に不変に保つ。

1. **`AgentDomain.AppFlavor`**（`enum`、`#if DEBUG` で `.debug`/`.release` を確定）を導入し、「データディレクトリ名（`Phlox` / `Phlox-Debug`）」「Keychain サービス名（`com.phlox.Phlox.mobileToken` / `com.phlox.Phlox.debug.mobileToken`）」「レガシー移行の可否（Release=true / Debug=false）」を集約する。
2. **`AgentDomain.AppSupportLocator`** を単一リゾルバとし、分散ハードコードされていた全箇所をこれ経由に統一する（FileManager 版と home 注入版の2オーバーロード）。
3. **`KeychainMobileTokenStore`** の既定 service を `AppFlavor.current.mobileTokenKeychainService` に変更する。
4. **`project.yml`**: Debug 構成のみ `PRODUCT_BUNDLE_IDENTIFIER = com.phlox.Phlox.debug`、表示名を build setting `PHLOX_APP_DISPLAY_NAME`（base=`Phlox` / Debug=`Phlox (Debug)`）経由の `CFBundleDisplayName` にする。
5. **レガシー移行スキップ**: Debug は `runsLegacyMigration == false` で `AgentDashboard→Phlox` 移行を実行せず、空の `Phlox-Debug` から始める。

## 根拠

- **最小変更で完全分離に到達**: データディレクトリを分ければポート・ランデブー・通信経路が芋づる式に分離される（env 注入経路の知見）。個別のポート番号調整やプロセス間ロックは不要。
- **Release 不変を構造的に保証**: `AppFlavor.current` はコンパイル時定数（`#if DEBUG`）なので、Release ビルドでは `.release` に確定し、旧リテラルと1文字違わない値へ解決される（by construction）。フォールバックやランタイム分岐ではないため退行の余地が小さい。
- **見分けの確保**: 別 bundle id により macOS が別アプリ扱いし `open` で独立起動でき、`Phlox (Debug)` 表示で取り違えを防ぐ。UserDefaults/Keychain も bundle id 由来で自然に分離される。

## 見送り

- **別 macOS ユーザーで Debug を起動**（無改修案）: 同時に画面で見えず実用性が低い。却下。
- **env 変数 `PHLOX_APP_SUPPORT_DIR` による上書きのみ**: 第一手段は `#if DEBUG` とした（env 上書きの併用は今回は不要と判断し未実装）。将来必要になれば `AppSupportLocator` に注入口を足せる。
- **任意 N プロファイルの汎用マルチインスタンス対応**: 今回は Release vs Debug の2つに限定。
- **下層 CLI エージェント（`claude`/`codex`/`cursor` 自身の `~/.claude` 等）の分離**: スコープ外。分離は Phlox のデータ層のみで、両インスタンスが同一プロジェクトで同一 CLI を spawn した際の CLI 側競合は本 ADR の対象外。

## 影響

- **Debug 版**: データは `~/Library/Application Support/Phlox-Debug`、bundle id `com.phlox.Phlox.debug`、表示名 `Phlox (Debug)`、Keychain は別サービス、Caches の ZDOTDIR 親も `Phlox-Debug`。bundle id 変更に伴い TCC 権限（画面収録・AX）と Keychain 項目は新規扱いで再取得になる（想定内・むしろ分離できて望ましい）。
- **Release 版**: データ位置・bundle id・表示名・Keychain サービスすべて現行と不変（実測: `swift test` の Release ピンテスト green ＋ swiftc での `.current` 実測）。
- **実動作**: Release（`Phlox`）と Debug（`Phlox-Debug`）を同時起動し、別データ・別ポート・両プロセス共存・相互の `ports.json` 不干渉を実測で確認済み。
- **手順**: 開発中に両方を使う方法は `docs/guides/running-release-and-debug-together.md` を参照。
