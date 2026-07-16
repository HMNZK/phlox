---
status: active
last-verified: 2026-07-06
---

# Release 版と Debug 版を同時に使う

安定版（Release）で日常開発を回しながら、コード変更を Debug 版で並行して確認するための手順。Debug ビルドは自動的に別のデータ保存先（`~/Library/Application Support/Phlox-Debug`）・別 bundle id（`com.phlox.Phlox.debug`）・別 Keychain を使うため、Release 版のセッションやデータを一切汚さずに同時起動できる（設計は ADR 0034 / 構造は `architecture/app-data-storage-and-flavor.md`）。

## 手順

1. **プロジェクトを再生成**（`project.yml` を変更したとき、または初回）:
   ```bash
   xcodegen generate
   ```

2. **Debug 版をビルド**。**稼働中の Debug 版があるなら、その出力先とは別の `derivedDataPath`** に出す（同じ出力先へビルドすると稼働中アプリのバイナリを上書きして落とす）:
   ```bash
   xcodebuild -project Phlox.xcodeproj -scheme Phlox \
     -configuration Debug -derivedDataPath /tmp/PhloxBuildCoexist build
   ```

3. **Debug 版を起動**。Release 版が動いていても、そのまま `open` で独立起動できる（bundle id が別なので `-n` は不要だが、確実に新プロセスを起こすなら付けてよい）:
   ```bash
   open /tmp/PhloxBuildCoexist/Build/Products/Debug/Phlox.app
   ```
   - 起動時の Keychain 許可ダイアログを避けたいだけの検証なら、`open --env PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1 <app>`（インメモリのトークン store に切替わり Keychain に触れない）。
   - Dock・メニューバー・About では **「Phlox (Debug)」** と表示され、Release 版（「Phlox」）と見分けられる。

## 何が分かれ、何が共有されるか

| | Release 版 | Debug 版 |
|---|---|---|
| データ | `~/Library/Application Support/Phlox` | `~/Library/Application Support/Phlox-Debug` |
| bundle id | `com.phlox.Phlox` | `com.phlox.Phlox.debug` |
| 表示名 | Phlox | Phlox (Debug) |
| Keychain（mobile token） | `com.phlox.Phlox.mobileToken` | `com.phlox.Phlox.debug.mobileToken` |
| ポート（hook/control） | 各自の `ports.json`（自動で別ポート） | 同左（衝突しない） |

Debug 版は空の `Phlox-Debug` から始まる（Release のセッションを引き継がない）。

## 注意

- **TCC 権限は別扱い**: bundle id が違うため、Debug 版の画面収録・アクセシビリティ権限は Release 版とは別に、初回に再取得を求められる。
- **稼働中 Debug の上書き禁止**: 手順2のとおり、動いている Debug 版と同じ `derivedDataPath` へビルドしない。
- **下層 CLI は共有**: 分離されるのは Phlox 自身のデータ層まで。spawn 先の `claude`/`codex`/`cursor` 自身の home（`~/.claude` 等）は両インスタンスで共有される。
