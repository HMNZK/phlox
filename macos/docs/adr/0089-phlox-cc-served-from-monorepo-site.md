---
status: active
last-verified: 2026-07-16
---

# 0089: phlox.cc をモノレポの `site/` から GitHub Actions Pages で配信する

## 文脈

phlox.cc は当初、別リポジトリ `HMNZK/phlox-dist`（`site/` の内容を平坦化した手動コピー）の GitHub Pages（legacy / branch=main / path=`/`）から配信していた。OSS モノレポ `HMNZK/phlox` の `site/` を正（アイコン・ヒーロー画像・モバイル節）として更新していたが、`phlox-dist` への再同期は手動だったため反映漏れが発生し、ライブの phlox.cc が旧版（7/6 デプロイのダーク端末アイコン）のまま止まった。**2 リポジトリ間の手動同期がドリフトの単一原因**だった。

phlox.cc は macOS アプリの主要な配布導線でもある（`Phlox.dmg` の初回ダウンロードと、Sparkle 自動更新フィード `appcast.xml` の配信元）。

## 決定

phlox.cc を **モノレポ `HMNZK/phlox` の `site/` ディレクトリから GitHub Actions Pages で配信**する。`site/` を更新して `main` に push すれば自動でライブへ反映される単一ソースにする。

- 配信手段は **GitHub Actions**（`.github/workflows/pages.yml`）で `site/` をアーティファクトとして deploy する。legacy（ブランチ）方式はソースが `/` か `/docs` のみでサブフォルダ `site/` を直接配信できないため。
- カスタムドメイン `phlox.cc` を `phlox-dist` Pages から外し、`phlox` Pages に設定する（DNS は不変。phlox.cc は GitHub Pages の apex A レコード 185.199.108–111.153 を指し、リポジトリ非依存）。
- Sparkle 自動更新フィード `appcast.xml` を `phlox-dist` からモノレポ `site/appcast.xml` に取り込み、phlox.cc から配信する。**更新バイナリ（zip/delta）は引き続き `phlox-dist` の Releases にホスト**する（appcast の enclosure がそこを指す）。
- macOS アプリの初回ダウンロード用 `Phlox.dmg` は `HMNZK/phlox` の Releases に公開する（`site/`・README の `phlox/releases/latest/download/Phlox.dmg` リンクが解決するように）。

## 結果

- `site/**` への push（`main`）で Pages ワークフローが走り phlox.cc へ自動デプロイ。単一ソース化でドリフトは解消。
- **`phlox-dist` は残す**（削除しない）: Sparkle 更新バイナリの Release ホストとして機能し続ける。site 配信の役割だけを `phlox` へ移した。
- **配信中の appcast は `site/appcast.xml`**（phlox.cc が `phlox` に移ったため）。今後リリースで更新フィードを書き換える手順は、旧 `phlox-dist/appcast.xml` ではなく `site/appcast.xml` を更新して push する運用に変わる。
- 初回ダウンロード導線は `phlox/releases/latest` に依存するため、リリースごとに DMG を `phlox` にも publish する必要がある。
- リリース運用の具体手順は [`operations/site-deploy-and-release.md`](../operations/site-deploy-and-release.md)。

## 却下した代替案

- **`phlox-dist` を配信元のまま手動同期を続ける**: ドリフトの根本原因を放置するため却下。
- **`site/` を `/docs` へ移して legacy Pages で配信**: モノレポの `macos/docs`・`ios/docs`（Diátaxis ドキュメント構造）と衝突するため却下。
