---
status: active
last-verified: 2026-07-06
---

# Release 版と Debug 版を同時に使う

安定版（Release）で日常開発を回しながら、コード変更を Debug 版で並行して確認するための手順。Debug ビルドは自動的に別のデータ保存先（`~/Library/Application Support/Phlox-Debug`）・別 bundle id（`com.phlox.Phlox.debug`）・別 Keychain を使うため、Release 版のセッションやデータを一切汚さずに同時起動できる（設計は ADR 0034 / 構造は `architecture/app-data-storage-and-flavor.md`）。

## 手順

0. **署名を用意する**（初回のみ・任意だが強く推奨）。証明書を持っているなら、リポジトリ直下に
   `Signing.local.xcconfig` を置いて Debug も正規署名にする（雛形は `Signing.example.xcconfig`）:
   ```
   PHLOX_DEVELOPMENT_TEAM = <あなたの Team ID>
   PHLOX_DEBUG_CODE_SIGN_STYLE = Manual
   PHLOX_DEBUG_CODE_SIGN_IDENTITY = Developer ID Application
   ```
   置かなければ従来どおり ad-hoc 署名でビルドできる。ただし ad-hoc は**リビルドのたびに
   designated requirement（cdhash）が変わる**ため、TCC（ファイルとフォルダ・画面収録・
   アクセシビリティ）の許可／拒否が毎回リセットされ、ビルドし直すたびに同じ承認ダイアログが出る
   （→ [ADR 0158](../adr/0158-debug-build-stable-code-signature.md)）。

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

- **`scripts/debug-build-restart.sh` は共存目的に使わない**: このスクリプトは `osascript -e 'quit app "Phlox"'` → `pkill -x Phlox`（プロセス名一致）で既存インスタンスを終了させる。Release 版と Debug 版は実行ファイル名がどちらも `Phlox` のため、これを実行すると**稼働中の Release 版まで巻き込んで終了する**。Release 版を残したまま Debug 版を起動するには、本ガイドの手動手順（別 `derivedDataPath` へ `xcodebuild` → `open`）を使う。
- **TCC 権限は別扱い**: bundle id が違うため、Debug 版の画面収録・アクセシビリティ権限は Release 版とは別に、初回に再取得を求められる。手順 0 の正規署名をしていれば、答えた結果はリビルドを跨いで保持される（ad-hoc のままだと毎回聞かれる）。署名方式を切り替えた直後は、ad-hoc 時代の記録が引き継がれないためサービスごとに一度ずつ聞かれる。
- **ダイアログが「Phlox」名義でも、触っているのは子プロセスのことがある**: `claude` などの下層 CLI がファイルへアクセスすると、macOS は責任プロセスである Phlox の名前で許可を求める。何が要求したかは `log show --predicate 'process == "tccd"'` の `AUTHREQ_ATTRIBUTION`（`accessing=` が実際のアクセス元）で確認できる。
- **稼働中 Debug の上書き禁止**: 手順2のとおり、動いている Debug 版と同じ `derivedDataPath` へビルドしない。
- **下層 CLI は共有**: 分離されるのは Phlox 自身のデータ層まで。spawn 先の `claude`/`codex`/`cursor` 自身の home（`~/.claude` 等）は両インスタンスで共有される。
