---
status: partial
task: task-47
---

# task-47 画面観測・撮影記録（r2）

合否欄: **pass**（PM 判定。根拠は末尾の「PM 判定」節）

## 実行情報

- 実行コミット SHA: `a2fe040427902fd9ce0819f976f0b3436f7dcff1`
- 作業ディレクトリ: `/tmp/ui-ux-wt-47`（`task/47`）
- PNG 保存先: `/tmp/phlox-t47-visual/r2/`（36 枚）
- 実行した起動コマンド原文（各条件を別プロセスで 1 組ずつ）:

```sh
(cd /tmp/ui-ux-wt-47/macos/Packages/SessionFeature && env PHLOX_PM_VISUAL_TASK=47 PHLOX_PM_VISUAL_WIDTH=<360|720> PHLOX_PM_VISUAL_SCALE=<0.8|1.0|2.0> PHLOX_PM_VISUAL_THEME=<light|dark> swift test --no-parallel --filter PMTranscriptVisualTask47Tests)
```

テスト起動は共通ラッパー `compact-test` 経由で行った。実エージェント（claude/codex/cursor）は起動していない。System Events の key code / keystroke は使っていない。

## 固定入力・注入イベント

- 固定 transcript item ID: `u1`, `a-md`, `r-summary`, `r-code`, `cmd-past`, `err-1`, `cmd-latest`。
- ハーネス内イベント: `turnStarted`、`agentMessageDelta(itemId: "a-append", text: "追記された回答")`、`turnCompleted`。
- 画面操作: 各組で `AXDisclosureTriangle` の最初の要素（説明: `思考の詳細, 有効`）へ `AXPress`、公開されている `AXScrollBar` へ `AXValue = 1.0`、`AXCloseButton` へ `AXPress`。
- 操作中の対象 AX PID は下表の `app PID` のみ。Release Phlox の PID 61465 は対象外。

## 12 組の撮影記録

すべて `initial`、`expanded`、`tail` の 3 枚を保存した。`runner PID` はラッパー、`app PID` は窓所有プロセス。bounds は `x,y,width,height`（pt）。末尾余白のハーネス状態値 `bottomMargin` は AX 属性として公開されず取得できなかった。公開されたスクロールバー値は全組で `before=0`, `after=1`。

| 条件 | runner PID | app PID | windowID | bounds | 撮影ファイル | 閉鎖後 |
| --- | ---: | ---: | ---: | --- | --- | --- |
| 360 / 0.8 / light | 27040 | 27246 | 52015 | 0,262,360,1056 | `t47-360-0.8-light-{initial,expanded,tail}.png` | confirmed / 0 |
| 360 / 0.8 / dark | 27404 | 27572 | 52021 | 0,262,360,1056 | `t47-360-0.8-dark-{initial,expanded,tail}.png` | confirmed / 0 |
| 360 / 1.0 / light | 27800 | 27969 | 52027 | 0,261,360,1058 | `t47-360-1.0-light-{initial,expanded,tail}.png` | confirmed / 0 |
| 360 / 1.0 / dark | 28120 | 28288 | 52031 | 0,262,360,1056 | `t47-360-1.0-dark-{initial,expanded,tail}.png` | confirmed / 0 |
| 360 / 2.0 / light | 28441 | 28610 | 52037 | 0,261,360,1058 | `t47-360-2.0-light-{initial,expanded,tail}.png` | confirmed / 0 |
| 360 / 2.0 / dark | 28760 | 28926 | 52043 | 0,261,360,1058 | `t47-360-2.0-dark-{initial,expanded,tail}.png` | confirmed / 0 |
| 720 / 0.8 / light | 29079 | 29253 | 52049 | 0,261,720,1058 | `t47-720-0.8-light-{initial,expanded,tail}.png` | confirmed / 0 |
| 720 / 0.8 / dark | 29403 | 29583 | 52055 | 0,262,720,1056 | `t47-720-0.8-dark-{initial,expanded,tail}.png` | confirmed / 0 |
| 720 / 1.0 / light | 29783 | 29952 | 52061 | 0,262,720,1056 | `t47-720-1.0-light-{initial,expanded,tail}.png` | confirmed / 0 |
| 720 / 1.0 / dark | 30123 | 30287 | 52067 | 0,262,720,1056 | `t47-720-1.0-dark-{initial,expanded,tail}.png` | confirmed / 0 |
| 720 / 2.0 / light | 30460 | 30631 | 52073 | 0,262,720,1056 | `t47-720-2.0-light-{initial,expanded,tail}.png` | confirmed / 0 |
| 720 / 2.0 / dark | 30787 | 30981 | 52079 | 0,262,720,1056 | `t47-720-2.0-dark-{initial,expanded,tail}.png` | confirmed / 0 |

