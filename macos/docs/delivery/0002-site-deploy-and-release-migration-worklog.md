---
status: completed
last-verified: 2026-07-16
---

# 0002: phlox.cc 配信のモノレポ移設と macOS リリース公開（作業ログ）

## 背景・きっかけ

ライブの phlox.cc が旧アイコン（ダーク端末）のまま更新されていなかった。調査の結果、phlox.cc は別リポジトリ `HMNZK/phlox-dist`（`site/` の手動コピー・最終デプロイ 7/6）から配信されており、モノレポ `site/` の更新（紫ネットワークアイコン・チャットモードのヒーロー画像・モバイル節）が反映されていなかった。2 リポジトリ手動同期のドリフトが原因。

## 何をしたか

- **サイトヒーロー画像の確定**: macOS ヒーローをチャットモードのモック（実行中サブエージェント＋使用量インスペクター）に差し替え、`site/assets/screenshot.webp` にコミット（`dev→verify→main`）。
- **配信のモノレポ移設**（→ [adr/0089](../adr/0089-phlox-cc-served-from-monorepo-site.md)）:
  - `.github/workflows/pages.yml` を追加（`site/` を GitHub Actions Pages で配信）。
  - `site/appcast.xml`（Sparkle フィード）を `phlox-dist` から取り込み。
  - `phlox` の Pages を Actions ソースで有効化し、カスタムドメイン `phlox.cc` を `phlox-dist` → `phlox` へ移設。
- **Download 404 の修正**: `HMNZK/phlox` に v1.0.0 Release を公開し、公式 `Phlox.dmg`（`phlox-dist` v1.0.0 とバイト一致）を添付。サイト/README の `phlox/releases/latest/download/Phlox.dmg` リンクが解決するようにした。
- **ドキュメント最新化**: 本 worklog・adr/0089・operations/site-deploy-and-release.md を追加。

## 検証結果

- サイト: phlox.cc が `icon.png=紫ネットワーク`・`screenshot.webp=最新`・全ページ 200 を配信（サーバー側 curl、キャッシュ回避）。Pages ワークフロー success。
- ダウンロード: `phlox/releases/latest/download/Phlox.dmg` → 200、取得 DMG は元と md5・サイズ一致。DMG は公証済み（`stapler validate` 成功・`spctl` accepted / Notarized Developer ID）。
- 自動更新: `SUFeedURL=https://phlox.cc/appcast.xml`、配信 appcast 最新 = 1.0.0 / build 12（アプリの `MARKETING_VERSION 1.0.0` / `CURRENT_PROJECT_VERSION 12` と一致）、更新バイナリ zip → 200。
- コード検証: `.claude/verify.sh` green（PhloxKit ユニットテスト・iOS シミュレータビルド・macOS 3 パッケージ 0 failures）。今回のコード外変更（ワークフロー yaml・appcast xml）はビルド/テストに影響なし。

## 積み残し・フォローアップ（重要）

移設により**今後のリリース手順が変わる**（→ [operations/site-deploy-and-release.md](../operations/site-deploy-and-release.md)）。放置すると次版で壊れる:

1. リリースごとに **DMG を `HMNZK/phlox` の Release にも公開**する（さもないと `phlox/releases/latest` が固定される）。
2. 更新フィードは **`site/appcast.xml`（phlox.cc が配信する正）を更新して push** する。旧 `phlox-dist/appcast.xml` はもう phlox.cc では配信されない。

- 提案: 上記 2 点を取りこぼさないリリース用 GitHub Actions の整備（公証は Developer ID・App 用パスワード等の Secrets 前提）。未着手。
