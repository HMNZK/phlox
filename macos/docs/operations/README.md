---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-16
---

# operations/

**役割（ここにしか書かない）**: 運用 Runbook（デプロイ/マイグレーション/ロールバック/障害対応）

**書かないもの**: 開発オンボーディング（→ guides/）

**Diátaxis**: How-to

**命名**: 小文字 kebab-case・ASCII・`.md`（索引のみ `README.md`）。順序ありは `NNNN-kebab.md`。

## 現在あるファイル（固定名の入口ファイルは未作成。以下が現行の入口）

- [`site-deploy-and-release.md`](site-deploy-and-release.md) — phlox.cc サイト配信（GitHub Actions Pages）と macOS アプリ配布（DMG ダウンロード・Sparkle 自動更新）の運用手順
- `release-<版>.md`（例: [`release-1.14.0.md`](release-1.14.0.md)） — 各版のリリース記録（検証結果・配布物・公開後の確認）。手順の正本は `site-deploy-and-release.md`
- [`mobile-per-device-token-migration.md`](mobile-per-device-token-migration.md) — 端末別モバイルトークン移行（既存端末の再ペアリング）と Data Protection Keychain の署名要件
