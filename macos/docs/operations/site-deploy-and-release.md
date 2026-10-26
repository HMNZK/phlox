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

1. dev由来の作業ブランチで`site/`配下を編集する。下記の統合前検証を通し、共通マージツールでdev→verify→mainへ統合してからpushする。mainへの直接コミットはしない。
2. `.github/workflows/pages.yml` が起動し `site/` を phlox.cc へデプロイする（`site/**` または当ワークフロー変更時に自動起動。手動起動は `gh workflow run pages.yml --repo HMNZK/phlox`）。
3. 検証:
   ```bash
   gh run list --repo HMNZK/phlox --workflow pages.yml --limit 1   # success を確認
   curl -sI https://phlox.cc/ | head -1                            # HTTP/2 200
   ```
4. ブラウザで旧版が見える場合はファビコン等のキャッシュ。`Cmd+Shift+R` で強制再読込。サーバー実体は `curl` で確認する。

## 統合前検証と実機記録

必須条件と記録の正本は [merge-verification-gates.md](../specs/merge-verification-gates.md)。入口は`macos/scripts/verification-gate.py`の`quality`（自動検査）・`capture-build --evidence-root <証拠基準> ... -- <ビルドコマンド>`（実ビルドの記録）・`release --dmg <既存staplerと同じDMG> --zip <同じ工程の配布ZIP> --evidence-root <証拠基準> [--record <JSON>]`（main前照合）・読み取り専用の`review-input --base <比較元> [--target <対象、既定HEAD>]`（レビュー材料）。対応表・独立レビュー・実機結果はそれぞれ`release/verification-scenarios.json`・`release/verification-reviews.json`・`release/verification-records.json`に置き、`schemaVersion`を持たせる。実機結果の初期集合は空で、passedは作らない。同書の監査基準OIDは過去の静的確認であり、引数の静的照合は実装・全体検証成功を示さない。修正中コードとの照合状況は同書の状態欄を参照する。

1. 要件・対象コード・テスト・実機シナリオの対応を確認し、変更差分とシナリオ本文を別担当が独立レビューする。明示`decision`を保存し、対象差分の最新判定が`pass`の場合だけ受理する。`review-input`で材料を得てもレビュー済みにはならない。AIレビューも可能だが、人の承認・実機観測の証言としては記録しない。必須項目を削除・対象外化する判断や要件変更はユーザーへ戻す。
2. dev/verify/main反映前は、文書保守後の同じ隔離候補でmacOS全19パッケージを標準入口へ明示し、iOS lint/単体/build、指定13関数のfake E2Eを実行する。新パッケージ漏れ・親環境による対象/並行性の変更も検出する。0件、必須skip、未設定、環境不足は合格にしない。通常の対象外opt-in skipと指定ADR 0209のknown issueは成功件数と分け、未知known issueとfake必須13のskip/known issueは非0。個別ID・生ログ・結果JSONは`$GITFLOW_VERIFICATION_DIR`のcandidate外へ保存する。
3. verifyで実際に確認するMac/iOSビルドを固定し、端末・OS・実施者・時刻・シナリオ版/内容・成果物ハッシュ・実ビルド入力とソースOID・観測証拠を対応付ける。capture-buildのsettingsは呼び出し側が実測したshowBuildSettings JSONで、実機platform・版/build・署名設定等を照合するが、実ビルドコマンドとの完全な結合は機械保証しない。実機には状態/履歴/表示だけでなく、追加統一したUsageの表示設定/60秒更新（AC-8）と新規会話のworktree/開始地点/Claude-Codex再開（AC-9）も含める。iOSを今回配布しないことだけで既存実機要件を対象外にしない。
4. 実機結果はverifyから切った記録だけの作業ブランチへ保存し、共通ツールでverifyへ戻す。証拠は統合元リポジトリの`.verification/release-evidence/<版>/<buildID>/`へ継続保管し、消えるcandidate内へ置かない。main反映前に、既存release検査が確認する同じ実DMGを照合へ渡し、記録した配布成果物ハッシュとの一致を要求する。文書保守だけでOIDが変わっても元のsourceOIDを残し、入力manifest・有効設定・対象シナリオ内容・成果物/証拠と独立レビューにより再利用できる。文書追加/削除や意味を変えないリンク修正だけで全実機結果を失効させず、意味が変わった場合は作業ブランチへ戻して再レビューする。ソースOIDの後付け書換えや祖先関係だけで流用しない。
5. `passed / failed / not_run / stale / not_applicable`を区別し、未実施・古い記録・失敗を合格にしない。対象外には具体的根拠とユーザー判断が必要。記録・参照・ハッシュの整合性を確認できても、シナリオの意味の十分性や人の実施証言の真実性までは機械保証できない。

