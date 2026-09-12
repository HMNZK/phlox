---
status: partial
task: task-38
---

# UX-06（task-38）実画面観測記録

製品コード・テスト・契約・台帳は未変更。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke は未使用。設定値は変更していない（Toggle・Picker・TextField・テーマ・アイコン・通知テスト・更新確認・QR・失効は未操作。タブの AXPress と撮影・スクロール試行のみ）。課金セッションは未作成。Release Phlox（PID 61465）には未接触。`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`。

PM 目視ゲートは PM が PNG を確認して判定する。

## ビルド

- コマンド: `cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t38b.log 2>&1`
- ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t38b.log`
- 末尾: `** BUILD SUCCEEDED **`
- 作業ツリー HEAD: `1e4e1f5`（台帳）。製品変更コミット: `89692d5`

## PID / suite

| 項目 | 値 |
|---|---|
| 本流実行 | v8（5 タブ AXPress 完走・SHOT 10 枚） |
| Debug PID | 54173 |
| suite | `com.phlox.t38.v8.54140` |
| データ | `$B/data-t33-v4` を `$B/data-t38-v8` へコピー（sqlite / ports 削除） |
| 起動 | `-AppleLanguages "(ja)"` `-AppleLocale ja` `-ApplePersistenceIgnoreState YES` `-phlox.appLanguage ja` `-phlox.theme phlox`、`PHLOX_AGENTS_JSON=$B/agents-t30.json` |
| ハーネス | `/tmp/phlox-t13-visual.SPfR9c/shoot-t38.sh`（成功ランナーは v8 と同一） |
| AX | 設定ボタンは help「設定」の click。タブは `toolbar 1` の AXButton に対する AXPress |

終了: 自 PID のみ `kill -TERM`。Debug バイナリの pgrep 不在。suite は `defaults delete`。Release 61465 `/Applications/Phlox.app/Contents/MacOS/Phlox` は残存。

先行の v1–v7 はメインウィンドウ未復元・設定ウィンドウ名がタブ名「一般」のため検出失敗・タブ座標ずれなどを記録した試行。本報告の SHOT / AX 原文は v8。

## 隔離確認

| 時点 | `com.phlox.Phlox` md5 |
|---|---|
| before | `abe1760b9e29c4afc58e8860ac27845f` |
| after-launch | 同左 |
| after-kill | 同左 |

`release_md5_unchanged=yes`。Release PID 61465 は観測中・終了後とも生存。

## ウィンドウ一覧（外枠寸法）

設定オープン直後 AX:

```
idx=1 name=一般 pos=642, 172 size=520, 728
idx=2 name=Phlox (Debug) pos=306, 192 size=900, 632
```

Quartz: 設定 `id=43865` bounds `X=642 Y=172 Width=520 Height=728`。メイン `id=43858` `900×632`。

コンテンツ指定は `.frame(width: 520, height: 640)`。実測外枠は **520×728**（タイトルバー＋タブ用ツールバー分が乗っている）。タブ切替後も外枠は 520×728 のまま。ウィンドウ `name` は選択中タブ名（`一般` / `外観` / `エージェント` / `接続` / `詳細`）になる。

## タブの AX 原文

初期選択はウィンドウ名 `一般`。toolbar は 5 個の `AXButton`。順序は契約どおり 一般・外観・エージェント・接続・詳細。`AXIdentifier` はすべて空（`settings-group-general` … `settings-group-advanced` はタブボタンに出ていない）。`selected` は `missing value`。選択の AX 信号はウィンドウ title と PNG のハイライト。

```
window=一般
toolbar-n=1
toolbar1-n=5
TB[1] role=AXButton value=missing value title=一般 name=一般 desc=ボタン ident= selected=missing value pos=753, 204 size=55, 56
TB[2] role=AXButton value=missing value title=外観 name=外観 desc=ボタン ident= selected=missing value pos=809, 204 size=55, 56
TB[3] role=AXButton value=missing value title=エージェント name=エージェント desc=ボタン ident= selected=missing value pos=865, 204 size=73, 56
TB[4] role=AXButton value=missing value title=接続 name=接続 desc=ボタン ident= selected=missing value pos=939, 204 size=55, 56
TB[5] role=AXButton value=missing value title=詳細 name=詳細 desc=ボタン ident= selected=missing value pos=995, 204 size=55, 56
```

直下 `UI element` の role 列: `AXGroup, AXToolbar, AXButton, AXButton, AXButton, AXStaticText`（後者3ボタンは閉じる／拡大縮小／しまう）。`radio button` 数は 0。`tab group` は window 直下に無し。

切替: `press-tb` の title 一致で AXPress。ident 指定はいずれも `NOTFOUND-tb`。

| 操作 | 結果 |
|---|---|
| press-tb `settings-group-appearance` | NOTFOUND-tb |
| press-tb `外観` | `pressed-AXPress i=2` → window name=`外観` |
| press-tb `エージェント` | `pressed-AXPress i=3` → `エージェント` |
| press-tb `接続` | `pressed-AXPress i=4` → `接続` |
| press-tb `詳細` | `pressed-AXPress i=5` → `詳細` |
| press-tb `一般`（往復） | `pressed-AXPress i=1` → `一般` |

group 1 の static text はヘッダーのみ（`Phlox (Debug)` / `設定`）。Form の Section 見出しは AX に出ていない。見出し照合は PNG。

## タブごとの見出し列挙と契約照合

PNG 目視（AX の Section 見出し列挙は未取得）。契約の所属は `tasks/task-38.md`「凍結する項目集合と順序」。

| タブ | 契約の section 見出し（この順） | PNG で見えた見出し | 照合 |
|---|---|---|---|
| 一般 | 言語・セッション・通知・アップデート | 言語、セッション、通知、アップデート（先頭ショットで 4 件とも末尾「今すぐ確認」まで見える） | PNG 上は一致 |
| 外観 | 外観・アプリアイコン | 外観。テーマ行（Phlox〜Gruvbox Dark の途中）。アプリアイコンは未到達 | 外観は一致。アプリアイコンは未検証 |
| エージェント | 権限・エージェント | 権限（bypass 行）、エージェント（「エージェント管理を開く」） | PNG 上は一致 |
| 接続 | モバイル接続・接続済みの端末 | モバイル接続（端末名 iPhone、QR コードを表示）。接続済みの端末は無し | モバイル接続は一致。接続済みの端末は未検証 |
| 詳細 | チームビュー討論・使用量・プライバシー・このアプリについて | チームビュー討論、使用量、プライバシー（リンク行が下端で欠ける）。このアプリについて無し | 先頭 3 見出しは見える。このアプリについてとプライバシー本文は未到達 |

テーマ見本（外観・先頭 PNG）: 各行で「アプリ外観」と「ターミナル配色」が同一行に並ぶ。ラベル自体の折り返しは、この解像度の PNG では見えない。見本内部の「本文の見本」「現在の会話」「メッセージを入力」も 1 行。

## suite の before / after 比較

専用 suite `com.phlox.t38.v8.54140` を `defaults export <suite> -` して md5。

| 時点 | md5 | keys |
|---|---|---|
| before（設定を開く直前） | `d1a66206d9413ab3fec69cc65c8bb30f` | `phlox.grid.paneLayout`, `phlox.panelDrawer.width.migratedTo560` |
| after-open | 同左 | 同左 |
| after-tabs（5 タブ往復して一般へ戻った後） | 同左 | 同左 |

差分: added=(none) / removed=(none) / changed=(none)。設定キー（`phlox.theme` / `phlox.notify.*` / `phlox.usage.*` / `phlox.agora.*` 等）の新規保存は無い。あるのは起動時のグリッド／ドロワー移行キーのみ。

## PNG 一覧

論理外枠はすべて 520×728。ファイルは Retina 2x の 1040×1456。PID=54173。wid=43865。

| ファイル | 対象タブ | 先頭/末尾 | ウィンドウ名 | 論理寸法 | PID |
|---|---|---|---|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-general-top.png` | 一般 | 先頭 | 一般 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-general-bottom.png` | 一般 | 末尾試行（スクロールバー無し。先頭と同内容） | 一般 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-appearance-top.png` | 外観 | 先頭 | 外観 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-appearance-bottom.png` | 外観 | 末尾試行（スクロールせず先頭と同内容） | 外観 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-agents-top.png` | エージェント | 先頭 | エージェント | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-agents-bottom.png` | エージェント | 末尾試行（先頭と同内容） | エージェント | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-connection-top.png` | 接続 | 先頭 | 接続 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-connection-bottom.png` | 接続 | 末尾試行（先頭と同内容） | 接続 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-advanced-top.png` | 詳細 | 先頭 | 詳細 | 520×728 | 54173 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v8-settings-advanced-bottom.png` | 詳細 | 末尾試行（スクロールせず先頭と同内容） | 詳細 | 520×728 | 54173 |

AX ログ: `/tmp/phlox-t13-visual.SPfR9c/t38-v8-ax.log`。観測ログ: `/tmp/phlox-t13-visual.SPfR9c/t38-v8-obs.log`。

## できなかった手順と理由

- **タブの AX identifier** `settings-group-general` … `settings-group-advanced`: ツールバーの 5 ボタンに `ident=` が空。title/name での AXPress はできた。
- **タブの selected 属性**: `missing value`。選択はウィンドウ名と PNG の枠で分かる。
- **Form 見出しの AX 列挙**: `every static text of window 1` はタブ名だけ。group 1 は `Phlox (Debug)` と `設定` だけ。Section 見出しは PNG 依存。
- **スクロールバー value=1**: window / group 1 とも scroll bar が AX に無い。一般は 4 Section が先頭で収まる。外観のアプリアイコン、詳細の「このアプリについて」（プライバシー行の欠け）は末尾ショット未達。
- **接続済みの端末**: 隔離データ＋ `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` のため端末行は無い。契約どおり未検証（描画コードの有無は本観測の対象外）。QR は押していない。
- **v1–v2**: エージェント管理ウィンドウだけが復元され、help「設定」が無かった。v3 以降は `-ApplePersistenceIgnoreState YES` でメイン `Phlox (Debug)` を出してから設定を開いた。

PM 目視ゲートは PM が PNG を確認して判定する。

## 追加ラウンド（v9: 末尾スクロール）

製品コード・テスト・契約・台帳は未変更。再ビルドしていない。既存 Debug は `/tmp/phlox-t13-visual.SPfR9c/Build`（HEAD 製品コミット `89692d5`）。`/tmp/phlox-t13-visual.SPfR9c/build-t38b.log` 末尾は `** BUILD SUCCEEDED **`。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke は未使用。設定値は変更していない（Toggle・Picker・TextField・テーマ・アイコン・通知テスト・更新確認・QR・失効は未操作。タブの AXPress と撮影・ホイールスクロールのみ）。課金セッションは未作成。Release Phlox（PID 61465）には未接触。`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`。

| 項目 | 値 |
|---|---|
| 本流実行 | v9（ホイールで Form 末尾まで。SHOT 公式 3 枚 + 変化なしタブは SHOT 省略） |
| Debug PID | 69139 |
| suite | `com.phlox.t38.v9.69102` |
| データ | `$B/data-t33-v4` を `$B/data-t38-v9` へコピー（sqlite / ports 削除） |
| 起動 | v8 と同じ（`-AppleLanguages "(ja)"` `-AppleLocale ja` `-ApplePersistenceIgnoreState YES` `-phlox.appLanguage ja` `-phlox.theme phlox`、`PHLOX_AGENTS_JSON=$B/agents-t30.json`） |
| ハーネス | `/tmp/phlox-t13-visual.SPfR9c/shoot-t38b.sh v9` |
| スクロール | `/tmp/phlox-t13-visual.SPfR9c/axscroll.py`。Form 中央 `(902.0, 636.0)`（ウィンドウ `642,172 520×728`、ヘッダー inset 200）。`dy=-600` を 0.5 秒待ちで PNG md5 が前回と同一になるまで |
| 終了 | 自 PID のみ `kill -TERM`。Debug バイナリの pgrep 不在。suite は `defaults delete`。Release 61465 残存 |

隔離: `com.phlox.Phlox` md5 before / after-launch / after-kill はいずれも `abe1760b9e29c4afc58e8860ac27845f`。`release_md5_unchanged=yes`。

### axscroll.py 全文

```
# usage: axscroll.py <pid> <x> <y> <dy>
# 画面座標 (x,y) が自 PID の最前面ウィンドウ内で、上に他ウィンドウが無いときだけ
# CGEventCreateScrollWheelEvent（ピクセル単位）を送る。負の dy で下方向。キーイベントは使わない。
import sys, Quartz
pid, x, y, dy = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4])
wins = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
for w in wins:  # front-to-back
    if w.get('kCGWindowLayer') != 0: continue
    b = w['kCGWindowBounds']
    if b['X'] <= x <= b['X']+b['Width'] and b['Y'] <= y <= b['Y']+b['Height']:
        if w.get('kCGWindowOwnerPID') == pid:
            moved = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), Quartz.kCGMouseButtonLeft)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, moved)
            Quartz.CGWarpMouseCursorPosition((x, y))
            ev = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitPixel, 1, dy)
            Quartz.CGEventSetLocation(ev, (x, y))
            Quartz.CGEventSetIntegerValueField(ev, Quartz.kCGScrollWheelEventPointDeltaAxis1, dy)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
            print("scrolled dy=%d at=%.1f,%.1f win=%r id=%s" % (
                dy, x, y, w.get('kCGWindowName'), w.get('kCGWindowNumber')))
            sys.exit(0)
        print("SKIP: covered by pid=%s %s" % (w.get('kCGWindowOwnerPID'), w.get('kCGWindowOwnerName')))
        sys.exit(2)
