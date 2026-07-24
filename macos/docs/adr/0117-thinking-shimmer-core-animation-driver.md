---
status: active
last-verified: 2026-07-24
---

# ADR-0117: Thinking シマーを Core Animation 駆動へ移し、グリッドの毎フレーム AttributeGraph／アクセシビリティ木再構築を根絶する

## ステータス

採択・実装済み（agent-grid-jank run / task-1）。ADR 0067 が定義した Thinking シマーの**駆動方式のみ**を、SwiftUI `TimelineView`（30fps）から Core Animation 駆動の `NSViewRepresentable`（`ThinkingShimmerView`）へ置換する。シマーの純関数仕様（`ThinkingAnimationModel.shimmerPhase`/`shimmerBrightness`/`shimmerBandCenter`）と reduceMotion 静止経路は不変。ADR 0116（`.appServer` グリッドの live-resize カクつき＝CoreAnimation Commit 停滞）とはスコープが別問題——0116 はリサイズ時の折返し計算、本 ADR は**定常状態**でシマーがメインスレッドを占有する経路を扱う。手本は ADR に未起票だが実在する `RunningBlinkDot`（DesignSystem、SwiftUI repeat-forever 回避のため CA 化済み）。

## コンテキスト

### 問題（実測で確定）

複数セッションをグリッド表示すると CPU が暴走・スタックする。非破壊 `sample`（本番アプリ）で、**メインスレッドの約半分（4106 中 2029 サンプル）が `AccessibilityViewGraph.postUpdate`＝SwiftUI がアクセシビリティのノード木を毎フレーム作り直す**処理に費やされていた。駆動源は `ThinkingIndicatorCell` の **`TimelineView(.animation)`（30fps）**であり、**文字ストリーミングではなくアニメのタイマー**が発生源＝出力が止まっても回り続ける（スタックの正体）。グリッドではタイルごとに独立して回るため N 倍化する。ADR 0067 の設計（純関数＋TimelineView＋LinearGradient mask）は CPU ハザードを純関数化で避けたが、**TimelineView 自体が SwiftUI の依存グラフ（AttributeGraph）とアクセシビリティ木を毎フレーム再評価させる**点は残っていた。

### なぜ「シマーを消す」ではなく「駆動方式を変える」か

重いのはシマーの見た目ではなく「SwiftUI に毎フレーム再描画・木再構築させる駆動方式」。同じ見た目を描画サーバー側（Core Animation）で回せば、SwiftUI の毎フレーム更新はゼロになる。ユーザー要望は「シマーを残す」。

## 決定

1. **`ThinkingShimmerView: NSViewRepresentable`（新規・`SessionFeature`）を導入**し、`ThinkingIndicatorCell` のシマー（アニメ）経路の `TimelineView` を置換する。旧 private 関数 `shimmeringThinkingText(scale:date:)`（毎フレーム 21 stop の `LinearGradient` を生成）は削除。
2. **駆動は Core Animation**: `CATextLayer("Thinking...")` を固定マスクにし、その下で `CAGradientLayer`（色＝`DSColor.chatTextSecondary` を明度で不透明度変調した明度バンプ）を `CABasicAnimation`（`position.x`、周期 `shimmerPeriod`、`repeatCount=.infinity`、linear）で左端外→右端外へ並進させる。アニメは `makeNSView` 時に一度だけ追加し、以降 SwiftUI の再評価に依存せず描画サーバー側で自律的に回る。`updateNSView` は色・フォントスケール・可視性の**離散変化のみ**反映（毎フレーム発火させない＝病理を持ち込まない）。
3. **帯形状は凍結純関数を再利用**: 明度バンプは `ThinkingAnimationModel.shimmerBrightness`/`shimmerBandCenter` から算出（ADR 0067 の契約・`AcceptanceThinkingShimmerTests` 凍結を維持）。
4. **可視性ゲートを CA でも担保**: `isTimelineVisible`（viewHierarchy && transcriptViewport && sceneActive、ADR 0067/0094 と同じシグナル）を `isVisible` として渡し、false で `layer.speed=0`（pause）、true で resume。retain cycle 回避のため delegate は使わない（`RunningBlinkDot` と同じ規律）。
5. **アクセシビリティは単一の安定ラベル**: SwiftUI ラッパーに `.accessibilityLabel("Thinking...")` + `.accessibilityElement(children: .ignore)` を付け、下層 CA は木を持たない（毎フレーム木再構築を根絶）。
6. **reduceMotion 静止経路は不変**。Compacting/Connecting インジケータ（同じ Timeline/Canvas 病理を持つ）は本 run のスコープ外（既知の後続候補）。