生ログ: `/tmp/phlox-t47-visual/r2/*-retry.log`、メタデータ: `/tmp/phlox-t47-visual/r2/r2-metadata.tsv`。

## AX 原文の要点

12 組すべてで同じ記録になった。

```text
AXWindows count=1
AXDisclosureTriangle AXPress status=0 before=0 after=1
AXScrollBar AXValue set=1.0 status=0 before=0 after=1
AXCloseButton AXPress status=0
runner_exit=confirmed runner_wait_status=0
```

初期 AX には `AXDisclosureTriangle value=0 description=思考の詳細, 有効`、展開後には同じ要素の `value=1` が記録された。初期 AX の transcript には `確認結果`、`太字 と 斜体`、`箇条書き`、`引用`、リンク `詳細`、表セル `A/B/x/y`、`思考の詳細`、`有効`、エラー本文 `a/**/b: error` が現れた。

## 観測した事実

- 初期 PNG では `a-md` の見出し「確認結果」、太字、斜体、箇条書き、引用の縦線、リンク「詳細」、2×2 表が視認できる。`a-md` の表示箇所には `**`、`##`、リンク記法の角括弧・丸括弧は見えていない。エラーカード本文には固定入力どおり `a/**/b: error` が表示された。
- 表の `A/B/x/y` は、light では周囲の本文と同じ濃色、dark では周囲の本文と同じ淡色で描画されている。表の背景・罫線は本文背景と異なる。
- 初期状態の「思考の詳細」は右向きの開閉印と要約「有効」を表示する。AX の値は `0`。`AXPress` 後の expanded PNG では下向きの開閉印と本文「有効」が表示され、AX の値は `1`。展開本文の色は、カード見出しより淡い gray で描画されている。
- 360pt / 倍率 2.0 の expanded・tail PNG では、画面下部のコンポーザ枠が「処理の詳細（1件）」の下側と重なり、ラベル下部および右側の開閉印の一部がコンポーザ上端の背後にある。light と dark の両方で観測した。
- 720pt / 倍率 1.0 の initial・expanded PNG では、エラーカードとコンポーザの間に大きな空白領域があり、コンポーザ全体が画面下部に描画されている。
- `tail` PNG は `AXScrollBar` の値を 1 にした後の状態である。AX ツリーで公開された唯一の `AXScrollBar` は先頭の操作ボタン列の `AXScrollArea` 配下にあり、`tail` ではこの横方向のボタン列が移動している。transcript の `AXScrollArea` 配下には `AXScrollBar` が公開されなかった。したがって、AX による transcript の縦方向末尾への位置設定値は取得できていない。ハーネス状態 `bottomMargin` の実数値も AX からは取得できていない。

## 再現できなかった／未観測の項目

- 未閉じ強調 4 種類、改行跨ぎの対象外ケース、各コード境界ケース（0/3/4 空白、タブ、3/4 バッククォート、チルダ、未閉じ、インライン、CRLF/CR、末尾空行）は、この撮影手順では個別に操作・表示していない。初期/展開/末尾の 3 状態では、当該個別 fixture の表示を取得していない。
- `r-code`（コードだけの思考）を開く操作は行っていない。開いたのは `r-summary` の「思考の詳細」であるため、コードだけの思考を全文まで到達させた画面はない。
- transcript の縦スクロールバーは AX に公開されず、`AXValue=1.0` で縦方向末尾へ送ったこと、およびその位置での最後の行とコンポーザ直上余白は確認できていない。

## UserDefaults・プロセス残存確認