print("SKIP: no window at point")
sys.exit(3)
```

python3 に Quartz あり（`kCGScrollEventUnitPixel=0`）。キーイベントは未使用。クリックはタブ AXPress と設定オープン（help「設定」）のみ。テーマ行・アイコン行・トグルには未クリック。

### 各タブの末尾で見えた見出し・行（PNG 目視）

**外観（スクロールあり、i=3 で安定）**

- 先頭 SHOT（v8 同一確認）: 見出し「外観」。テーマ Phlox（選択チェック）・Tokyo Night・Dracula・Catppuccin Mocha・Gruvbox Dark（下端で欠ける）。
- 中間 i=1: Nord・Catppuccin Latte・Solarized Light・GitHub Light・Phlox Light（下端）。
- 末尾 SHOT: テーマ一覧の最後は **Phlox Light**（フッタ「テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。」）。見出し **アプリアイコン** と行が全部見える: ホワイト（選択チェック）・ダーク+グラデ・ダーク・グラデーション・ライト。フッタ「Dock とアプリのアイコンを切り替えます。変更は即座に反映されます。」まで。

**詳細（スクロールあり、i=2 で安定）**

- 末尾 SHOT: 「使用量」全行。見出し **プライバシー** と本文リンク行 **プライバシーポリシー**（青リンク、欠けなし）。見出し **このアプリについて** と内容: アプリ = Phlox (Debug)、バージョン = 1.6.1、ビルド = 24。これ以上 PNG は変化せず、ビルド行が末尾。

**一般**: スクロール不要（先頭で全件表示）。言語・セッション・通知・アップデート（「今すぐ確認」まで）。md5 1 回目で不変。

**エージェント**: スクロール不要（先頭で全件表示）。権限（bypass 7 行）・エージェント（「エージェント管理を開く」）とフッタまで。md5 1 回目で不変。

**接続**: スクロール不要（先頭で全件表示）。モバイル接続（端末名 iPhone、QR コードを表示）。接続済みの端末は無し（隔離 + `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`）。md5 1 回目で不変。

5 タブ往復（一般→外観→エージェント→接続→詳細→一般）はいずれも `pressed-AXPress` で window name がタブ名に一致。

### PNG 一覧

論理外枠はすべて 520×728。ファイルは Retina 2x の 1040×1456。PID=69139。wid=43904。

| ファイル | 対象タブ | 先頭/末尾 | ウィンドウ名 | 論理寸法 | PID |
|---|---|---|---|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t38-v9-settings-appearance-top.png` | 外観 | 先頭（v8 同一確認） | 外観 | 520×728 | 69139 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v9-settings-appearance-bottom.png` | 外観 | 末尾（ホイール、md5 安定） | 外観 | 520×728 | 69139 |
| `/tmp/phlox-t13-visual.SPfR9c/t38-v9-settings-advanced-bottom.png` | 詳細 | 末尾（ホイール、md5 安定） | 詳細 | 520×728 | 69139 |

一般・エージェント・接続は変化なしのため公式 `-bottom` SHOT は作っていない。観測用 PNG: `t38-v9-scroll-{general,agents,connection}-before.png` と `-1.png`（md5 同一）。観測ログ: `/tmp/phlox-t13-visual.SPfR9c/t38-v9-obs.log`。AX ログ: `/tmp/phlox-t13-visual.SPfR9c/t38-v9-ax.log`。

### suite 比較

専用 suite `com.phlox.t38.v9.69102` を `defaults export <suite> -` して md5。

| 時点 | md5 | keys |
|---|---|---|
| before（設定を開く直前） | `c407b7810967443e831ce1ff7bdcf1b5` | `phlox.grid.paneLayout`, `phlox.panelDrawer.width.migratedTo560` |
| after-open | 同左 | 同左 |
| after-tabs（5 タブ往復して一般へ戻った後） | 同左 | 同左 |

差分: added=(none) / removed=(none) / changed=(none)。テーマ・アイコン・通知等の設定キー新規保存は無い。

### できなかったこと

- タブの AX identifier / selected、Form 見出しの AX 列挙は v8 と同じく空。照合は PNG。
- AX スクロールバーは引き続き無し。末尾到達はホイール + PNG md5 安定で代替した。
- 接続済みの端末は隔離データのため行が無い（契約どおり未検証）。QR は押していない。
- 「このアプリについて」のビルド行より下に追加行があるかは、これ以上スクロールしても PNG が変わらないこと以上は分からない。見える末尾はビルド 24。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定（2026-09-13）

- 判定: **pass**。PM が v8 の 5 タブ先頭 PNG（general/appearance/agents/connection/advanced）と v9 の末尾 PNG（appearance-bottom・advanced-bottom）を目視。5 タブ「一般・外観・エージェント・接続・詳細」が契約の順序・アイコンで並び、初期選択は一般。14 Section の所属は契約表どおり（一般: 言語・セッション・通知・アップデート／外観: 外観（テーマ 10 件＋見本）・アプリアイコン／エージェント: 権限・エージェント／接続: モバイル接続／詳細: チームビュー討論・使用量・プライバシー・このアプリについて）。外観変更・権限確認・接続設定・更新確認の所在が見出しから分かる。文字の欠け・重なりなし、テーマ見本のラベルは 1 行。
- 値の不変: 専用 suite の export は設定を開く前・開いた直後・5 タブ往復後で md5・key とも同一（新規保存なし）。Release `com.phlox.Phlox` md5 不変。
- 未検証・制限: (1) 「接続済みの端末」Section は隔離データのため未描画（描画コードの存在は rb で確認）。(2) タブの AX identifier `settings-group-<id>` はコードにあるが（rb で確認）、標準 TabView のツールバー型タブでは AX に露出せず selected も取れない。タブは title で AXPress でき、ウィンドウ名で選択タブが分かる。SwiftUI 標準 TabView の挙動であり、契約の「標準 TabView」決定を優先して受容（decision-log に記録）。(3) AX スクロールバーが無く、末尾到達はホイールスクロール（axscroll.py、遮蔽確認付き）と PNG 安定で確認。

=== REPORT COMPLETE ===

