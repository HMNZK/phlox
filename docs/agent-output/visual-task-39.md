---
status: partial
task: task-39
date: 2026-09-13
pid: 38891
suite: com.phlox.t39.v5.38833
---

# task-39（BUG-01 修正後）実画面再現の再実施

製品コード・テスト・契約・台帳は未変更。隔離 Debug のみ操作。System Events は `first process whose unix id is 38891`。key code / keystroke 未使用。操作は AX と axclick.py のみ。課金セッションは未作成（custom `sh -c` の Sunflower / Bluebell のみ）。Release Phlox（PID 61465）には未接触。トレース（`[BUG01]` / `Bug01Trace`）は入っていない。

PM 目視ゲートは PM が PNG を確認して判定する。

## ビルド結果

- コマンド: `cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t39b.log 2>&1`
- ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t39b.log`
- 末尾: `** BUILD SUCCEEDED **` / EXIT:0
- 成果物: `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`
- 作業ツリー HEAD: `277fd0d`（台帳）。製品修正コミット: `2e27c8b`
- スパイク worktree（`bug01-repro`）のビルドは未使用

## PID / 隔離

| 項目 | 値 |
|---|---|
| 本流実行 | v5（A/B/C/D 完走・指定 PNG） |
| Debug PID | 38891（自プロセスのみ AX / axclick / TERM） |
| suite | `com.phlox.t39.v5.38833`（終了後 `defaults delete`） |
| PHLOX_DATA_DIR | `/tmp/phlox-t13-visual.SPfR9c/data-t39-v5` |
| PHLOX_AGENTS_JSON | `/tmp/phlox-t13-visual.SPfR9c/agents-t39.json`（Sunflower / Bluebell のみ。実 CLI 未 click） |
| ハーネス | `/tmp/phlox-t13-visual.SPfR9c/shoot-t39.sh` |
| 起動 | `open -n` + `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`、`-AppleLanguages "(ja)"` `-AppleLocale ja` `-ApplePersistenceIgnoreState YES` |
| Release PID 61465 | 起動中のまま。`com.phlox.Phlox` md5 `abe1760b9e29c4afc58e8860ac27845f` 不変 |

`set size of window 1 to {1440, 800}` のあと Quartz 実寸は `306, 192, 1206, 790`（既存ハーネスと同じ）。

終了: PID 38891 に `kill -TERM`、Debug バイナリ `pgrep` 不在、suite 削除、Release 61465 残存。`release_md5_unchanged=yes`。

先行 v1–v3 はメニュー項目 click が System Events の同名プロセス誤解決（`window "Phlox (Debug)" of application process "Phlox"` / -1728）でセッション未作成。v4 はセッション作成・モード切替・C の PNG は取れたが、見出し/サイドバーの座標取得が長文 AppleScript で失敗。本報告の SHOT / AX 原文は v5。

## セッション対応

custom agent 2 本（`printf '…_OUTPUT\n'; seq 1 30; exec cat`）。花名は生成値。

| 役割 | agent id / 表示名 | 花名 | session id |
|---|---|---|---|
| 第 1（Sunflower 相当） | `bug01-sunflower` / Sunflower | **Daisy** | `FF92AC9B-FD22-427B-A004-9004E8082963` |
| 第 2（Bluebell 相当） | `bug01-bluebell` / Bluebell | **Lavender** | `B4525AB1-17D7-4F60-BD7C-762CC5EBAE39` |

作成はプロジェクト行の `menu button "追加"` + 同一 osascript 内で `click menu item "Sunflower"` / `"Bluebell"`（Claude/Codex/Cursor/新しいチャットは未 click）。

選択の AX 信号: 行の `selected` は常に false。選ばれている行の表示名が **「現在の会話」** に置き換わる。PNG のサイドバーハイライトと開始時刻（Daisy=`04:51:46` / Lavender=`04:51:55`）で裏取り。

## 再現 A/B/C/D 結果表

操作の目視根拠は PNG。AX 列挙は描画の代替にしない。

| 再現 | 操作 | 選択 | 表示モード | ターミナルに出力が見えるか | PNG |
|---|---|---|---|---|---|
| 事前 | 2 本作成後、サイドバー Daisy を axclick.py | Lavender→**Daisy** | single | **見える**（SUNFLOWER_OUTPUT 1–30）。作成直後の Lavender は `t39-single-s2-created.png` で BLUEBELL 1–30 | `/tmp/phlox-t13-visual.SPfR9c/t39-single-before.png` |
| **A** | グリッド AXPress → タイル見出し「Lavender」に `AXPress` → 単一 AXPress | **Daisy のまま**（行は `現在の会話, Lavender` のまま。AXPress は実行結果文字列あり） | grid→single | グリッドは両タイル出力あり。**単一は SUNFLOWER 1–30 が見える** | `t39-a-grid.png` / `t39-a-single.png` |
| **B** | グリッドで Lavender 見出しを axclick.py（1195.0, 251.0、遮蔽確認付き `clicked`）→ 単一 | Daisy→**Lavender**（行が `Daisy, 現在の会話` に変化。PNG で Lavender ハイライト） | grid→single | グリッドは両タイル出力あり。**単一は BLUEBELL 1–30 が見える** | `t39-b-grid.png` / `t39-b-single.png` |
| **C** | 見出し操作なしで grid→single を 3 往復（Lavender のまま） | **Lavender のまま** | 3 往復 | グリッドは両タイル出力あり（`t39-c-grid-3.png`）。**単一は 3 回とも BLUEBELL 1–30 が見える** | `t39-c-single-1.png` / `-2.png` / `-3.png` / `t39-c-grid-3.png` |
| **D** | 単一でサイドバー Daisy → Lavender を axclick.py | Daisy（SUNFLOWER）↔ Lavender（BLUEBELL） | single | **両方とも出力が見える**（1–30） | `t39-d-switch-1.png` / `t39-d-switch-2.png` |

モードボタン: `selected[単体表示]=true` / `selected[グリッド表示]=true` が切替と一致。タイル見出し AX 座標（グリッド）: Daisy `700,241 size=44×20`、Lavender `1158,241 size=74×20`。

## 修正前（investigation-bug-01-runtime.md）との対比

修正前（spike PID 80633、Camellia / Gardenia、トレースあり）は、A（選択不変）・B（Gardenia に選択成功）・C（3 往復）のいずれも **grid→single のたびに単一が空白**。グリッドには両タイルの 1–30 が残った。データ消失ではなかった。

| 再現 | 修正前 | 本再実施（修正後・トレースなし） |
|---|---|---|
| A | 単一 **空白**。選択は Camellia のまま | 単一に **SUNFLOWER 1–30**。選択は Daisy のまま |
| B | 選択は Gardenia に成功。単一 **空白** | 選択は Lavender に成功。単一に **BLUEBELL 1–30** |
| C | 単一 **3 回とも空白**。グリッドは出力あり | 単一 **3 回とも BLUEBELL 1–30**。グリッドも両タイル出力あり |
| 復帰 | 別セッションをマウスで選ぶと出力が戻る | D で Daisy / Lavender を切替えて双方の出力が表示される |

タイル見出しに AX 選択経路が弱いこと（修正前: actions=`AXShowMenu` のみ。本再実施: `AXPress` はエラーにならず実行結果は返るが、選択は変わらない）は修正前と同じ。空白そのものの因果ではない。

## できなかった手順と理由

- v1–v3: メニューを開いたあとの別 osascript が `window "Phlox (Debug)" of application process "Phlox"` に誤解決し（Release と同名プロセス並存）、セッションが作れなかった。同一 osascript 内で `menu button "追加"` → `menu item` まで完結させると v4 以降で作成できた。
- 長文 AppleScript（`dump-t39.applescript` で window 参照を変数に置く / `name of window` を読む）は同じ -1728 で statics / modes / 見出し座標が取れない。v5 は一行 `get value/position/size of every … of window 1` に切り替えた。
- 行の AX `selected` は常に false。選択は「現在の会話」への改名と PNG で判定した。
- 単一面のターミナル AX 子は内容を返さない（statics は `Projects` と開始時刻のみ）。出力の有無は PNG。
- `set size of window 1 to {1440, 800}` は Quartz 実寸 1206×790 に留まった。
- スパイクの実行時トレースは本ビルドに無い（契約どおり）。所有権の後着 attach ログは取っていない。

PM 目視ゲートは PM が PNG を確認して判定する。

=== REPORT COMPLETE ===
