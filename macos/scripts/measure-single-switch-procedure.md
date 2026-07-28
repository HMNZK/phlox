# シングル表示のセッション切替コストを計測する手順

修正の前後で同一条件の数値を取るための再現手順。実測値と真因は
[ADR 0139](../docs/adr/0139-transcript-text-selection-and-render-budget.md)、
作業経緯は [delivery 0025](../docs/delivery/0025-single-view-switch-perf-worklog.md)。

## 前提と厳守事項

- **稼働中のリリース版（`/Applications/Phlox.app`）を終了させない。** `pkill` / `osascript quit` /
  `macos/scripts/debug-build-restart.sh` は使わない。リリース版・Debug 版・計測版は実行ファイル名が
  すべて `Phlox` で、プロセス名一致のコマンドは全部を巻き添えにする。
- **Debug 構成では計測しない。** 最適化が効かず、絶対値（合格閾値 200ms）の判定に使えない。
- **アドホック署名は使えない。** 同梱の Sparkle.framework が Developer ID 署名のままなので
  チーム ID 不一致で dyld がロードを拒否し、起動直後にクラッシュする。

## 1. 計測ビルド（Release・正規署名）

```bash
cd macos
/opt/homebrew/bin/xcodegen generate          # Phlox.xcodeproj は .gitignore 対象
xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Release \
  -derivedDataPath /tmp/PhloxMeasure<Variant> \
  CODE_SIGN_IDENTITY="Developer ID Application: Ryosuke Sakurai (9JGGMW6UW6)" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=9JGGMW6UW6 \
  OTHER_CODE_SIGN_FLAGS="--timestamp=none" build
```

`<Variant>` は `Baseline` / `Candidate` のように分ける（**稼働中の計測版と同じ derivedDataPath へ
ビルドしない**）。

## 2. フィクスチャ（前後で同一のものを使う）

ベースラインで使ったスナップショットは `/tmp/phlox-measure-data`。**再計測ではこれを作り直さず
そのまま使う**（作り直すと transcript の内容が変わり、比較が成立しない）。

失われた場合の再作成手順:

```bash
rm -rf /tmp/phlox-measure-data
cp -R ~/Library/Application\ Support/Phlox /tmp/phlox-measure-data   # コピー。元は触らない
cd /tmp/phlox-measure-data
cp sessions.json sessions.json.orig
jq '{schemaVersion, sessions: [.sessions[] | select(
      .id.rawValue == "7C953723-DEF8-41BB-8B2B-16547384273B" or
      .id.rawValue == "D02B46C5-CDF1-45B6-83D4-26EFE4834DE6" or
      .id.rawValue == "6210B9F7-CD48-4B26-9DED-C9FBFD498B73" or
      .id.rawValue == "5B091DAB-5720-47DE-82E4-92F18E7B1B26")]}' \
  sessions.json.orig > sessions.json
```

4 セッションへ絞るのは、復元時に起動するエージェントプロセスを抑えるため（全 11 セッションだと
その数だけ `claude` が起動する）。**フィクスチャを作り直したらベースラインも取り直すこと。**

## 3. 起動（データ・設定ともライブ版から隔離）

```bash
open -n \
  --env PHLOX_DATA_DIR=/tmp/phlox-measure-data \
  --env PHLOX_DEFAULTS_SUITE=com.phlox.Phlox.measure \
  --env PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1 \
  /tmp/PhloxMeasure<Variant>/Build/Products/Release/Phlox.app
sleep 30                                   # セッション復元の完了を待つ
MPID=$(pgrep -f "PhloxMeasure<Variant>/Build/Products/Release/Phlox.app/Contents/MacOS/Phlox" | head -1)
```

`PHLOX_DATA_DIR` / `PHLOX_DEFAULTS_SUITE` は `AppSupportLocator.swift:12,31` /
`PhloxUserDefaults.swift:7` が解釈する。**bundle id はライブ版と同じ**（`AppFlavor` は `#if DEBUG`
判定なので Release 構成では `.release`）なので、`open -n` で新規インスタンスを強制する。

起動後、**ライブ版と Debug 版の PID が変わっていないことを確認する**。

## 4. ウィンドウを既定サイズへ

```bash
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $MPID) \
  to tell window 1 to set {position, size} to {{0, 25}, {1500, 930}}"
```

サイドバー行の座標はこのウィンドウサイズ・位置を前提にしている。変えたら座標を取り直すこと。

**クリック座標を計算するときはウィンドウの実位置を読むこと。** 上の指定は `{0, 25}` だが、
実際に配置される Y はメニューバー分ずれて 33 になる（`kCGWindowBounds` で確認できる）。
25 を前提に計算すると 8pt ずれ、小さなボタンのクリックが外れる。

