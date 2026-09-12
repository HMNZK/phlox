v6 の深い AX 走査は時間切れで止まりました。テーマ切替の完走は後続の v7（PID 30170）で済んでおり、報告は `docs/agent-output/visual-task-35.md` にあります。隔離 Debug は終了済みで、Release（PID 61465）はそのまま残っています。
��（チャット composer）の実画面比較は課金なし表示経路が無いため未実施。

PM 目視ゲートは PM が PNG を確認して判定する。

## ビルド

- コマンド: `cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t35b.log 2>&1`
- ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t35b.log`
- 末尾: `** BUILD SUCCEEDED **`

## PID / suite（本手順の完走は v7）

| 実行 | Debug PID | suite | 備考 |
|---|---|---|---|
| v7（テーマ click・SHOT 完走） | 30170 | `com.phlox.t35.v7.30061` | AX click index=3/9/1。Release 未変化 |
| v6（深い AX 原文） | 26227 | `com.phlox.t35.v6.26109` | テーマ行 path 1.4.2.1–10 を取得。走査が長く TERM |
| v1–v5 | （失敗・途中） | `com.phlox.t35.vN.$$` | 予約語 / プロセス名衝突 / ApplicationServices 不在。Release 未変化 |

起動: `-AppleLanguages "(ja)"` `-AppleLocale ja` `-phlox.appLanguage ja`。**`-phlox.theme` は未付与**。データは `$B/data-t33-v4` を `$B/data-t35-v7` へコピー。`PHLOX_AGENTS_JSON=$B/agents-t30.json`。

`set size of window 1 to {1440, 800}` のあと Quartz メイン: `X=306 Y=192 Width=1206 Height=790`（論理 pt）、name=`Phlox (Debug)`。設定窓: `X=642 Y=172 Width=520 Height=672`、name=`“Phlox (Debug)”設定`。

終了: 自 PID のみ `kill -TERM`。Debug バイナリの pgrep 不在。suite は `defaults delete`。Release 61465 `/Applications/Phlox.app/Contents/MacOS/Phlox` は残存。

## 隔離確認

列挙: `defaults domains | tr ',' '\n' | grep -i phlox` → 約 80650 件（pane-probe / updater.probe 等が大半）。md5 比較対象は次の3件。

| 時点 | `com.phlox.Phlox` md5 | `phlox.theme` | `com.phlox.Phlox.debug` md5 | debug `phlox.theme` | suite `phlox.theme` |
|---|---|---|---|---|---|
| before | `abe1760b9e29c4afc58e8860ac27845f` | dracula | `f831318354a5115a893c738abc151760` | tokyo-night | (absent) / Domain does not exist |
| after-launch | 同左（不変） | dracula | `11b8738d82f73bbe8ab6424d66452a3c` | tokyo-night | (absent) ※paneLayout 等のみ |
| after-dracula | 同左（不変） | dracula | `8e31c7ea1e554d09e1168f67a3b598d8` | **dracula** | (absent) |
| after-github-light | 同左（不変） | dracula | `6ee9d77ae500ac61d7574c1911e93e1a` | **github-light** | (absent) |
| after-restored | 同左（不変） | dracula | `3d1e29b5bec56f13bcf641374572b9b3` | **phlox** | (absent) |
| after-kill | 同左（不変） | dracula | 同上 | phlox | Domain does not exist |

- Release が使う domain は `com.phlox.Phlox`。観測中の export ファイル md5 は全ステップ `abe1760b9e29c4afc58e8860ac27845f`。`phlox.theme=dracula` のまま。
- テーマ書き込み先は専用 suite ではなく **Debug 標準 domain `com.phlox.Phlox.debug`**（`@AppStorage(ThemeStore.themeKey)` が suite を使わない）。suite には `phlox.grid.paneLayout` と `phlox.panelDrawer.width.migratedTo560` のみ。
- Debug 起動時の既定は、未付与の `-phlox.theme` ではなく既存値 **tokyo-night**。

## AX 原文

### 設定窓 depth 2（v7、`window idx=1`）

```
window idx=1 name=“Phlox (Debug)”設定
n1=5
D1[1] role=AXGroup roleDesc=グループ value=missing value title=missing value desc=グループ
  D2[1.1] role=AXImage roleDesc=イメージ value=missing value title=missing value desc=イメージ
  D2[1.2] role=AXStaticText roleDesc=テキスト value=Phlox (Debug) title=missing value desc=テキスト
  D2[1.3] role=AXStaticText roleDesc=テキスト value=設定 title=missing value desc=テキスト
  D2[1.4] role=AXScrollArea roleDesc=スクロール領域 value=missing value title=missing value desc=スクロール領域
D1[2] role=AXButton roleDesc=閉じるボタン value=missing value title=missing value desc=閉じるボタン
D1[3] role=AXButton roleDesc=拡大/縮小ボタン value=missing value title=missing value desc=拡大/縮小ボタン
  D2[3.1] role=AXGroup roleDesc=グループ value=missing value title=missing value desc=グループ
