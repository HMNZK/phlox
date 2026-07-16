---
status: active
last-verified: 2026-07-16
---

# サイト配信と macOS リリース Runbook

> **このファイルの役割**: phlox.cc サイト配信と macOS アプリ配布（DMG ダウンロード・Sparkle 自動更新）の運用手順。
> **背景・なぜこの構成か**: [`adr/0089-phlox-cc-served-from-monorepo-site.md`](../adr/0089-phlox-cc-served-from-monorepo-site.md)

## 現在の配信トポロジー

| 対象 | 配信元 | URL |
|---|---|---|
| Web サイト（phlox.cc） | `HMNZK/phlox` の `site/` を GitHub Actions Pages で配信 | https://phlox.cc/ |
| 初回ダウンロード DMG | `HMNZK/phlox` の Releases | https://github.com/HMNZK/phlox/releases/latest/download/Phlox.dmg |
| Sparkle 更新フィード | `HMNZK/phlox` の `site/appcast.xml`（phlox.cc から配信） | https://phlox.cc/appcast.xml |
| Sparkle 更新バイナリ（zip/delta） | `HMNZK/phlox-dist` の Releases（tag `updates`） | github.com/HMNZK/phlox-dist/releases/download/updates/… |

- カスタムドメイン `phlox.cc` は `HMNZK/phlox` の Pages に設定。DNS は GitHub Pages の apex A レコード（185.199.108–111.153）で**リポジトリ非依存**。
- アプリ側の Sparkle 設定（`macos/project.yml` / `macos/App/Info.plist`）: `SUFeedURL = https://phlox.cc/appcast.xml`、`SUPublicEDKey = SxwucM1aQ79y8oB0XjN2HDmBBs75LpX8nlOcYQHKXqo=`。

## サイトを更新する

1. `site/` 配下を編集して `main` に push する。
2. `.github/workflows/pages.yml` が起動し `site/` を phlox.cc へデプロイする（`site/**` または当ワークフロー変更時に自動起動。手動起動は `gh workflow run pages.yml --repo HMNZK/phlox`）。
3. 検証:
   ```bash
   gh run list --repo HMNZK/phlox --workflow pages.yml --limit 1   # success を確認
   curl -sI https://phlox.cc/ | head -1                            # HTTP/2 200
   ```
4. ブラウザで旧版が見える場合はファビコン等のキャッシュ。`Cmd+Shift+R` で強制再読込。サーバー実体は `curl` で確認する。

## macOS アプリをリリースする

前提: DMG のビルド・Developer ID 署名・notarytool 公証・stapler は `swift-release` スキル（`sign_and_notarize.sh`）で行う。公証済み DMG は `stapler validate` 成功かつ `spctl -a -t open` が `accepted, source=Notarized Developer ID` になること。

リリース時は **3 箇所**を更新する（[ADR 0089](../adr/0089-phlox-cc-served-from-monorepo-site.md) の移設により配信先が変わった点に注意）:

1. **初回ダウンロード用 DMG を `HMNZK/phlox` の Release に公開する**（これをしないと `phlox/releases/latest` が旧版に固定される）:
   ```bash
   gh release create vX.Y.Z --repo HMNZK/phlox --target main \
     --title "Phlox X.Y.Z" --notes "…" path/to/Phlox.dmg
   ```
2. **Sparkle 更新バイナリ（zip/delta）を `HMNZK/phlox-dist` の Release（tag `updates`）にアップロードする**（現行の更新配信基盤）。
3. **`site/appcast.xml`（＝phlox.cc が配信する正）に新バージョンの `<item>` を追記して `main` に push する**。旧 `phlox-dist/appcast.xml` はもう phlox.cc では配信されないので更新しても意味がない。enclosure URL・`sparkle:version`・`sparkle:edSignature` を新バイナリに合わせる。push で Pages が自動デプロイ。

### リリース後の検証

```bash
# 初回ダウンロード
curl -s -o /dev/null -w '%{http_code}\n' -L \
  https://github.com/HMNZK/phlox/releases/latest/download/Phlox.dmg          # 200

# 更新フィード（最新版・アプリの build 番号と一致するか）
curl -s https://phlox.cc/appcast.xml | grep -m1 sparkle:version

# 更新バイナリの疎通
curl -s -o /dev/null -w '%{http_code}\n' -L \
  "$(curl -s https://phlox.cc/appcast.xml | grep -oE 'https://[^\"]+\.zip' | head -1)"  # 200
```

バージョン整合: `macos/project.yml` の `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` と appcast の `sparkle:shortVersionString` / `sparkle:version`、Release タグを一致させる。

## ロールバック

- **サイト**: `main` を前コミットへ戻して push（Pages が再デプロイ）、または直前の成功 run を `gh run rerun` する。
- **DMG ダウンロード**: 問題のある Release を `gh release delete vX.Y.Z --repo HMNZK/phlox` すると `releases/latest` が一つ前へ戻る。
- **自動更新**: `site/appcast.xml` から該当 `<item>` を除去して push すれば、そのバージョンは配信対象外になる。
