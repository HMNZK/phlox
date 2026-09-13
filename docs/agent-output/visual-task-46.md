---
status: partial
task: task-46
---

# task-46 PM 目視ゲート記録（撮影・操作・記録）

合否は PM が PNG を確認して判定する。製品コード・凍結テスト・ハーネス・契約・台帳は未変更。コミットしていない。

## 実行コミット SHA

`a18ca11520d04f7b46730cf26068ee87fd6dc3ba`（ブランチ `task/46`、`a18ca11 task-46: 凍結テストを実パスへ復帰（rebase で落ちた rename を再適用）`）

## 起動コマンド原文

窓表示モード。作業ディレクトリ `/tmp/ui-ux-wt-46`。幅・倍率・テーマは環境変数で切替（ハーネス 181〜217 行）。

```sh
(cd macos/Packages/SessionFeature && env PHLOX_PM_VISUAL_TASK=46 PHLOX_PM_VISUAL_WIDTH=<w> PHLOX_PM_VISUAL_SCALE=<s> PHLOX_PM_VISUAL_THEME=<t> swift test --no-parallel --filter PMTranscriptVisualTask46Tests)
```

既定組の実コマンド:

```sh
(cd macos/Packages/SessionFeature && env PHLOX_PM_VISUAL_TASK=46 PHLOX_PM_VISUAL_WIDTH=720 PHLOX_PM_VISUAL_SCALE=1.0 PHLOX_PM_VISUAL_THEME=light swift test --no-parallel --filter PMTranscriptVisualTask46Tests)
```

操作は自 PID への AX（`AXUIElementPerformAction(..., "AXPress")` と属性取得）および System Events `first process whose unix id is <PID>`（info / disclosures）。クリック座標が必要なときだけ `/tmp/phlox-t13-visual.SPfR9c/axclick.py`。スクロールは `AXScrollBar` の `AXValue` 設定（必要時 `axscroll.py`）。撮影は `screencapture -o -l <windowID>`。System Events の key code / keystroke は未使用。`com.phlox.Phlox` の UserDefaults は未書き込み。課金セッションは未作成。Release Phlox PID 61465 は未接触。

AX 原文の共通形（12 組とも同じ。開閉で `value` だけ変わる）:

```
osax: name=swiftpm-testing-helper unix id=<PID> background only=false visible=true frontmost=false nwin=1 nui=2
AXRole err=0 val=AXApplication
AXWindows err=0 n=1
AXDisclosureTriangle value=False（初期閉）/ True（開）。desc は見出し＋補足。
AXPress err=0
```

製品の `.accessibilityValue("展開中"/"折りたたみ中")` は AX ツリー上は `AXDisclosureTriangle` の boolean として出る。osascript `entire contents` では `role=AXDisclosureTriangle value=false`。

## 12 組（PID・窓 bounds）

