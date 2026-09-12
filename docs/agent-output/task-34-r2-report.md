---
task: task-34
status: partial
---
## 詰まった / 完了できなかった点

契約 4 条件のうち **row 1 高さ ≤ 36pt を満たせなかった**。実測 3 回とも `row1 size` の高さは **40pt**（着手前 32pt＋4 の上限 36 を超過）。AX 枠 24×24 と 24pt 枠内端クリックは r2 / r4 で合格したが、行高と同時には成立しなかった。試行上限 3 回に達した。

機械検証（配線・DesignSystem 全数・DashboardFeature / SessionFeature ビルド）は最終成果物で exit 0。隔離 Debug の xcodebuild も毎回 **BUILD SUCCEEDED**。Release Phlox（PID 61465）は未操作。key code 未使用。

## できた風だが実は未完（最重要）

- **AX 24×24 と端クリック合格を「完了」と読むと誤り。** r2 / r4 は `row1 plus` 24×24、center / inner-* `popups=1`、outer-* `popups=0` だが、行高 40pt のままなので契約は未達。
- **`.controlSize(.mini)` は行高を下げない。** r2 で付与しても `row1 size` は 40 のまま。AppKit 側 Menu の固有高（レイアウト上 ~32）＋ `padding(.vertical, DSSpacing.xs)` 8pt が 40 になる、という読みと整合する。
- **`.menuStyle(.borderlessButton)` ＋外側 `.frame(24).contentShape` ＋ `.fixedSize()` 削除（r3）は AX だけ 24×24 になる。** 押せる範囲は中心のみ（inner-* が全て `popups=0`）。差し戻し 1 回目の「label frame が押せる範囲に反映されない」が、`.fixedSize()` を外しても **ヒットテスト側では残る**。
- **`Color.clear.frame(24).overlay { Menu }.clipped()`（r4）も行高 40 のまま。** SwiftUI 親の提案サイズを 24 にしても、List / outline の行高は Menu の NSView 固有高に引っ張られる。見た目の余白は r2 と区別がつかず、構造だけ増えるので **成果物からは overlay を外し、実測済みの r2 構成を残した**（4 条件の合否は r2 と同一）。
- 余白リズム（`t34-r2-row1.png` / `t34-r3-row1.png` / `t34-r4-row1.png`）は見出し＋と行の「…」「＋」の並び自体は保たれているが、行高 40pt なので「増分 4pt 以内」は未達。

## 置いた前提・仮定

- 成果物は r2 構成: `ProjectSidebarHeader` の 2 つの `Menu` に `.menuStyle(.button)` + `.buttonStyle(.plain)` + `.controlSize(.mini)` + `.menuIndicator(.hidden)` + 外側 `.frame(DSHitTarget.icon)` + `.contentShape(Rectangle())`。label 側の `.frame(DSHitTarget.icon)` / グリフ `DSIconSize.s` / `help` / 省略記号の `opacity(actionOpacity)` は維持。
- r4 の overlay は計測後に破棄した。残コードは r2 実測と対応する。
- `.buttonStyle(.plain)` のため `HoverableIconButtonStyle` の hover 面はこれらの Menu には乗っていない。着手前 HEAD（`borderlessButton` + `.fixedSize()`）にも同スタイルは無かった。省略記号は hover 時 `opacity` のみ。
- 行高 40 の内訳は未計装の仮定: Menu のレイアウト高 ~32 + 垂直 padding 8。AX 枠 24 とレイアウト固有高は独立。
- `measure-t34.sh` の click 判定（自 PID の layer>0 ウィンドウ数）と AX `help` 検索を、契約の端クリック／AX size の一次信号として用いる。
- 配線検査の `.contentShape(Rectangle())` 増加は基準以上で許容（差し戻し 1 回目）。`help` / `focusable` 等は基準同数。

## 契約からの逸脱

- **成功基準 3 の行高:** row 1 が 40pt で、契約の「36pt 以下」を満たさない。allowed_paths 内・3 試行では、AX 24×24・端クリック・行高 36 以下を同時に満たす構成に到達しなかった。
- padding / `DSSpacing` / List の `listRowInsets` / `Menu` 自体の置換（NSViewRepresentable 等）は契約例に無く、余白リズム維持と衝突しうるため手を出していない。
- overlay 試行は契約例の「外側 frame + clipped」の延長。行高が変わらなかったため成果物には残していない。

## 実測（measure-t34.sh 原文・全試行）

### r2（`.menuStyle(.button)` + `.buttonStyle(.plain)` + `.controlSize(.mini)` + 外側 frame 24）— 成果物と同一

