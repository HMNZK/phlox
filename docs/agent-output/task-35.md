---
task: task-35
status: completed
---
## 詰まった / 完了できなかった点

差し戻し 1 回目の対象（選択チェック付き行でも用途名を 1 行表示）は実装・隔離 Debug ビルド・Dracula 選択の設定ウィンドウ撮影まで完了した。ブロッカーはない。

## できた風だが実は未完（最重要）

- 契約の PM 追記どおり、入力欄の実画面比較は未達のまま。今回の撮影は設定一覧の用途名折り返し確認であり、適用後チャット入力欄との比較合格には使えない。
- AX dump（`dump-ax.applescript` の labels）では `アプリ外観` / `ターミナル配色` が ABSENT。見本側は `accessibilityHidden`、行の AX ラベルはテーマ名。視覚上の用途名は PNG で確認したが、VoiceOver が用途名を独立に読むかは未測定。
- `PHLOX_DEFAULTS_SUITE=com.phlox.t35.r1.45805` を渡しても `phlox.theme` は suite ではなく `com.phlox.Phlox.debug` に書かれた（launch 時 phlox → Dracula 選択時 dracula → 終了時 phlox へ戻し）。契約が禁止する「suite 指定だけで AppStorage 隔離」は仮定していない。Release `com.phlox.Phlox` は不変。

## 置いた前提・仮定

- 差し戻し指示どおり、`Text(model.appLabel)` と `Text(model.terminalLabel)` に `.lineLimit(1)` と `.fixedSize(horizontal: true, vertical: false)` を付け、見本列 HStack に `.layoutPriority(1)` を置いた。テーマ名・チェック・見本寸法・配色導出は変えていない。
- 撮影は既存 `/tmp/phlox-t13-visual.SPfR9c/shoot-t35.sh` を `r1` 引数で流用。key code なし、自 PID への AX のみ、Release PID 61465 非接触。GitHub Light クリックと Phlox 復元はスクリプト既存手順のまま。
- 1 行表示の判定は `t35-r1-settings-dracula.png` の Dracula 行（チェック付き）の目視。測色はしていない。

## 契約からの逸脱

なし。変更は `macos/App/SettingsView.swift` の 5 行追加のみ（allowed_paths 内）。テスト・配線 rb・契約・台帳・`ThemePreviewModel.swift` は未変更。

## App ビルド結果と撮影（PNG パス・隔離確認）

- 検証: `TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb` → `task35-wiring: OK`。`(cd macos/Packages/DesignSystem && swift test)` → 143 tests / 28 suites passed。`git diff --check` 空。いずれも exit 0。
- ビルド: `xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build` → `** BUILD SUCCEEDED **`（ログ `/tmp/phlox-t13-visual.SPfR9c/build-t35c.log`）。
- 必須 PNG: `/tmp/phlox-t13-visual.SPfR9c/t35-r1-settings-dracula.png`（exit 0）。ウィンドウ `“Phlox (Debug)”設定` wid=43246 bounds=642,172 520×672。Debug PID=46010。Dracula 行はチェック付きで「アプリ外観」「ターミナル配色」とも 1 行（v7 の Dracula 行だけ 2 行折り返しは解消）。
- 隔離: Debug バイナリ `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`。専用 data `data-t35-r1`、suite `com.phlox.t35.r1.45805`（終了時 `defaults delete`、ドメイン不在を確認）。自 PID 46010 へ TERM、terminated。Release PID 61465 生存。`com.phlox.Phlox` md5 は before/after-dracula/after-kill とも `abe1760b9e29c4afc58e8860ac27845f`（theme=dracula のまま）。

## レビュー重点（PM 用）

- `t35-r1-settings-dracula.png` の Dracula 行で「ターミナル配色」が 1 行か（v7 差し戻し点）。他候補行とのラベル高さ比較。
- チェック出現で見本・色帯が欠けていないか。用途名が省略記号になっていないか（`fixedSize` は折り返し拒否であり省略保証ではない）。
- 配線検査はラベル修飾子を見ていない。機械 green を 1 行表示の証拠にしないこと。
=== REPORT COMPLETE ===
