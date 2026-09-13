実画面観測は両テーマとも完走しました。合否は判定していません。

成果は次のとおりです。

- 報告: `docs/agent-output/visual-task-17.md`（`status: partial`）
- PNG / AX: `/tmp/phlox-t13-visual.SPfR9c/t17-*`
- ハーネス: `shoot-t17.sh`（既存の t38 / t2735 手順を踏襲）

AX では通知テスト・管理が `enabled=True`、今すぐ確認が `enabled=False`。焦点は両テーマとも `set-focused-err=0` / `after_focused=True`。対象ボタンの action は実行していません。Release（PID 61465）の defaults md5 は不変、Debug は終了済みです。

leave だけ、ポインタが設定窓の外ではなくタブバー上に残っています。焦点の見え方と bordered 化は PNG を PM が判定します。

PM 目視ゲートは PM が PNG を確認して判定する。
: `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`
- バイナリ mtime: 2026-09-13 11:32:49。再ビルドしていない
- 観測開始時 HEAD（`shoot-t17.sh` 記録）: `eb7e10a`（台帳）。バイナリはこのパスの既存 Debug を使用

## ハーネス / 隔離

| 項目 | 値 |
|---|---|
| ハーネス | `/tmp/phlox-t13-visual.SPfR9c/shoot-t17.sh` |
| AX | `/tmp/phlox-t13-visual.SPfR9c/ax-t17.py`（enabled / frame / AXFocused）。タブは `dump-t38-toolbar.applescript` の title AXPress。設定オープンは help「設定」の click。close は `AXCloseButton` |
| データ | `$B/data-t33-v4` をテーマ別にコピー。sessions の `pid` 削除。sqlite / ports 削除 |
| 起動 | `PHLOX_AGENTS_JSON=$B/agents-t2735.json`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`、`-AppleLanguages "(ja)"` `-AppleLocale ja` `-phlox.appLanguage ja` `-ApplePersistenceIgnoreState YES` `-phlox.theme <dracula\|phlox-light>` |
| 比較用変更前 PNG | `t38-v8-settings-general-top.png` / `t38-v8-settings-agents-top.png`（task-38、RichButtonStyle）。`t2735-*-settings-preview.png` は外観タブのテーマ見本で、対象 3 ボタンではない |

| 時点 | `com.phlox.Phlox` md5 |
|---|---|
| before | `abe1760b9e29c4afc58e8860ac27845f` |
| 各テーマ起動時 / 終了後 / final | 同左 |

`release_md5_unchanged=yes`。Release PID 61465 は観測中・終了後とも生存（`/Applications/Phlox.app/Contents/MacOS/Phlox`）。Debug バイナリは各テーマ終了後 `pgrep` 不在。suite は `defaults delete`。

課金子プロセス: `BILLING_HITS=0`（両テーマ）。

## 共通ウィンドウ

設定窓 Quartz: `X=642 Y=172 Width=520 Height=728`。ウィンドウ名は選択タブ（`一般` / `エージェント`）。メイン `Phlox (Debug)` は `306, 192, 900×632`。フル窓 PNG は Retina 2x の **1040×1456**。

タブ identifier は空。title で AXPress。`ident=` 空は task-38 と同じ。

```
press-tb-title=pressed-AXPress i=1 ident= title=一般 desc=ボタン name=一般 pos=753, 204 size=55, 56
window1-name-after=一般
press-tb-title=pressed-AXPress i=3 ident= title=エージェント desc=ボタン name=エージェント pos=865, 204 size=73, 56
window1-name-after=エージェント
```

スクロールは不要（通知テスト・今すぐ確認・管理ボタンは初回 dump で到達）。`axscroll.py` は未使用。

ラベルは AXTitle ではなく **AXDescription**。`title=''`。管理ボタンの AX に `wrench.and.screwdriver` は出ていない。PNG にはレンチ形アイコンがある。AXChildren の CHILD 行は 0 件。

無効な更新へ `AXFocused` は設定していない。Return / Space は未使用。

## dracula

| 項目 | 値 |
|---|---|
| Debug PID | 67755 |
| suite | `com.phlox.t17.dracula.67653`（削除済み） |
| 設定 wid | 44917 |
| AX ログ | `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-ax.log` |
| 観測ログ | `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-obs.log` |

### AX 原文

```
BUTTON role=AXButton title='' desc='通知テスト' value='' ident= help= sub= enabled=True focused=False selected=None pos=672.0, 686.5 size=84.5, 24.0 frame=672.0,686.5,84.5,24.0 center=714.2,698.5 crop16=656.0,670.5,116.5,56.0
enabled=True
focused=False
title=''
```

```
BUTTON role=AXButton title='' desc='今すぐ確認' value='' ident= help= sub= enabled=False focused=None selected=None pos=672.0, 827.5 size=84.5, 24.0 frame=672.0,827.5,84.5,24.0 center=714.2,839.5 crop16=656.0,811.5,116.5,56.0
enabled=False
focused=None
title=''
```

期待どおり通知=`True`、更新=`False`。

```
before_focused=False before_enabled=True
BUTTON role=AXButton title='' desc='通知テスト' ...
set-focused-err=0
after_focused=True
focus-result=ok
```

```
BUTTON role=AXButton title='' desc='エージェント管理を開く' value='' ident= help= sub= enabled=True focused=False selected=None pos=672.0, 815.0 size=185.5, 24.0 frame=672.0,815.0,185.5,24.0 center=764.8,827.0 crop16=656.0,799.0,217.5,56.0
enabled=True
focused=False
title=''
```

```
before_focused=False before_enabled=True
BUTTON role=AXButton title='' desc='エージェント管理を開く' ...
set-focused-err=0
after_focused=True
focus-result=ok
```

### PNG 一覧（PID=67755）

| ファイル | 対象 | 論理 crop / 窓 | ピクセル | PID |
|---|---|---|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-general.png` | 設定窓・一般 | 520×728 | 1040×1456 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-notify.png` | 通知テスト 通常 | frame+16pt | 234×114 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-notify-hover.png` | 通知テスト hover | 同上 | 234×114 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-notify-leave.png` | 通知テスト leave | 同上 | 234×114 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-notify-focused.png` | 通知テスト 焦点 | 同上 | 234×114 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-update.png` | 今すぐ確認 通常（無効） | frame+16pt | 234×114 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-update-hover.png` | 今すぐ確認 hover（無効・観察のみ） | 同上 | 234×114 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-agents.png` | 設定窓・エージェント | 520×728 | 1040×1456 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-manage.png` | 管理を開く 通常 | frame+16pt | 436×112 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-manage-hover.png` | 管理を開く hover | 同上 | 436×112 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-manage-leave.png` | 管理を開く leave | 同上 | 436×112 | 67755 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-dracula-manage-focused.png` | 管理を開く 焦点 | 同上 | 436×112 | 67755 |

## phlox-light

| 項目 | 値 |
|---|---|
| Debug PID | 71671 |
| suite | `com.phlox.t17.phlox-light.67653`（削除済み） |
| 設定 wid | 44940 |
| AX ログ | `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-ax.log` |
| 観測ログ | `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-obs.log` |

### AX 原文

frame / enabled / focused は dracula と同値（同じ論理座標）。

```
BUTTON role=AXButton title='' desc='通知テスト' value='' ident= help= sub= enabled=True focused=False selected=None pos=672.0, 686.5 size=84.5, 24.0 frame=672.0,686.5,84.5,24.0 center=714.2,698.5 crop16=656.0,670.5,116.5,56.0
enabled=True
```

```
BUTTON role=AXButton title='' desc='今すぐ確認' value='' ident= help= sub= enabled=False focused=None selected=None pos=672.0, 827.5 size=84.5, 24.0 frame=672.0,827.5,84.5,24.0 center=714.2,839.5 crop16=656.0,811.5,116.5,56.0
enabled=False
```

```
set-focused-err=0
after_focused=True
focus-result=ok
```
（通知テスト / エージェント管理を開くの両方。`before_focused=False before_enabled=True`）

```
BUTTON role=AXButton title='' desc='エージェント管理を開く' value='' ident= help= sub= enabled=True focused=False selected=None pos=672.0, 815.0 size=185.5, 24.0 frame=672.0,815.0,185.5,24.0 center=764.8,827.0 crop16=656.0,799.0,217.5,56.0
enabled=True
```

### PNG 一覧（PID=71671）

| ファイル | 対象 | 論理 crop / 窓 | ピクセル | PID |
|---|---|---|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-general.png` | 設定窓・一般 | 520×728 | 1040×1456 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-notify.png` | 通知テスト 通常 | frame+16pt | 234×114 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-notify-hover.png` | 通知テスト hover | 同上 | 234×114 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-notify-leave.png` | 通知テスト leave | 同上 | 234×114 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-notify-focused.png` | 通知テスト 焦点 | 同上 | 234×114 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-update.png` | 今すぐ確認 通常（無効） | frame+16pt | 234×114 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-update-hover.png` | 今すぐ確認 hover（無効・観察のみ） | 同上 | 234×114 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-agents.png` | 設定窓・エージェント | 520×728 | 1040×1456 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-manage.png` | 管理を開く 通常 | frame+16pt | 436×112 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-manage-hover.png` | 管理を開く hover | 同上 | 436×112 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-manage-leave.png` | 管理を開く leave | 同上 | 436×112 | 71671 |
| `/tmp/phlox-t13-visual.SPfR9c/t17-phlox-light-manage-focused.png` | 管理を開く 焦点 | 同上 | 436×112 | 71671 |

