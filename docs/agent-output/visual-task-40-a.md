---
task: task-40
status: partial
---

# UI-03（task-40）PM 目視ゲート A — 隔離 Debug：エラー行と入力欄

製品コード・テスト・契約・台帳は未変更。成果は PNG・AX ログ・本報告。合否は PM が判定する。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke 未使用。送信・再試行・セッション作成なし。アプリ内の「文字を大きく／小さく」は未操作。Release Phlox（PID 61465）未接触。

PM 目視ゲートは PM が PNG を確認して判定する。

## 環境

- HEAD: `6976f2a`
- App: `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`
- ハーネス: `/tmp/phlox-t13-visual.SPfR9c/shoot-t40a.sh`（`ax-t2735.py` / `axclick.py` / `axscroll.py` / `agents-t2735.json`、データは `data-t33-v4` をコピーして visual-task-27-35-composer.md の復元失敗プレースホルダ手順）
- 起動 env: `PHLOX_DATA_DIR` / `PHLOX_DEFAULTS_SUITE` / `PHLOX_AGENTS_JSON` / `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`
- 起動引数キー（実コード）: `ThemeStore.themeKey` = `phlox.theme`、`ChatFontSettings.scaleKey` = `phlox.chat.fontScale`（`--args -<key> <value>`、NSArgumentDomain）
- 共通 args: `-AppleLanguages "(ja)" -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme <theme> -phlox.chat.fontScale <scale>`

## 隔離

| 時点 | `com.phlox.Phlox` md5 | Release `phlox.theme` | Release `phlox.chat.fontScale` | Release PID |
|---|---|---|---|---|
| 撮影前 | `abe1760b9e29c4afc58e8860ac27845f` | dracula | 1 | 61465 残存 |
| 各 combo 終了 / 最終 | 同左（不変） | dracula | 1 | 61465 残存 |

Debug は各 combo で `kill -TERM` 後 pgrep 不在。suite は `defaults delete`（終了後の `defaults domains` 残件は delete 時 Domain not found）。

## PID と子プロセス

起動直後の `pgrep -P <PID>` は 6 回とも 1 件。コマンドはいずれもモデルカタログ照会で、チャット送信ではない。選択後・終了前は 0 件。

| テーマ | 倍率 | Debug PID | 起動直後 `pgrep -P` | 選択後 |
|---|---|---|---|---|
| phlox-light | 1.0 | 57706 | 57715 `/Users/ryosuke/.local/bin/claude --bare -p /model --output-format json` | (none) |
| phlox-light | 2.0 | 59591 | 59594 同コマンド | (none) |
| phlox-light | 0.8 | 72883 | 72886 同コマンド（約 4s で消滅） | (none) |
| dracula | 1.0 | 76862 | 76878 同コマンド | (none) |
| dracula | 2.0 | 80173 | 80176 同コマンド（約 4s で消滅） | (none) |
| dracula | 0.8 | 83505 | 83508 同コマンド | (none) |

子孫プロセス列挙原文（phlox-light 1.0 起動直後）:

```
=== descendants pgrep -P 57706 when=launch ===
pgrep -P pids:
57715
child_count=1
pgrep -P ps:
  PID  PPID COMMAND
57715 57706 /Users/ryosuke/.local/bin/claude --bare -p /model --output-format json
```

選択後原文:

```
=== descendants pgrep -P 57706 when=after-select ===
(none)
child_count=0
```

## PNG 一覧

ウィンドウ実枠は論理 1206×790（`screencapture -l` 2412×1580）。`set size {1440, 800}` は枠に反映されなかった。チャット列 crop は composer 左端付近、1522×1580。

