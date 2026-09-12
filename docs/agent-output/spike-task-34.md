---
task: spike-task-34
status: completed
---
## 結果（合格変種の有無と最終の作業ツリー状態）

s1 / s2 / s3 のいずれも契約 4 条件を同時に満たさなかった。3 変種とも `row1 plus` AX 24×24・center/inner-* `popups=1`・outer-* `popups=0` は合格、**`row1 size` 高さはすべて 40（上限 36）**。`t34-s1-row1.png` / `t34-s2-row1.png` / `t34-s3-row1.png` の見出し＋と行の「…」「＋」の並びは r2 と区別がつかず、余白の崩れは無いが行そのものが 8pt 高い。

合格変種が無いため作業ツリーは **r2 構成に戻した**。`git diff` は着手時と同じ 2 Menu の差分（`.borderlessButton`+`.fixedSize()` → `.button`+`.plain`+`.controlSize(.mini)`+外側 `.frame(DSHitTarget.icon)`+`.contentShape`）。HStack への `.frame(height: 24)` は残していない。`docs/agent-output/task-34.md` はスパイク中に触っていない。台帳・契約・テスト・rb は未変更。Release Phlox（PID 61465）は未操作。隔離 Debug は各 `measure-t34.sh` 終了後に不在。key code 未使用。各変種の `swift build` と xcodebuild は **BUILD SUCCEEDED**。

## 各変種の差分と measure-t34.sh 原文

共通（label 側、3 変種とも維持）: `Image` に `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon)` + `.contentShape(Rectangle())`。`.menuIndicator(.hidden)` / `.help` / 省略記号の `.opacity(actionOpacity)` も維持。

### s1 — `.menuStyle(.button)` + `.buttonStyle(.plain)` + `.menuIndicator(.hidden)` + `.fixedSize()`（外側 frame / contentShape / controlSize なし）

Menu 修飾子:

```
.menuStyle(.button)
.buttonStyle(.plain)
.menuIndicator(.hidden)
.fixedSize()
```

```
pid=64939
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
terminated
```

判定: AX 24×24 OK / 端クリック OK / **row1 高さ 40 NG** / 撮影 `t34-s1-row1.png`（並びは r2 相当、行がセッション行より高い）

### s2 — s1 の `.fixedSize()` の後に外側 `.frame(width: DSHitTarget.icon, height: DSHitTarget.icon)`

Menu 修飾子:

```
.menuStyle(.button)
.buttonStyle(.plain)
.menuIndicator(.hidden)
.fixedSize()
.frame(width: DSHitTarget.icon, height: DSHitTarget.icon)
```

```
pid=68440
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
terminated
```

判定: AX 24×24 OK / 端クリック OK / **row1 高さ 40 NG** / 撮影 `t34-s2-row1.png`（s1 / r2 と目視差なし）

### s3 — Menu に `.frame(height: DSHitTarget.icon)`、HStack に `.frame(height: 24)`（padding 維持）

Menu 修飾子:

```
.menuStyle(.button)
.buttonStyle(.plain)
.menuIndicator(.hidden)
.frame(height: DSHitTarget.icon)
```

HStack 直後（計測時のみ。復元時に削除）: `.frame(height: 24)` → 既存 `.padding(.horizontal/.vertical)` は維持。

```
pid=73049
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
terminated
```

判定: AX 24×24 OK / 端クリック OK / **row1 高さ 40 NG** / 撮影 `t34-s3-row1.png`（HStack 高さ固定でも行は視覚的に縮まない）

## 考察（行高 40 の原因、次に試す価値のある案）

**原因（実測から）:** `.menuStyle(.button)` の AppKit コントロール固有高が List/outline の行高を決めている。AX 枠（24×24）と行の fittingSize は別系統。HEAD（`.borderlessButton` + `.fixedSize()`）は row 32。`.button` 系は r2 / r3 / r4 / s1 / s2 / s3 のすべてで 40。差は常に +8pt。垂直 padding は HEAD から `DSSpacing.xs`×2＝8 で不変なので、「padding を足した」のではなく **Menu(.button) の最小高が borderless より約 8pt 高い（固有高 ~32 + padding 8 = 40）**。`.controlSize(.mini)`（r2）も `.fixedSize()`（s1）も、その後の外側 `.frame(24)`（s2）も、HStack `.frame(height: 24)`（s3、理論上 24+8=32）も **行高を 1pt も動かさない**。s3 が最有力の反証で、SwiftUI 側の提案サイズは NSOutlineView が見る Menu NSView の圧縮を拒否している。

**次に試す価値がある案（優先順）:**

1. **垂直 padding を `xs`(4×2=8) → `xxs`(2×2=4) または 0。** Menu(.button) 固有高 ~32 が動かない前提なら 36 ちょうど、または 32。AX と端クリックは既に合格なので、高さだけ契約側で padding 変更を許せば最短。見た目の行密度は変わる。今回の許容範囲外。
2. **`Menu` をやめて `Button` + `HoverableIconButtonStyle`（見出し＋と同じ経路）でメニューを出す**（`confirmationDialog` / popover / プログラム `NSMenu`）。行高 32 のまま AX 24 が取れる見込みが最も高い。契約の Menu 維持と衝突しうる。
3. **24×24 の `NSViewRepresentable`（borderless NSButton の pull-down）。** AppKit で高さを直接固定する。Menu 置換。
4. **ヒットだけ別 Button に移し、見た目の Menu は `.borderlessButton` のまま**（r3 は Menu 自身の端クリックが NG）。行高は HEAD の 32 に戻る見込み。配線が複雑。
5. **価値が低い:** `.controlSize` の Environment 伝播、overlay+clipped（r4 済）、`.menuStyle(.borderlessButton)` の外側 frame だけ（r3 済、端クリック NG）。同じ SwiftUI 修飾子の並べ替えでは行高 40 は動かない、というのが今回の結論。

=== REPORT COMPLETE ===
