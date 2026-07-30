---
status: accepted
last-verified: 2026-07-30
---

# ADR 0143: 活動状態のラベルにシマーを戻し、帯の純関数を共有モデルへ1本化する

> **このファイルの役割**: orb 移行（ADR 0142）で消えたシマーを、状態語のラベル側へ戻した理由と、
> プラットフォームごとの駆動方式を分けた理由。
> **書かないもの**: 帯形状の仕様（→ [ADR 0067](0067-thinking-wave-animation-and-viewport-pause.md)）、
> Core Animation 駆動にした理由（→ [ADR 0117](0117-thinking-shimmer-core-animation-driver.md)）。

## 文脈

ADR 0142 で Thinking 表示を点描 orb ＋ 状態語（"Searching..." 等）に置き換えたとき、
ラベルは静的テキストにした。結果として、それまで 3 面すべてにあった「明度帯が左→右へ流れる」
シマーが消えた。ユーザーの指摘は明確で、**orb は状態を伝えるが、テキストが静止すると
「生きている感じ」（処理が進んでいる手応え）が失われる**。ADR 0117 の時点でも同じ要望
（「シマーは残す」）でシマー廃止案は棄却されている。

シマーの純関数は当時 macOS `ThinkingAnimationModel.shimmer*` と iOS `DSThinkingAnimationModel` に
同じ式が二重にあり、0142 で iOS 側だけが削除された（macOS 側は圧縮中インジケータが使うため残存）。

## 決定

**orb は残したまま、隣の状態語にシマーをかける。帯の純関数は共有パッケージへ 1 本化する。**

- **`ShimmerBandModel`（`DesignSystem`）に純関数を集約する。** 余白 0.6・帯幅 0.22 は ADR 0067 の
  凍結値をそのまま移設した。実チャットでの目視を受けて 2 つだけ変えた（圧縮中インジケータも
  同じ値を共有するため一緒に変わる）:
  - **周期 1.6s → 2.0s**（速すぎた）
  - **下限明度 0.45 → 0.55**（ライトモードで下限側の文字が背景に溶けた）
- **基準色は secondary ではなく本文色（`chatTextPrimary` / `textPrimary`）を渡す。** 帯は基準色の
  不透明度を明度で変調する仕組みなので、secondary（ライトテーマでは本文色を 42% 背景へ混ぜた色）を
  基準にすると、下限 0.55 との積で本文色の 1/4 程度の濃さしか残らず読めない。本文色を基準にすると
  下限でちょうど secondary 相当の濃さになり、帯の頂点で本文色まで濃くなる＝陰影が濃く、かつ
  どの位相でも読める。
  macOS の `ThinkingAnimationModel.shimmer*` は削除し、圧縮中インジケータもこの共有モデルを使う。
  同じ式を二度持たない（0142 で立てた方針をシマー側にも適用する）。
- **`ShimmerTextView`（`DesignSystem`）を任意ラベル向けに一般化する。** 旧 `ThinkingShimmerView` は
  文字列 `"Thinking..."` を固定で持っていた。状態語は 6 通りに変わるため、text と実寸を引数に取る。
- **駆動方式はプラットフォームで分ける。**
  - macOS は Core Animation（`CATextLayer` マスク＋`CAGradientLayer` の並進）。ADR 0117 が実測した
    病理（`TimelineView(.animation)` が AttributeGraph とアクセシビリティ木を毎フレーム作り直し、
    グリッドでメインスレッドを ~24% 占有する）を再び持ち込まないため。旧実装の落とし穴
    （locations を 0…1 外へアニメしない・バンプを host 幅換算で評価する）もそのまま引き継ぐ。
  - iOS は `TimelineView(.animation)` ＋ `LinearGradient`（0142 以前の iOS 実装と同じ）。
    Dynamic Type の `Font` をそのまま活かせること、1 画面に 1 個しか出ないため上記の病理が
    問題にならないことによる。CATextLayer にすると実寸を自前で解決する必要があり、
    得るものより失うものが大きい。
- **ReduceMotion 時は静止テキスト**、`isVisible` が false の間はアニメーションを止める
  （macOS は `layer.speed = 0`、iOS はスケジュールを空にする）。ADR 0067 / 0117 と同じゲート。

## 結果

- 3 面（macOS チャットの Thinking セル・macOS ダッシュボードのアゴラ行・iOS セッション詳細）で
  orb ＋ シマーするラベルになった。
- `DSFont.bodyPointSize` と `ChatScaledFont.bodyPointSize(scale:)` を足した。`Font` からは実寸を
  取り出せないため、Core Animation 経路へ渡す値を明示する必要がある。
- 回帰保護: `ShimmerBandModelTests`（帯の凍結仕様。旧 `AcceptanceThinkingShimmerTests` /
  `ThinkingShimmerWhiteboxTests` の後継）と `ShimmerTextViewTests`（CA 駆動・非表示停止・
  locations∈[0,1]・host 幅換算バンプ・任意ラベル追従。旧 `AcceptanceThinkingShimmerViewTests` /
  `ThinkingShimmerViewWhiteboxTests` の後継）を `DesignSystemTests` に置いた。
- **正直な限界**: iOS 側の SwiftUI 経路は、パッケージのテストが macOS ターゲットで走るため
  ユニットテストでは AppKit 経路しか通っていない（コンパイルは iOS シミュレータ向けビルドで確認）。
  CPU の再計測はしていない（macOS の駆動方式は 0117 と同一のため）。