D1[4] role=AXButton roleDesc=しまうボタン value=missing value title=missing value desc=しまうボタン
D1[5] role=AXStaticText roleDesc=テキスト value=“Phlox (Debug)”設定 title=missing value desc=テキスト
```

SCROLL（v7 labels）: `AXScrollArea pos=642, 268 size=520, 576`

### テーマ行（v6 深い走査。初期スクロール位置、Y が負＝画面上端より上）

```
NODE path=1.4.2 role=AXGroup desc=グループ ... pos=662-1130 size=4801229
NODE path=1.4.2.1 role=AXButton desc=ボタン ... pos=672-1120 size=460102
NODE path=1.4.2.2 role=AXButton desc=ボタン ... pos=672-997 size=460102
NODE path=1.4.2.3 role=AXButton desc=ボタン ... pos=672-874 size=460102
NODE path=1.4.2.4 role=AXButton desc=ボタン ... pos=672-751 size=460102
NODE path=1.4.2.5 role=AXButton desc=ボタン ... pos=672-628 size=460102
NODE path=1.4.2.6 role=AXButton desc=ボタン ... pos=672-505 size=460102
NODE path=1.4.2.7 role=AXButton desc=ボタン ... pos=672-382 size=460102
NODE path=1.4.2.8 role=AXButton desc=ボタン ... pos=672-259 size=460102
NODE path=1.4.2.9 role=AXButton desc=ボタン ... pos=672-136 size=460102
NODE path=1.4.2.10 role=AXButton desc=ボタン ... pos=672-13 size=460102
```

10 行。`desc=ボタン`。title/value は missing。子は depth 5 まで未出現。ThemeStore.all 順で index 1=Phlox … 3=Dracula … 9=GitHub Light。v7 の click はこの index を使用。

### 見本ラベル 5 種（AX）

| 文言 | AX | PNG |
|---|---|---|
| アプリ外観 | ABSENT | 各テーマ行に描画 |
| ターミナル配色 | ABSENT | 各テーマ行に描画 |
| 本文の見本 | ABSENT | 見本カード内に描画 |
| 現在の会話 | ABSENT（設定窓。メインサイドバーの行値には PRESENT） | 見本カード内に描画 |
| メッセージを入力 | ABSENT | 見本カード内に描画 |

見出し「外観」は PNG にある。AX Heading の value は missing。

### メインサイドバー行値（v7）

```
UI検証A, 現在の会話, #976761, 空のプロジェクトB, missing value
```

Dracula 選択後も同文。単体表示のまま。

### 操作ログ（v7）

```
settings-click-result=clicked-help
scroll-idx35=0
press-result=clicked-ax:index=3 needle=Dracula
press-result=clicked-ax:index=9 needle=GitHub Light
press-result=clicked-ax:index=1 needle=Phlox
close=clicked-subrole
```

全文: `/tmp/phlox-t13-visual.SPfR9c/t35-v7-obs.log` `/tmp/phlox-t13-visual.SPfR9c/t35-v7-ax.log` `/tmp/phlox-t13-visual.SPfR9c/t35-v6-obs.log`

## PNG 一覧

パス先頭: `/tmp/phlox-t13-visual.SPfR9c/`。論理寸法は Quartz。画素は Retina 2x。

| ファイル | テーマ（prefs / 画面） | ウィンドウ寸法（論理 pt） | PID |
|---|---|---|---|
| `t35-v7-main-default.png` | debug=tokyo-night。暗色メイン。現在の会話「文字の読みやすさ」に左マーカー | メイン 1206×790 @306,192 | 30170 |
| `t35-v7-settings-default.png` | 開いた直後・スクロールせず。外観は画面外。アイコン節～最大発言数 | 設定 520×672 @642,172 | 30170 |
| `t35-v7-settings-scrolled-top.png` | scroll bar value=0 のあと。外観。チェックは Tokyo Night | 設定 520×672 | 30170 |
| `t35-v7-settings-list.png` | scrolled-top からの一覧向け切り出し（ヘッダー残） | 設定 scroll AX 520×576 @642,268 | 30170 |
| `t35-v7-settings-dracula.png` | debug=dracula。チェックは Dracula 行 | 設定 520×672 | 30170 |
| `t35-v7-main-dracula.png` | debug=dracula。暗色。左マーカー＋「文字の読みやすさ」。単体 | メイン 1206×790 | 30170 |
| `t35-v7-settings-github-light.png` | debug=github-light。窓・外観クロームは明色。GitHub Light 行は画面外（1–5 行目まで） | 設定 520×672 | 30170 |
| `t35-v7-main-github-light.png` | debug=github-light。サイドバー/クローム明色、セッション面は暗。左マーカー＋「文字の読みやすさ」。単体 | メイン 1206×790 | 30170 |
| `t35-v7-settings-restored.png` | debug=phlox。チェックは Phlox 行 | 設定 520×672 | 30170 |

画素: メイン PNG 2412×1580、設定 PNG 1040×1344。

見本カード（PNG）: 各候補に「アプリ外観」「本文の見本」「現在の会話」（太字＋左マーカー）「メッセージを入力」「ターミナル配色」と色帯。GitHub Light 選択時も各カードの見本色は候補テーマのまま（クロームだけが github-light）。

## できなかった手順と理由

- 設定を開いた直後の見える範囲にテーマ一覧は無かった（Form がアイコン節まで落ちていた）。一覧撮影は `scroll-idx35=0` の後。指定の「スクロールせず見える範囲」は `settings-default`（外観なし）。
- テーマ名での AX 照合はできず（ボタン desc=`ボタン`、title missing、子 0）。ThemeStore.all の index で AX click。
- GitHub Light 行は 10 件中 9 番目で、スクロール先頭の設定ショットには入らない。チェックマークは prefs=`github-light` とクローム明色で確認。行そのもののチェックは未写。
- 一覧領域の `-R` は AX size のパース失敗でスキップ。`settings-list.png` は scrolled-top の切り出し。
- 入力欄（チャット composer）の実画面比較は課金なし表示経路が無いため未実施。フィクスチャは ui01-probe 等で、メイン中央は空の暗面。
- v1–v5 は設定 AX が空／click 失敗（System Events がプロセス名 `Phlox` で Release 側を掴む、`rd`/`th` 予約語、`ApplicationServices` 未インストール）。v6 は AX 原文取得後に深い走査で時間切れ。いずれも Release md5 は不変。

PM 目視ゲートは PM が PNG を確認して判定する。

=== REPORT COMPLETE ===