## 実装上の落とし穴（レビューで検出・回避済み）

- **`CAGradientLayer.locations` に `0…1` 外の値をアニメしない**: 初版は locations を `-1.1…2.1` へ動かして帯を掃引したが、Apple 仕様上 `0…1` 外は未定義で、オフスクリーン `render(in:)` 経路では大半のフレームが**空描画**になる（実測）。→ locations は固定 `[0,1]` 昇順にし、帯移動は勾配レイヤーの**並進**で行う。並進の全区間で勾配がホスト全域を覆うよう勾配幅を `2 + 2·shimmerMargin`（host 幅倍）とする。
- **明度バンプを勾配全幅に張らない**: 被覆のため勾配は host 幅の `2+2·margin` 倍あるので、バンプ（bandWidth 0.22）を勾配全幅へ張るとシマー帯が約 3.2 倍に広がり、テキスト全体がほぼ均一に光ってコントラストが失われる（実測: 帯中央で端明度 0.87 vs 原実装 0.49）。→ stop 明度は勾配内位置ではなく **host 幅換算位置** `0.5 + (location − 0.5)·widthInHostWidths` で凍結 falloff を評価し、バンプを原寸（host 幅ぶん）に保つ。

## 棄却した代替案

- **シマーを消して静止「Thinking…」にする**: ユーザー要望（シマー維持）に反する。棄却。
- **TimelineView の間引きをさらに緩める（30→7fps 等）**: 病理（毎フレーム木再構築）は残り、駆動頻度を下げるだけの対症療法。棄却。
- **`CAGradientLayer.locations` を `0…1` 外へアニメして掃引**: 未定義動作・`render(in:)` で空描画（上記）。棄却。

## 結果・残余

- **前後比較 CPU 実測（隔離ハーネス・3×3=9 枚・駆動方式のみ差異、sample/ps）**: 旧（TimelineView×9）＝メインスレッド **~24% 持続** ＋ `AG::Graph::UpdateStack::update`／CoreText 毎フレーム再描画。新（Core Animation×9）＝メインスレッド **0.0%**（`mach_msg`/CFRunLoop 待機、AttributeGraph 更新なし）。シマー駆動のメインスレッド負荷を **~24% → ~0%** へ。
- 凍結受け入れ `AcceptanceThinkingShimmerViewTests`（SessionFeature、PM 著）が CA アニメの周期＝`shimmerPeriod`・無限反復・非表示停止・帯明度の凍結 falloff 由来・色追従・毎フレーム勾配ビルダー除去を符号化。白箱 `ThinkingShimmerViewWhiteboxTests` が locations∈[0,1]・被覆不変条件・host 幅換算バンプを回帰ガード。SessionFeature 328 tests / 44 suites・DashboardFeature 凍結純関数 12 tests 全 pass。アプリ Debug 統合ビルド BUILD SUCCEEDED。
- **正直な限界**: CPU は隔離ハーネスの n=1 点推定（絶対値は本番アプリの旧 68% とは異なる）。シマー描画自体は描画サーバー側（WindowServer/GPU）へ移動しており、その負荷は別途・未計測（ただしアプリのメインスレッド占有＝グリッド飢餓の原因は解消）。
- **既知の残余（スコープ外の後続候補）**: 同じ 30fps 病理を持つ `CompactingIndicatorCell`（`ThinkingAnimationModel.timelineSchedule` 共有）と `ChatConnectingIndicator`（`TimelineView(.animation)`・Canvas レーダー）は未対処。同じ CA 化パターンを横展開できる。ADR 0116（live-resize 幅固定）とは独立トラック。