| 幅 | 倍率 | テーマ | PID | windowID | bounds | osax 原文 | 結果 |
|---|---|---|---|---|---|---|---|
| 720 | 1.0 | light | 69335 | 47324 | {X=0, Y=386, W=720, H=932} | `unix id=69335 background only=false visible=true frontmost=false nwin=1 nui=2` | 全操作撮影 |
| 720 | 1.0 | dark | 11408 | 47504 | {X=-1, Y=385, W=722, H=934} | `unix id=11408 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 720 | 0.8 | light | 10069 | 47488 | {X=2, Y=389, W=716, H=926} | `unix id=10069 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 720 | 0.8 | dark | 10740 | 47496 | {X=-1, Y=385, W=722, H=934} | `unix id=10740 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 720 | 2.0 | light | 12737 | 47512 | {X=0, Y=386, W=720, H=932} | `unix id=12737 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 720 | 2.0 | dark | 2573 | 47430 | {X=0, Y=386, W=720, H=932} | `unix id=2573 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 360 | 0.8 | light | 6371 | 47442 | {X=0, Y=387, W=360, H=930} | `unix id=6371 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 360 | 0.8 | dark | 7000 | 47450 | {X=0, Y=385, W=360, H=934} | `unix id=7000 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 360 | 1.0 | light | 7311 | 47458 | {X=0, Y=385, W=360, H=934} | `unix id=7311 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 360 | 1.0 | dark | 8027 | 47464 | {X=1, Y=389, W=358, H=926} | `unix id=8027 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 360 | 2.0 | light | 8667 | 47472 | {X=0, Y=385, W=360, H=934} | `unix id=8667 ... nwin=1 nui=2` | 初期閉・全カード開 |
| 360 | 2.0 | dark | 9306 | 47480 | {X=0, Y=385, W=360, H=934} | `unix id=9306 ... nwin=1 nui=2` | 初期閉・全カード開 |

12 組とも helper は `swiftpm-testing-helper`。終了はクローズボタン `AXPress err=0`（`sub=AXCloseButton`）。終了後 `pgrep -x xctest` / `swiftpm-testing-helper`（自作業）/ `SessionFeaturePackageTests` なし。PID 61465 `/Applications/Phlox.app` 残存。

初期閉 AX（12 組共通、`disc_count=8`、すべて `value=False`）:

```
n=1 key=single desc=処理の詳細（1件）, 出力あり ident=Task46.singleCommandPath
n=2 key=reason-short desc=思考の詳細, 短い思考
n=3 key=reason-long desc=思考の詳細, 思考の本文を長く書いて折りたたみと展開を見る。…
n=4 key=group1 desc=処理の詳細（1件）, 出力あり ident=CommandGroupCell
n=5 key=group51 desc=処理の詳細（51件）, 出力あり ident=CommandGroupCell
n=6 key=diff desc=編集済み TranscriptItemPresentation.swift, +501, -0
n=7 key=task0 desc=タスク（0件） ident=ChatMessage.taskList
n=8 key=task2 desc=タスク（2件） ident=ChatMessage.taskList
```

回答・エラーは Disclosure なし。エラーは静的テキスト `エラー` / `a/**/b: error`。

全カード開後は 8 件とも `value=True`、`AXPress err=0`。

## PNG（既定組 720 / 1.0 / light）

撮影 `screencapture -o -l 47324`。論理 720×932、PNG 1440×1864（2x）。操作ログ `/tmp/phlox-t46-visual2/ops-720-1.0-light.log`。

| パス | 幅 | 倍率 | テーマ | 場面 | 操作 | AX 原文 |
|---|---|---|---|---|---|---|
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-initial-closed.png` | 720 | 1.0 | light | 初期閉（スクロールほぼ末尾） | なし | disc 8 件 value=False。ScrollBar before=0.9378 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-initial-closed-top.png` | 720 | 1.0 | light | 初期閉・先頭（回答） | AXScrollBar AXValue=0 | SCROLL err=0 after=0.0 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-single.png` | 720 | 1.0 | light | 単体コマンド開 | AXPress 単体 | err=0 AFTER value=True ident=Task46.singleCommandPath |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-closed-single.png` | 720 | 1.0 | light | 単体コマンド再閉 | AXPress | err=0 AFTER value=False |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-reason-short.png` | 720 | 1.0 | light | 思考短文開 | AXPress | err=0 AFTER value=True desc=思考の詳細, 短い思考 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-closed-reason-short.png` | 720 | 1.0 | light | 思考短文再閉 | AXPress | err=0 AFTER value=False |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-reason-long.png` | 720 | 1.0 | light | 思考長文開 | AXPress | err=0 AFTER value=True |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-closed-reason-long.png` | 720 | 1.0 | light | 思考長文再閉 | AXPress | err=0 AFTER value=False |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group1.png` | 720 | 1.0 | light | 1件グループ開 | AXPress | err=0 AFTER value=True ident=CommandGroupCell |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-closed-group1.png` | 720 | 1.0 | light | 1件グループ再閉 | AXPress | err=0 AFTER value=False |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group1-before-more.png` | 720 | 1.0 | light | 1件グループ開・追加前 | AXPress | value=True。出力 20 行まで |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group1-more-lines.png` | 720 | 1.0 | light | 1件グループ「さらに 1 行」直後 | AXPress btn `さらに 1 行を表示` ident=CommandGroupCell | err=0。末尾行はコンポーザに隠れ |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group1-scrolled.png` | 720 | 1.0 | light | 1件グループ開・スクロール | AXValue 0.12〜0.28 | 「さらに 1 行を表示」y=1122 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group1-more-lines-scrolled.png` | 720 | 1.0 | light | 20行追加後の 21 行目到達 | AXPress `さらに 1 行を表示` + scroll | err=0。PNG に output line 21 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group51.png` | 720 | 1.0 | light | 51件グループ開 | AXPress | err=0 AFTER value=True |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group51-more-rows.png` | 720 | 1.0 | light | 51件「残り 1 件を表示」 | AXPress btn `残り 1 件を表示` | err=0 ident=CommandGroupCell |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-group51-end.png` | 720 | 1.0 | light | 51件末尾 | AXScrollBar AXValue=1 | SCROLL err=0。末尾コマンド＋差分見出し |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-diff.png` | 720 | 1.0 | light | 差分開 | AXPress | err=0 AFTER value=True |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-diff-scrolled.png` | 720 | 1.0 | light | 差分スクロール | AXValue=1 | SCROLL err=0 before=0.0285 after=1.0 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-diff-more-lines-end.png` | 720 | 1.0 | light | 差分追加＋末尾 line501 | AXPress `さらに 4 行を表示` ident=FileChange.showMoreButton + scroll 1 | err=0。PNG に `501 + line501` |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-task0.png` | 720 | 1.0 | light | タスク空開 | AXPress | err=0 AFTER value=True desc=タスク（0件） |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-task2.png` | 720 | 1.0 | light | タスク非空開 | AXPress | err=0 AFTER value=True desc=タスク（2件） |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-error.png` | 720 | 1.0 | light | エラー（収納なし） | なし | 静的テキスト。Disclosure なし |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-all-open-top.png` | 720 | 1.0 | light | 全カード開・先頭 | open-all AXPress×8 + scroll 0 | 8 件 value=True、err=0 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-all-open-mid.png` | 720 | 1.0 | light | 全カード開・中程 | scroll 0.5 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-all-open.png` | 720 | 1.0 | light | 全カード開・末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-open-reason-short-before-replace.png` | 720 | 1.0 | light | 短文思考開（置換前） | AXPress | AFTER value=True |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-same-len-replace.png` | 720 | 1.0 | light | 同長置換 | AXPress ボタン「同長置換」 | err=0。開保持。desc=`思考の詳細, xxxx` value=True |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-blank-reasoning.png` | 720 | 1.0 | light | 空白 | AXPress 「空白」 | err=0。disc_count=7（短文カード消滅） |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-restore-reasoning.png` | 720 | 1.0 | light | 再表示 | AXPress 「再表示」 | err=0。reason-short value=False（再表示時は閉） |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-turn-start.png` | 720 | 1.0 | light | 実行開始（group1 開のまま） | AXPress 「実行開始」 | err=0。group1 value=True 保持 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-light-turn-end.png` | 720 | 1.0 | light | 実行終了 | AXPress 「実行終了」 | err=0。group1 value=True 保持 |

## PNG（残り 11 組。各組 初期閉・初期閉先頭・全開先頭・全開末尾）

各組とも初期 `value=False`×8、全開 `AXPress err=0` で `value=True`×8、クローズ `AXPress err=0`。

| パス | 幅 | 倍率 | テーマ | 場面 | 操作 | AX 原文 |
|---|---|---|---|---|---|---|
| `/tmp/phlox-t46-visual2/t46-720-1.0-dark-initial-closed.png` | 720 | 1.0 | dark | 初期閉 | なし | PID 11408 nwin=1 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-dark-initial-closed-top.png` | 720 | 1.0 | dark | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-dark-all-open-top.png` | 720 | 1.0 | dark | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-720-1.0-dark-all-open.png` | 720 | 1.0 | dark | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-light-initial-closed.png` | 720 | 0.8 | light | 初期閉 | なし | PID 10069 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-light-initial-closed-top.png` | 720 | 0.8 | light | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-light-all-open-top.png` | 720 | 0.8 | light | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-light-all-open.png` | 720 | 0.8 | light | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-dark-initial-closed.png` | 720 | 0.8 | dark | 初期閉 | なし | PID 10740 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-dark-initial-closed-top.png` | 720 | 0.8 | dark | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-dark-all-open-top.png` | 720 | 0.8 | dark | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-720-0.8-dark-all-open.png` | 720 | 0.8 | dark | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-light-initial-closed.png` | 720 | 2.0 | light | 初期閉 | なし | PID 12737 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-light-initial-closed-top.png` | 720 | 2.0 | light | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-light-all-open-top.png` | 720 | 2.0 | light | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-light-all-open.png` | 720 | 2.0 | light | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-dark-initial-closed.png` | 720 | 2.0 | dark | 初期閉 | なし | PID 2573 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-dark-initial-closed-top.png` | 720 | 2.0 | dark | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-dark-all-open-top.png` | 720 | 2.0 | dark | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-720-2.0-dark-all-open.png` | 720 | 2.0 | dark | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-light-initial-closed.png` | 360 | 0.8 | light | 初期閉 | なし | PID 6371 value=False×8。PNG 720×1864 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-light-initial-closed-top.png` | 360 | 0.8 | light | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-light-all-open-top.png` | 360 | 0.8 | light | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-light-all-open.png` | 360 | 0.8 | light | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-dark-initial-closed.png` | 360 | 0.8 | dark | 初期閉 | なし | PID 7000 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-dark-initial-closed-top.png` | 360 | 0.8 | dark | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-dark-all-open-top.png` | 360 | 0.8 | dark | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-360-0.8-dark-all-open.png` | 360 | 0.8 | dark | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-light-initial-closed.png` | 360 | 1.0 | light | 初期閉 | なし | PID 7311 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-light-initial-closed-top.png` | 360 | 1.0 | light | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-light-all-open-top.png` | 360 | 1.0 | light | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-light-all-open.png` | 360 | 1.0 | light | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-dark-initial-closed.png` | 360 | 1.0 | dark | 初期閉 | なし | PID 8027 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-dark-initial-closed-top.png` | 360 | 1.0 | dark | 初期閉先頭 | scroll 0 | ファイル名折り返し。タスク行がフレーム下端 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-dark-all-open-top.png` | 360 | 1.0 | dark | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-360-1.0-dark-all-open.png` | 360 | 1.0 | dark | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-light-initial-closed.png` | 360 | 2.0 | light | 初期閉 | なし | PID 8667 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-light-initial-closed-top.png` | 360 | 2.0 | light | 初期閉先頭 | scroll 0 | ユーザー吹き出し「単体グループ」が折り返し切れ |
| `/tmp/phlox-t46-visual2/t46-360-2.0-light-all-open-top.png` | 360 | 2.0 | light | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-light-all-open.png` | 360 | 2.0 | light | 全カード開末尾 | scroll 1 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-dark-initial-closed.png` | 360 | 2.0 | dark | 初期閉 | なし | PID 9306 value=False×8 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-dark-initial-closed-top.png` | 360 | 2.0 | dark | 初期閉先頭 | scroll 0 | SCROLL err=0 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-dark-all-open-top.png` | 360 | 2.0 | dark | 全カード開先頭 | open-all | AXPress err=0 value=True×8 |
| `/tmp/phlox-t46-visual2/t46-360-2.0-dark-all-open.png` | 360 | 2.0 | dark | 全カード開末尾 | scroll 1 | SCROLL err=0 |