共通`gitflow-merge.sh`自体は変更しない。既存の品質・署名・配布物確認を残したプロジェクト入口を接続し、ローカルGit設定は実装検証後に親担当が設定する。ローカル設定の存在をサーバー側の保護や必須チェックの設定済みと取り違えない。

capture-buildとreleaseへ同じ`--evidence-root`を明示し、記録中の相対参照はそこから解決する。Macのcapture-buildには、同じ工程で新しく生成する実配布ZIPも`--zip`で渡す。main用releaseにも同じZIPを`--zip`で指定し、DMGとZIPの来歴、app内容、feedの版/build/URL/サイズと実ZIPの署名を照合する。署名検証はDMG内appの公開鍵を使う。appcastはビルド入力からだけ分け、変更の独立レビューを維持する。既存の署名・版・ノート・appcast・stapler検査はreleaseに先行させる。catalogはビルド入力から外し、対象AC行・手順・期待結果を別に照合する。記録したtoolchainは当時の来歴で、現在のXcode/SDK更新だけで同一成果物を失効させない。ただしrootの`SECURITY.md`・`THIRD_PARTY_NOTICES.md`等は依然入力に含むため、文書だけの修正でも再確認が必要になる保守的な限界がある。

最終ZIPは、appの公証チケットをstapleした後の、DMGへ格納したものと同じappから作る。共通`sign_and_notarize.sh`がapp公証提出用に作るZIPはstaple前なので、そのまま配布しない。`capture-build`へ渡す実コマンド内で、共通工程の完了後に`ditto -c -k --keepParent <staple済app> <最終配布ZIP>`を実行してから来歴を採取する。その最終ZIPをSparkleで署名してfeedへ記入する。保存済み1.14.0配布物ではstapleが追加した`Contents/CodeResources`がZIPに不足することを2026-10-27に確認したため、旧ZIPをこの検査の成功例にしない。

独立レビューの現在の判定は`release/verification-reviews.json`の最新記録で確認する（2026-10-25の記録はコード差分へのAIレビューのpassで、実機シナリオはnot_run）。全体検証の成否は最終候補での各実行の`result.json`・終了コード・原ログで確認し、本書では合格を主張しない。ControlServer初回期限超過は後の診断5回成功でも原因未特定として残す。macOS19パッケージのexit 0後にイベント解析で失敗した最初のqualityについては、イベント行のASCII LF区切りとPTY子プロセスへのイベント出力引数の除去をコードへ反映したが、修正後の全体成功は本書では確認していない。詳細と報告元の区別は[仕様の未解決記録](../specs/merge-verification-gates.md)を参照する。

実CLI依存検査、人操作/ACK待ち、XCUITestを自動検査から一括起動しない。XCUITestは実行禁止。シミュレーターでの描画・操作を実機確認へ読み替えず、記録だけ作成して実機済みにしない。旧`release/dev-to-main-checklist.html`は7月の範囲の過去資料で、保存済みチェックは現在の合格証拠ではない。

## macOS アプリをリリースする

前提: DMG のビルド・Developer ID 署名・notarytool 公証・stapler は `swift-release` スキル（`sign_and_notarize.sh`）で行う。公証済み DMG は `stapler validate` 成功かつ `spctl -a -t open` が `accepted, source=Notarized Developer ID` になること。