## 変更前 PNG（比較用・今回未再撮影）

| ファイル | 内容 |
|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-general-top.png` | 一般。通知テスト／今すぐ確認が紫グラデーション塗り（RichButtonStyle）。PID=54173、論理 520×728 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-agents-top.png` | エージェント。管理ボタンが同系統の塗り＋レンチ。PID=54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t2735-dracula-settings-preview.png` | 外観タブの Dracula 見本。対象 3 ボタンではない |

t38-v8 の起動テーマは `phlox`（暗色）。今回の dracula / phlox-light とは起動引数が異なる。

## できなかった手順と理由

- **leave を設定窓の外へ**: 手順は「ポインタを窓外へ」。実装はメイン窓中心相当 `(756.0, 272.0)` で、設定窓（642,172 520×728）と重なるタブバー上だった。`hit-win` は `一般` / `エージェント` のまま。ボタン上からは外れている。設定窓 bounds の外への移動は未達。
- **管理ボタンの SF Symbol 名**: AX に `wrench.and.screwdriver` は無い。`title=''`、`desc='エージェント管理を開く'`。アイコンの有無は PNG。
- **タブ AX identifier**: toolbar の 5 ボタンは `ident=` 空。title の AXPress で切替。
- **有効状態の「今すぐ確認」**: 専用 suite で updater 起動抑制。`enabled=False` を記録。有効時の実描画は未検証（契約どおり別状態の画像で代用しない）。
- **接続済み端末の失効行**: 隔離データ＋ ephemeral token のため行無し。宣言の不変性のみ。QR・失効は未操作。
- **Tab キー巡回**: 未実施。焦点は AX `set focused` のみ。敵対レビュー HIGH 3 どおり、失敗時は未達とする前提だったが、今回 `set-focused-err=0` / `after_focused=True`。焦点の見え方は PNG を PM が判定する。

終了: 各テーマの自 PID に `kill -TERM`。Debug `pgrep` 不在。suite 削除。Release 61465 残存。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定（2026-09-13、PNG を目視）

- 変更前（`t38-v8-settings-general-top.png`）の「通知テスト」「今すぐ確認」は紫〜ピンクの 2 色グラデーション＋発光枠。変更後（`t17-dracula-general.png`・`t17-phlox-light-general.png`）は標準 bordered の控えめな面で、トグルやリンクと強さがそろった。ヘッダーのグラデーション・アクセント色の tint（ボタン文字色）は維持。
- 無効な「今すぐ確認」は文字と面が減光され、有効な「通知テスト」と見分けられる（明暗とも）。hover は面の明度がわずかに上がる程度で、旧来の強い枠・影は無い。
- 焦点: AX set focused 後、通知テスト／エージェント管理を開く の両方に青いフォーカスリングが見える（dracula・phlox-light）。AX `after_focused=True` と一致。
- 判定: pass。未検証: 更新確認が有効な状態の見た目（隔離 suite では常に無効）、端末失効ボタン（隔離データに端末なし）。宣言の不変は rb で確認済み。

=== REPORT COMPLETE ===