| パス | 対象 | 寸法（px） | テーマ | 倍率 | PID |
|---|---|---|---|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-1.0.png` | 窓全体 | 2412x1580 | phlox-light | 1.0 | 57706 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-1.0-chat.png` | チャット列 | 1522x1580 | phlox-light | 1.0 | 57706 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-1.0-window-scrolled.png` | 窓全体（axscroll 後） | 2412x1580 | phlox-light | 1.0 | 57706 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-1.0-chat-scrolled.png` | チャット列（axscroll 後） | 1522x1580 | phlox-light | 1.0 | 57706 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-2.0.png` | 窓全体 | 2412x1580 | phlox-light | 2.0 | 59591 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-2.0-chat.png` | チャット列 | 1522x1580 | phlox-light | 2.0 | 59591 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-2.0-window-scrolled.png` | 窓全体（axscroll 後） | 2412x1580 | phlox-light | 2.0 | 59591 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-2.0-chat-scrolled.png` | チャット列（axscroll 後） | 1522x1580 | phlox-light | 2.0 | 59591 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-0.8.png` | 窓全体 | 2412x1580 | phlox-light | 0.8 | 72883 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-0.8-chat.png` | チャット列 | 1522x1580 | phlox-light | 0.8 | 72883 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-0.8-window-scrolled.png` | 窓全体（axscroll 後） | 2412x1580 | phlox-light | 0.8 | 72883 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/phlox-light-0.8-chat-scrolled.png` | チャット列（axscroll 後） | 1522x1580 | phlox-light | 0.8 | 72883 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-1.0.png` | 窓全体 | 2412x1580 | dracula | 1.0 | 76862 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-1.0-chat.png` | チャット列 | 1522x1580 | dracula | 1.0 | 76862 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-1.0-window-scrolled.png` | 窓全体（axscroll 後） | 2412x1580 | dracula | 1.0 | 76862 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-1.0-chat-scrolled.png` | チャット列（axscroll 後） | 1522x1580 | dracula | 1.0 | 76862 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-2.0.png` | 窓全体 | 2412x1580 | dracula | 2.0 | 80173 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-2.0-chat.png` | チャット列 | 1522x1580 | dracula | 2.0 | 80173 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-2.0-window-scrolled.png` | 窓全体（axscroll 後） | 2412x1580 | dracula | 2.0 | 80173 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-2.0-chat-scrolled.png` | チャット列（axscroll 後） | 1522x1580 | dracula | 2.0 | 80173 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-0.8.png` | 窓全体 | 2412x1580 | dracula | 0.8 | 83505 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-0.8-chat.png` | チャット列 | 1522x1580 | dracula | 0.8 | 83505 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-0.8-window-scrolled.png` | 窓全体（axscroll 後） | 2412x1580 | dracula | 0.8 | 83505 |
| `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/dracula-0.8-chat-scrolled.png` | チャット列（axscroll 後） | 1522x1580 | dracula | 0.8 | 83505 |

AX ログ: `/tmp/phlox-t13-visual.SPfR9c/t40-gateA/<theme>-<scale>-ax.log` / `-obs.log`

## AX 原文（エラー見出し・本文・時刻・入力欄）

プレースホルダ本文は 6 回とも `chat restore failed: customBinaryNotFound("ui-chat-probe")`。入力欄 ident=`ChatComposer.input`、AXValue 空（プレースホルダは画像上「Ask Phlox anything...」）。composer frame は全倍率 `pos=677.5, 890.0 size=744.0, 36.0`。

### phlox-light 1.0

```
HEADING STATIC role=AXStaticText title='' desc='' value='Error' ident= help= focused=None selected=None pos=678.5, 252.0 size=44.5, 13.0
BODY STATIC role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 269.0 size=414.0, 19.0
TIME STATIC role=AXStaticText title='' desc='' value='13:42' ident= help= focused=None selected=None pos=677.5, 292.0 size=29.0, 13.0
COMPOSER COMPOSER role=AXScrollArea title='' desc='' value='' ident=ChatComposer.input help= focused=False selected=None pos=677.5, 890.0 size=744.0, 36.0
OVERLAP_CHECK body_bottom=288.0 composer_top=890.0 gap=602.0 result=NO_OVERLAP
DISTINCT_Y heading_y=252.0 body_y=269.0 time_y=292.0 heading_h=13.0 body_h=19.0 time_h=13.0
BODY_BOX wrap=SINGLE_LINE_OR_SHORT
```

### phlox-light 2.0

```
HEADING STATIC role=AXStaticText title='' desc='' value='Error' ident= help= focused=None selected=None pos=679.5, 252.0 size=75.5, 24.0
BODY STATIC role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 280.0 size=677.5, 74.0
TIME STATIC role=AXStaticText title='' desc='' value='13:43' ident= help= focused=None selected=None pos=677.5, 358.0 size=53.5, 24.0
COMPOSER COMPOSER role=AXScrollArea title='' desc='' value='' ident=ChatComposer.input help= focused=False selected=None pos=677.5, 890.0 size=744.0, 36.0
OVERLAP_CHECK body_bottom=354.0 composer_top=890.0 gap=536.0 result=NO_OVERLAP
DISTINCT_Y heading_y=252.0 body_y=280.0 time_y=358.0 heading_h=24.0 body_h=74.0 time_h=24.0
BODY_BOX wrap=WRAP
```

### phlox-light 0.8

```
HEADING STATIC role=AXStaticText title='' desc='' value='Error' ident= help= focused=None selected=None pos=678.5, 252.0 size=38.0, 10.0
BODY STATIC role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 266.0 size=342.5, 15.0
TIME STATIC role=AXStaticText title='' desc='' value='13:46' ident= help= focused=None selected=None pos=677.5, 285.0 size=24.0, 10.0
COMPOSER COMPOSER role=AXScrollArea title='' desc='' value='' ident=ChatComposer.input help= focused=False selected=None pos=677.5, 890.0 size=744.0, 36.0
OVERLAP_CHECK body_bottom=281.0 composer_top=890.0 gap=609.0 result=NO_OVERLAP
BODY_BOX wrap=SINGLE_LINE_OR_SHORT
```

### dracula 1.0

```
HEADING STATIC role=AXStaticText title='' desc='' value='Error' ident= help= focused=None selected=None pos=678.5, 252.0 size=44.5, 13.0
BODY STATIC role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 269.0 size=414.0, 19.0
TIME STATIC role=AXStaticText title='' desc='' value='13:46' ident= help= focused=None selected=None pos=677.5, 292.0 size=29.0, 13.0
COMPOSER COMPOSER role=AXScrollArea title='' desc='' value='' ident=ChatComposer.input help= focused=False selected=None pos=677.5, 890.0 size=744.0, 36.0
OVERLAP_CHECK body_bottom=288.0 composer_top=890.0 gap=602.0 result=NO_OVERLAP
BODY_BOX wrap=SINGLE_LINE_OR_SHORT
```

### dracula 2.0

```
HEADING STATIC role=AXStaticText title='' desc='' value='Error' ident= help= focused=None selected=None pos=679.5, 252.0 size=75.5, 24.0
BODY STATIC role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 280.0 size=677.5, 74.0
TIME STATIC role=AXStaticText title='' desc='' value='13:47' ident= help= focused=None selected=None pos=677.5, 358.0 size=53.5, 24.0
COMPOSER COMPOSER role=AXScrollArea title='' desc='' value='' ident=ChatComposer.input help= focused=False selected=None pos=677.5, 890.0 size=744.0, 36.0
OVERLAP_CHECK body_bottom=354.0 composer_top=890.0 gap=536.0 result=NO_OVERLAP
BODY_BOX wrap=WRAP
```

### dracula 0.8

```
HEADING STATIC role=AXStaticText title='' desc='' value='Error' ident= help= focused=None selected=None pos=678.5, 252.0 size=38.0, 10.0
BODY STATIC role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 266.0 size=342.5, 15.0
TIME STATIC role=AXStaticText title='' desc='' value='13:47' ident= help= focused=None selected=None pos=677.5, 285.0 size=24.0, 10.0
COMPOSER COMPOSER role=AXScrollArea title='' desc='' value='' ident=ChatComposer.input help= focused=False selected=None pos=677.5, 890.0 size=744.0, 36.0
OVERLAP_CHECK body_bottom=281.0 composer_top=890.0 gap=609.0 result=NO_OVERLAP
BODY_BOX wrap=SINGLE_LINE_OR_SHORT
```

## 確認項目の記録（AX と PNG。合否は書かない）

- 折り返し: 倍率 1.0 / 0.8 は本文 AX 高さ 19 / 15（1 行相当）。倍率 2.0 は高さ 74、PNG で `customBinaryNotFound("ui-chat-` のあと改行し `probe")` が次行。
- 時刻との区別: AX は見出し・本文・時刻が別 Y。PNG では見出し「Error」が赤、時刻は小さめの二次色。倍率 2.0 では時刻（13:43 / 13:47）が履歴スクラバーの灰色チップ「workspace」と横に重なり、時刻の左が欠ける。
- 入力欄への重なり: AX `NO_OVERLAP`（gap 536〜609pt）。PNG でもエラーカードと「Ask Phlox anything...」の間に空面。入力欄の文字サイズは倍率を変えても AX 36pt 高のまま（ChatComposer は本ゲートの文字正本対象外）。
- 末尾スクロール: エラー 1 件のみでカードと入力欄は初期から同時に見える。`axscroll.py` dy=-480 をチャット列中央へ送った。スクロール前後 PNG は実質同一。

本ゲートの画像は日本語回答・箇条書き・処理カードの目視成功には数えない。

## できなかった手順と理由

- 起動直後の子プロセス 0 件: 6 回とも到達せず。App が起動時に `claude --bare -p /model --output-format json` を 1 件 spawn する（モデルカタログ。送信・セッション作成ではない）。数秒で消え、選択後は 0 件。製品コードは変えていないため抑制できなかった。
- ウィンドウを 1440×800 にする System Events `set size`: 実枠は 1206×790 のまま（task-27/35 と同型）。
- 入力欄プレースホルダの AXValue: 空。文言は PNG のみ。
- 末尾へ「スクロールして初めて見える」状態: プレースホルダが 1 行のため再現不能。axscroll は実行した。
- アプリ内「文字を大きく／小さく」: 契約注 10 どおり未操作。倍率は起動引数のみ。
- 初回 phlox-light 0.8: カタログ CLI 検出後に撮影スクリプトを止めたため未完。同一手順で PID 72883 を撮り直した。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定（2026-09-13、Claude=PM が PNG を目視）

閲覧: `phlox-light-1.0-chat.png`・`phlox-light-2.0-chat.png`・`phlox-light-0.8-chat.png`・`dracula-1.0-chat.png`（各 1522×1580px）。

- エラー見出し「Error」は赤の補助サイズ、本文は本文サイズ、時刻は小さい二次色で 3 段が読順どおりに区別できる（1.0／0.8／dracula）。倍率 2.0 で本文が `ui-chat-` の後で折り返し、欠け・重なりなし。
- 入力欄との重なりなし。末尾スクロール到達（axscroll 後の PNG も同一内容で末尾）。
- **ゲート A: pass**（エラー行と入力欄の範囲）。契約どおり、この画像を日本語回答・箇条書き・処理カードの目視成功には数えない。
- 判定外の観測（task-40 の allowed_paths 外）: 倍率 2.0 で履歴スクラバーのチップ「workspace」（左端で切れて `orkspace` と表示）がエラーカードの時刻行と重なる。チップは全倍率で同じ位置（y≈380px）に固定表示されており、カードが高くなる 2.0 で重なる。task-40 以前から同じ挙動かは未検証。UX-05（task-46/47）または別項目で扱う候補として decision-log に記録。
- 課金確認: 起動時の `claude --bare -p /model --output-format json` は Phlox のモデルカタログ照会。生成された transcript（`~/.claude/projects/-private-tmp-phlox-t13-visual-SPfR9c-*`）を PM が開き、`/model` ローカルコマンドの記録のみで assistant 応答・usage が無いことを確認（課金なし）。当該 transcript ディレクトリは PM が削除した。

=== REPORT COMPLETE ===