合計 76 PNG。詳細ログ: `/tmp/phlox-t46-visual2/ops-720-1.0-light.log`、`/tmp/phlox-t46-visual2/combos-summary.json`、`/tmp/phlox-t46-visual2/ax-720-1.0-light-initial.txt`。

## 画素から読める初期閉（AX 値とは別。PM 判定用）

- 回答: 収納なし。「第一段落の回答本文。」「第二段落も常時読む。」
- 思考短: 「思考の詳細」／「短い思考」／閉
- 思考長: 「思考の詳細」／要約折り返し／閉
- 単体経路: 「処理の詳細（1件）」／「出力あり」／閉（VStack 先頭）
- 1件グループ: 同見出し／閉
- 51件グループ: 「処理の詳細（51件）」／閉
- 差分: 「編集済み TranscriptItemPresentation.swift +501 -0」／閉
- タスク: 「タスク（0件）」「タスク（2件）」／閉
- エラー: 「エラー」／本文 `a/**/b: error` は折りたたみ外
- 360×2.0 light 先頭: 吹き出し「単体グループ区切り」が折り返し切れ。狭い幅×大倍率の重なり・切れは PNG を見て判定する

## 契約「実装後の確認」項目

| 項目 | 実施 | 理由 |
|---|---|---|
| 回答・短文/長文思考・単体/グループコマンド・差分・空/非空タスク・処理中・構造化エラーの**初期閉の表示** | 実施 | 12 組の初期閉 PNG。処理中は窓表示前にハーネスが `.turnCompleted` 済み。実行中は既定組で「実行開始」後に撮影 |
| 初期閉のあと AX クリックで開 → 撮影 | 実施 | 12 組とも AXDisclosureTriangle へ AXPress err=0。value False→True |
| キーボード相当を AXPress で代替し記録 | 実施 | keystroke 禁止のため AXPress。開閉とハーネスボタン（同長置換・空白・再表示・実行開始/終了） |
| AX 値 expanded/collapsed | 実施（boolean） | AX 原文は `value=False`/`True`。文字列「展開中／折りたたみ中」は三角の AXValue には出ない |
| 同一 ID 更新中の開閉保持（同長置換・実行開始/終了） | 実施（既定組） | 同長置換後も短文が開（desc=`xxxx`, value=True）。group1 は実行開始/終了後も value=True |
| 思考の非空→空白→非空で再表示時は閉 | 実施（既定組） | 空白で disc_count=7。再表示後 reason-short value=False |
| コマンド表の単体／1件グループ | 実施 | 単体 ident=`Task46.singleCommandPath`、1件グループ ident=`CommandGroupCell`。展開内容は既定組 PNG |
| 500行／20行／50件の追加表示と末尾到達 | 実施（既定組） | `さらに 4 行を表示` 後 line501。`さらに 1 行を表示` 後 output line 21。`残り 1 件を表示` 後グループ末尾 |
| 幅360/720 × 倍率0.8/1.0/2.0 × 明/暗の 12 組 | 実施 | 12/12。各組最低 初期閉＋全カード開。狭い幅×2.0 の切れは PNG 判定 |
| Reduce Motion 下でも処理中が読める | 未検証 | ハーネスに Reduce Motion 切替が無い |
| 復元失敗プレースホルダ | 未実施 | 契約どおり補助経路。本ゲートでは再実行しない |