```
pid=35082
mode buttons size: 30, 24
header plus size: 24, 24
row1 elements: ボタン, ボタン, テキスト, メニューボタン, メニューボタン row1 elements: 折りたたむ, このプロジェクトを選択, このプロジェクトを選択, プロジェクト操作, このプロジェクトで新規セッションを開始 row1 elements: 16, 16, 16, 16, 135, 16, 24, 24, 24, 24
row1 plus {pos,size}={545, 256, 24, 24}
center click(557.0,268.0) -> popups=1
inner-left click(546.0,268.0) -> popups=1
inner-top click(557.0,257.0) -> popups=1
inner-right click(568.0,268.0) -> popups=1
inner-bottom click(557.0,279.0) -> popups=1
outer-left click(544.0,268.0) -> popups=0
outer-top click(557.0,255.0) -> popups=0
row1 more {pos,size}={513, 256} row1 more {pos,size}={24, 24}
row1 size: 280, 40
still-running
```

判定: AX 24×24 OK / 端クリック OK / **row1 高さ 40 NG** / 撮影 `t34-r2-row1.png`

### r3（`.menuStyle(.borderlessButton)` + 外側 frame 24 + contentShape、`.fixedSize()` なし）

```
pid=42234
mode buttons size: 30, 24
header plus size: 24, 24
row1 elements: ボタン, ボタン, テキスト, メニューボタン, メニューボタン row1 elements: 折りたたむ, このプロジェクトを選択, このプロジェクトを選択, プロジェクト操作, このプロジェクトで新規セッションを開始 row1 elements: 16, 16, 16, 16, 135, 16, 24, 24, 24, 24
row1 plus {pos,size}={545, 256, 24, 24}
center click(557.0,268.0) -> popups=1
inner-left click(546.0,268.0) -> popups=0
inner-top click(557.0,257.0) -> popups=0
inner-right click(568.0,268.0) -> popups=0
inner-bottom click(557.0,279.0) -> popups=0
outer-left click(544.0,268.0) -> popups=0
outer-top click(557.0,255.0) -> popups=0
row1 more {pos,size}={513, 256} row1 more {pos,size}={24, 24}
row1 size: 280, 40
still-running
```

判定: AX 24×24 OK / **端クリック NG（中心以外 popups=0）** / **row1 高さ 40 NG** / 撮影 `t34-r3-row1.png`

### r4（r2 相当 Menu を `Color.clear.frame(24).overlay` + `.clipped()` で包む）— 計測後に破棄

```
pid=49779
mode buttons size: 30, 24
header plus size: 24, 24
row1 elements: ボタン, ボタン, テキスト, メニューボタン, メニューボタン row1 elements: 折りたたむ, このプロジェクトを選択, このプロジェクトを選択, プロジェクト操作, このプロジェクトで新規セッションを開始 row1 elements: 16, 16, 16, 16, 135, 16, 24, 24, 24, 24
row1 plus {pos,size}={545, 256, 24, 24}
center click(557.0,268.0) -> popups=1
inner-left click(546.0,268.0) -> popups=1
inner-top click(557.0,257.0) -> popups=1
inner-right click(568.0,268.0) -> popups=1
inner-bottom click(557.0,279.0) -> popups=1
outer-left click(544.0,268.0) -> popups=0
outer-top click(557.0,255.0) -> popups=0
row1 more {pos,size}={513, 256} row1 more {pos,size}={24, 24}
row1 size: 280, 40
still-running
```

判定: AX 24×24 OK / 端クリック OK / **row1 高さ 40 NG**（overlay 無効） / 撮影 `t34-r4-row1.png`

各試行の `still-running` は `kill -TERM` 直後 2 秒のスクリプト出力。終了確認後に Debug は不在、Release 61465 は生存。

## レビュー重点（PM 用）

- 4 条件同時成立は 3 試行で未達。残コードは「AX と端クリックは合格、行高 40」の r2。completed にしない。
- macOS の SwiftUI `Menu`（`.button` / `.borderlessButton` とも）は、AX 枠 24 と List 行のレイアウト固有高 ~32 が分離している。行高を 36 以下にするには、契約の拡大（行高上限の見直し、垂直 padding / `listRowInsets` の変更許可、または Menu 以外のヒットターゲット実装）が必要に見える。
- r3 は「AX size だけ見て押せる範囲合格」と誤読しやすい。inner-* が全て 0。
- `.buttonStyle(.plain)` による hover 面の欠落を Rubric「HoverableIconButtonStyle と同等」で落とすかどうか。HEAD のこれらの Menu にも同スタイルは無かった。
- 配線・凍結テストは green。未達は PM 目視ゲートの行高だけ。

=== REPORT COMPLETE ===