### DMG をビルドする（styled インストール画面つき）

`macos/` で次を実行する。**`DMG_BACKGROUND` / `DMG_DS_STORE` を必ず渡す**こと（省略すると背景・アイコン配置のない素の DMG になり、インストール画面が簡素化する回帰が起きる。1.0.1 で一度発生した）。`TEAM_ID` と署名名義は**ローカルにのみ持ち、リポジトリにコミットしない**:

```bash
cd macos
XCODEGEN=1 APP_NAME=Phlox SCHEME=Phlox PROJECT=Phlox.xcodeproj \
  TEAM_ID=<your-team-id> \
  IDENTITY="Developer ID Application: <name> (<your-team-id>)" \
  KEYCHAIN_PROFILE=AC_NOTARY \
  ENTITLEMENTS=App/Phlox.entitlements \
  DMG_BACKGROUND=release-assets/dmg/dmg-background.png \
  DMG_DS_STORE=release-assets/dmg/DS_Store \
  bash ~/.claude/skills/swift-release/scripts/sign_and_notarize.sh
```

- 生成物: `macos/build/Phlox.dmg`（人間向け・Release 添付用）／ `macos/build/Phlox.zip`（Sparkle 用。配布時に `Phlox-<version>.zip` へリネーム）。
- styled DMG の背景・レイアウト資産は `macos/release-assets/dmg/`（`dmg-background.png` と `DS_Store` テンプレート）。`.DS_Store` はボリューム名 `Phlox`・背景ファイル名・アイコン名（`Phlox.app` / `Applications`）に紐づくため、これらを変える場合はテンプレートを作り直す（詳細は同ディレクトリ `README.md`）。
- Sparkle 用 zip の EdDSA 署名は `sign_update`（初回は keychain のアクセス許可ダイアログで「常に許可」が必要）。

### シミュレーターの許可リストと XPC 署名を確認する

現行の正式版 Xcode を選択し、`xcodebuild -version` の build が `SimulatorPolicy.verified` の許可リストにあるか照合する。リポジトリのルートで次を実行し、照合失敗なら公開を止める。スクリプトは選択中の Xcode を検査するため、それが現行の正式版であることは別途確認する。

```sh
python3 macos/scripts/verify-simulator-allowlist.py
```

配布前に [互換性・実行記録の手順](simulator-compatibility-verification.md) を実施する。
Xcode build × iOS runtime の組を実行記録に残し、合格した組だけを `SimulatorPolicy.verified` に追加する。
表示だけ合格した組は `supportsInput: false` にし、入力を有効にしない。未確認の組を範囲指定で許可しない。
現行は Xcode 26.2（17C52）× iOS 26.2 の1組。日本語入力・四方向・実接続異常など既存記録で未検証の項目は配布前に確認し、合格を記録する。
Phloxの回転は「表示を回転」で手動指定する。Simulator.app側の回転に自動追従する検査とは区別し、指定した四方向ごとに描画と入力座標が一致するか確認する。

生成した配布用アプリにも次を実行する（公証・staple の後、DMG／Sparkle 公開の前）。

```sh
~/.agents/scripts/compact-test --full simulator-release-signing \
  bash macos/scripts/tests/test_simulator_bridge_signing.sh /絶対パス/Phlox.app
```

本体と XPC の bundle ID・build・版・Team ID、hardened runtime、専用エンタイトルメント、本体への非公開部品混入を検査する。
本体と XPC は `project.yml` の共通 build・版を使う。通信版が違う旧補助プロセスを一括停止せず、本体の再起動案内に従う。
凍結済み `test_signing_entitlements_variants.sh` は変更しない。署名検査、実端末記録、未検証の項目をリリース記録に添付する。

### 検査後に公開する

リリース時は **3 箇所**を更新する（[ADR 0089](../adr/0089-phlox-cc-served-from-monorepo-site.md) の移設により配信先が変わった点に注意）:

1. **初回ダウンロード用 DMG を `HMNZK/phlox` の Release に公開する**（これをしないと `phlox/releases/latest` が旧版に固定される）。`--notes` には下記「リリースノートを書く」で用意した本文を入れる:
   ```bash
   gh release create vX.Y.Z --repo HMNZK/phlox --target main \
     --title "Phlox X.Y.Z" --notes-file path/to/release-notes.md path/to/Phlox.dmg
   ```
2. **Sparkle 更新バイナリ（zip/delta）を `HMNZK/phlox-dist` の Release（tag `updates`）にアップロードする**（現行の更新配信基盤）。
3. **`site/appcast.xml`（＝phlox.cc が配信する正）に新バージョンの `<item>` を追記して `main` に push する**。旧 `phlox-dist/appcast.xml` はもう phlox.cc では配信されないので更新しても意味がない。`<item>` には `<description>`（リリースノート）を必ず含め、enclosure URL・`sparkle:version`・`sparkle:edSignature` を新バイナリに合わせる。push で Pages が自動デプロイ。

常駐実行方式へ移行した版の新規`<item>`には、更新後のGUIが接続できる実行プロトコルの範囲も記す。現在の実装は版1で、次を追加する。既に公開した旧方式のバイナリへ、この互換性情報を後付けしない。

```xml
<phloxRuntimeProtocolMin>1</phloxRuntimeProtocolMin>
<phloxRuntimeProtocolMax>1</phloxRuntimeProtocolMax>
```

新規更新候補は、この範囲が現在の実行プロトコルを含む場合にだけ受け入れる。情報なし、不正な範囲、非互換の候補は延期する。セッションの開始有無で判定を変えないため、ダウンロード中の新規開始で判定が変わる競合を避ける。初回導入前に既に準備済みだったSparkleの更新処理は、この判定の保証対象外。再開時にはSparkleが候補判定delegateを省略するため、過去に判定を通していないキャッシュまで保証したとは扱わない。

### リリースノートを書く（必須）

**すべてのリリースにリリースノートを付ける。** 同じ内容を次の 2 箇所へ載せる:

| 載せる場所 | 書式 | 読者が見る場所 |
|---|---|---|
| `site/appcast.xml` の `<item>` 内 `<description>` | HTML を `<![CDATA[ … ]]>` で包む。`xml:lang="en"` を先、`xml:lang="ja"` を後に置く | Sparkle の更新ダイアログ |
| `gh release create` の `--notes` / `--notes-file` | Markdown | GitHub Releases のページ |

- **`xml:lang="en"` を先頭に置く** — Sparkle は `preferredLocalizationsFromArray` の仕様で一致する言語が無ければ配列の先頭を選ぶ。先頭を en にすると未対応言語のフォールバックが英語になる。
- 見出しは `<h3>新機能</h3>`（en は `New`）と `<h3>修正</h3>`（en は `Fixed`）の 2 種を使い、該当する変更が無い区分は省く。
- 各項目は**ユーザーが体感する変化**を平易な言葉で 1〜2 文で書く。内部リファクタリング・テスト追加・コミットの羅列は載せない。
- 雛形は 1.3.1 の `<item>`（`git show a4514d1 -- site/appcast.xml`）をコピーして中身を差し替える。
- `<description>` が無い `<item>` を push しない — Sparkle の更新ダイアログが空欄になり、ユーザーが何が変わったか分からないまま更新することになる（1.3.1 で発生し、後追いで追記した）。

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

バージョン整合: `macos/project.yml` の共通設定 `settings.base` にある `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を更新し、appcast の `sparkle:shortVersionString` / `sparkle:version`、Release タグを一致させる。本体と XPC サービスはこの共通設定を使う。

## ロールバック

- **サイト**: `main` を前コミットへ戻して push（Pages が再デプロイ）、または直前の成功 run を `gh run rerun` する。
- **DMG ダウンロード**: 問題のある Release を `gh release delete vX.Y.Z --repo HMNZK/phlox` すると `releases/latest` が一つ前へ戻る。
- **自動更新**: `site/appcast.xml` から該当 `<item>` を除去して push すれば、そのバージョンは配信対象外になる。