```bash
python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerPID') == $MPID and w.get('kCGWindowLayer', 9) == 0:
        print(w.get('kCGWindowBounds'))
"
```

`screencapture -l<windowID>` の画像はウィンドウ左上が原点・Retina で 2 倍なので、
画像座標 ÷2 ＋ ウィンドウ原点 が論理点になる。

## 4.5. サイドバーを展開して 1 件選択し、計測直前の画面を残す

**この節を飛ばすと計測が無言で無効になる。** SIGTERM で終了させた次の起動では選択セッションが
復元されず、サイドバーのプロジェクト行が**折りたたまれたまま**始まる。そのままクリックを送ると
セッション行ではなくプロジェクトの開閉ボタンを押すだけで、**トランスクリプトが一度も描画されない**。
それでも記録は成功し、ハング 0 件という「速くなったように見える」結果が出る。

```bash
python3 /tmp/phlox_click.py $MPID 25 166      # プロジェクト行の開閉トライアングル
sleep 3
python3 /tmp/phlox_click.py $MPID 95 196 --no-activate   # セッションを 1 件選択
sleep 8
screencapture -x -o -l$WID /tmp/precheck-<variant>.png   # 目視確認用に必ず残す
```

`precheck-*.png` を毎回開いて、**セッション行が展開されトランスクリプトが描画されている**ことを
目で確かめてから記録を始める。

## 5. 記録と操作

```bash
rm -rf /tmp/phlox-switch-<variant>.trace
nohup xcrun xctrace record --template 'Time Profiler' --attach $MPID \
  --output /tmp/phlox-switch-<variant>.trace --time-limit 45s > /tmp/xctrace.log 2>&1 &
sleep 9
python3 /tmp/phlox_switch_loop.py 12 7 > /tmp/switch_clicks.tsv
```

クリック間隔は **7 秒**。2.5 秒でも同じ値が出ることは確認済みだが、間隔が短いと
1 回分のコストが次の区間へはみ出していないかを疑う余地が残る。7 秒なら余裕がある。

`phlox_switch_loop.py`（計測時の一時スクリプト。リポジトリには置いていないので下記の仕様から
再作成する）は次を行う:

- サイドバーのセッション行を**実クリック**する（論理点 `(95,196) Lotus` / `(95,224) Dahlia` /
  `(95,252) Zinnia` / `(95,280) Foxglove`）。キーボードショートカット `⌘⌥↓` は
  実際のユーザー操作経路と違うので**使わない**。
- **クリックのたびに frontmost の pid を検証する**。同名 Phlox が 3 つ走っているため、
  検証なしで CGEvent を送るとライブ版へ誤爆する。
- 各クリックの時刻を TSV で記録する。

## 6. 集計

```bash
# ハング
xcrun xctrace export --input /tmp/phlox-switch-<variant>.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' > /tmp/hangs.xml
# メインスレッドの内訳
xcrun xctrace export --input /tmp/phlox-switch-<variant>.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > /tmp/tp.xml
```

`potential-hangs` から「件数・各継続時間・合計・クリック数で割った 1 回あたり平均」を出す。
`time-profile` は `<thread id|ref="N">` が Main Thread の行だけを取り、フレーム名の包含率を
集計する（**id/ref の参照圧縮を解決すること**。解決しないとメインスレッドのサンプルが
1 件しか取れない）。

**ハング件数だけで判断しない。** Instruments のハング検出には閾値があり、閾値未満は 0 件になる。
改善後の比較には「メインスレッドのサンプル数 ÷ クリック数」（Time Profiler は 1ms 間隔なので
サンプル数 ≒ ms）を使う。**待機のみの対照**（クリックせず同じ長さを記録）も取ること。
実測では 8ms/枠だったので、この指標はほぼ切替コストそのものとみなせる。

## 7. 合否判定

合格条件（実測前に確定）: **切替 1 回あたりのメインスレッド稼働が 200ms 以下**。

| | 切替 1 回 | ハング件数 | 最大 |
|---|---:|---:|---:|
| 修正前（2026-07-29） | 2447ms | 11 / 12 | 4564ms |
| 修正後（ADR 0139 適用） | 177ms | 0 | — |
| 待機のみの対照 | 8ms | 0 | — |

## 8. 後始末

```bash
kill $MPID          # 計測インスタンスだけを終了する。pkill は使わない
```

計測インスタンスが復元のために起動した `claude` プロセスも終了することを確認する。