## 終了

各組ともクローズボタン AXPress（`windowWillClose` → `finishVisual`）。`pgrep -x xctest` none。`pgrep swiftpm-testing-helper`（本作業）none。`pgrep SessionFeaturePackageTests` none。PID 61465 `/Applications/Phlox.app` 残存。

合否は PM が PNG を確認して判定する。

=== REPORT COMPLETE ===

## PM 判定（2026-09-13、Claude PM が PNG を目視）

判定: **pass**。確認した PNG（/tmp/phlox-t46-visual2/）: 720/1.0/light の initial-closed-top・all-open-top・all-open-mid・all-open・open-diff-more-lines-end・open-group51-end・turn-start、360/2.0/dark all-open-top、360/0.8/light initial-closed-top、720/2.0/dark initial-closed-top、720/1.0/light の 12 組すべての initial-closed／all-open は担当の AX 記録（value False→True）で確認。

- 初期閉: 回答本文は常時表示、思考・単体/グループコマンド・差分・タスク（0 件／2 件）・エラーが見出し＋要約で閉、DisclosureTriangle の AX 値 False。
- 展開: 501 行差分は末尾 `501 + line501` へ到達、51 件グループは末尾まで Bash カードが並ぶ、20 行出力の追加表示、タスク 2 件（調査・実装、状態アイコン付き）、タスク 0 件は「タスクなし」、エラーは赤の意味色。
- 幅 360 × 倍率 2.0 × 暗: 見出し・要約が折り返し、切れ・重なりなし。幅 360 × 0.8 × 明: 縮小しても要約が読める。
- 観察（不合格ではない）: 長い要約を持つ「思考の詳細」は開閉シェブロンが右端に寄り、短い要約では見出し直後に付く（要約長で位置が変わる）。幅 360 ではコンポーザのラベルが「…」に畳まれる（既存挙動）。
- 未検証: 復元失敗プレースホルダ経路（契約どおり補助経路で本ゲート対象外）、Reduce Motion 下の処理中表示（ハーネスで切替不可）。