- `~/Library/Preferences/com.phlox.Phlox.plist` MD5（開始前）: `51a4354558727f023b062c7246ce19db`
- 同 MD5（終了後）: `51a4354558727f023b062c7246ce19db`
- 終了時の Release Phlox: `61465 /Applications/Phlox.app/Contents/MacOS/Phlox`（残存）。
- 上表の 12 組の runner PID と app PID は終了後の `ps -p` に残っていない。終了操作で追加の kill は行っていない。
- リポジトリのコード・テスト・契約・台帳は変更していない。この記録ファイルのみを追加した。コミットは行っていない。

=== REPORT COMPLETE ===

## PM 判定（2026-09-14、r2/r3/r4 の PNG を PM が閲覧）

判定: **pass**（契約「## 課金なしの PM 目視ゲート」）。観測は 3 ラウンドに分けた: r2＝12 組（幅360/720 × 倍率0.8/1.0/2.0 × 明暗）の初期・展開・末尾、r3＝コード境界 11 ケース・未閉じ強調・同長置換・思考展開・末尾スクロール・文字色実測（`visual-task-47-r3.md`）、r4＝`最新コマンド` 状態での `r-code`・`cmd-latest`（`visual-task-47-r4.md`）。

合格根拠（PM が PNG で直接確認した点）:
- 回答 Markdown は見出し・太字・斜体・箇条書き・引用・リンク・2×2 表として描画され、`**` `##` やリンク記法の角括弧は本文に露出しない。表セル `x` `y` は周囲の本文と同じ色で描かれる（task-47 の実装修正点。明暗とも確認）。
- コード保護: `0空白` `3空白` `4空白` `タブ` `3本` `4本` `チルダ` `未閉じ` `インライン` `CRLF` `末尾空行` の 11 ケースとも、コード内の `**x` が装飾化されず、前置インデントが保たれ、言語ラベルとコピー操作を持つコードカードとして描かれる。`4本` は外側フェンスのみ消えて内側の 3 バッククォートが内容として残る。`4空白` はインデントコードとしてフェンス文字列自体が内容になる。
- コマンド・出力・エラーの原文保護: `echo **ok`、`** not markdown` / `## also not` / `/tmp/a/**/b: ok`、`a/**/b: error` はいずれも記号のまま表示される。
- 未閉じ強調: `**確` → `**確認` → `**確認**` の 3 段階とも先頭の `**` は露出せず本文が太字として読める。同長置換（`**確認`→`**更新`）で旧内容が残らない。
- 思考カード: 既定は閉、要約は装飾除去済み。`r-summary` を開くと本文（`## 有効`）が secondary 色で出る（実測 `#494949`、背景 `#F7F7F7` に対し 8.40:1。回答 primary は `#1D1D1D` / 15.74:1 で明確に別色）。要約なしでコードだけの `r-code` を開くとコード全文 `let value = "**x"` に到達でき、`**` は保たれる（明暗とも）。
- 重なり・切れ: 12 組で本文の切れ・到達不能はない。最狭・最大倍率（360pt × 2.0）でも末尾までスクロールすると最終カードとコンポーザ上端の間に約 84pt の余白が残り、隠れない。

未検証として残す 3 点（いずれも合否に影響しないと PM が判断）:
- 実イベント追記（`a-append` / `追記された回答`）の画面表示。ハーネスのルートは `scenario.items` を描画し、VM の transcript を描画しないため、窓では出ない。実イベント経路自体は凍結アサーション `assertRealEventAppend` が VM 側で検証済み。ハーネス構造の制約であり製品欠陥ではない。
- 最新／過去コマンドの「実行中」補足の差。観測時点は turn 完了後のため両方 `出力あり` になる。実行中表示は task-46 の凍結テストと本ハーネスの状態アサーションが担保する。
- タブ・行末空白・CR の不可視文字そのものは画像から数えられない。`0空白` と `末尾空行` については AX 値 `\t  **x  \n` として保持を確認した。

ハーネス修理 2 件（#4 幅・倍率・テーマの環境変数、#5 活性化ポリシーと操作列配置）は PM 側の欠陥修理として実施し、再凍結済み（baseline 1e202e1）。製品差分は変更していないためレビュー r2 の pass は有効。
