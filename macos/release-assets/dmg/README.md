---
status: active
last-verified: 2026-07-17
---

# DMG インストール画面の資産

> **役割**: 配布 DMG（`Phlox.dmg`）の「デザインされたインストール画面」を再現するための資産一式。
> **なぜ repo に置くか**: これらが無いと `sign_and_notarize.sh` は背景・アイコン配置のない素の DMG を作り、インストール画面が簡素化する回帰が起きる（実際に 1.0.1 で一度発生した）。旧 DMG アーティファクトの中にしか無かった資産を復元して版管理下に置いた。

## ファイル

| ファイル | 用途 |
|---|---|
| `dmg-background.png` | DMG ウィンドウの背景画像（660×440）。紫グラデーション＋右向きシェブロン「>」（左のアプリを右の Applications へドラッグ、を示唆）。ビルド時に DMG 内 `.background/dmg-background.png` へ配置される。 |
| `DS_Store` | Finder のレイアウト定義テンプレート。ビルド時に DMG ボリューム直下の `.DS_Store` へコピーされる。ウィンドウ寸法・アイコンサイズ・アイコン座標・背景参照を保持する。（先頭ドット名 `.DS_Store` は `macos/.gitignore` で無視されるため、非ドット名 `DS_Store` で保存している。） |

## 重要: `.DS_Store` の結合条件

`DS_Store` テンプレートは次に**紐づいている**。いずれかを変えると背景が出ない／配置が崩れるため、変更時はテンプレートを作り直すこと:

- **ボリューム名 = `Phlox`**（`sign_and_notarize.sh` の `VOLNAME`、既定は `APP_NAME`）。背景はボリューム名＋相対パスのエイリアスで参照されるため、別名ボリュームでは解決しない。
- **背景ファイル名 = `dmg-background.png`**（`.background/` 配下）。
- **アイコン名 = `Phlox.app` と `Applications`**（座標はこの2名に対して記録されている）。

## 使い方（リリース時）

`sign_and_notarize.sh` に `DMG_BACKGROUND` と `DMG_DS_STORE` を渡す。詳細は `macos/docs/operations/site-deploy-and-release.md`。

```bash
cd macos
... DMG_BACKGROUND=release-assets/dmg/dmg-background.png \
    DMG_DS_STORE=release-assets/dmg/DS_Store \
    bash ~/.claude/skills/swift-release/scripts/sign_and_notarize.sh
```

## テンプレートを作り直す手順（結合条件を変える場合）

1. RW DMG を作ってマウントし、Finder で背景画像・アイコンサイズ・アイコン座標・ウィンドウ寸法を設定する。
2. Finder が書いた `.DS_Store` をボリュームから取り出し、この `DS_Store` として保存する。
3. 上記「結合条件」（ボリューム名・背景ファイル名・アイコン名）を合わせる。
