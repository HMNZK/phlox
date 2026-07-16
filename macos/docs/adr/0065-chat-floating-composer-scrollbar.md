---
status: active
last-verified: 2026-07-10
---

# ADR 0065: チャット入力欄をフローティング化し、スクロール逃し余白はコンテンツ内スペーサーで確保する

> **このファイルの役割**: 「スクロールバーが最下部で画面右下端に届かない」修正で、safeAreaInset 案・contentMargins 案を棄却しフローティング入力欄＋コンテンツ内スペーサーに至った決定と macOS 固有の実挙動の記録。
> **書かないもの**: 現行のレイアウト構成（→ architecture/chat-mode-ux-components.md）。

## 文脈

チャットのスクロールバーは入力欄（composer）上端で止まり、ユーザー要求「最下部時はバーが画面右下端に届く」を満たせなかった。macOS の SwiftUI では次の2手段がいずれも**スクロールインジケータごとインセット**することを実機で確認した（ユニットテスト・静的検査では検出不能）:

1. `safeAreaInset(edge: .bottom)`（task-3 の初回実装）— バーのトラックが inset 上端で終わる。
2. `contentMargins(.bottom, h, for: .scrollContent)`（task-6 の初回実装）— API 上は「コンテンツのみ」の placement だが、macOS ではオーバーレイスクローラも h ぶんインセットされた（実測: つまみ終端＝ウィンドウ下端− composer 高）。

## 決定

- composer は ScrollView の**兄弟でも safeAreaInset でもなく `.overlay(alignment: .bottom)`** で浮かせ、ScrollView 自体はカラム全高（画面下端）を占める。
- 最下部でコンテンツが composer に隠れないための逃し余白は、**スクロールコンテンツ内部の末尾スペーサー**（`chat-bottom` アンカー兼用・高さ= composer 実測高）で確保する。コンテンツ内スペーサーはスクローラ形状に影響しない。
- composer 高さの計測は `onGeometryChange` → `@State` → スペーサー高さの**一方向**（ADR 0030 の規律）。計測値を composer 自身のサイズ決定へ戻さない。
- composer の**全幅不透明背景（周囲余白帯の塗り）は撤去**し、パネル本体（角丸矩形）だけを不透明にする。副作用として、スクロール途中はメッセージがパネル周囲余白の背後を通過して見える（フローティング入力欄の見た目）。この副作用はユーザーへ提示し承認を得た。

## 棄却案

- **safeAreaInset(bottom) の維持**: 実機でバーが届かない（上記1）。棄却。
- **contentMargins(.scrollContent)**: 同上（上記2）。API の宣言と macOS 実挙動が乖離。棄却。
- **現状維持（バーは入力欄上端まで）**: ユーザーへ選択肢として提示し、フローティング化が選ばれた。

## 結果

- 実機（Debug）で、つまみのウィンドウ右下端到達・最下部コンテンツ非隠蔽・CPU 0.0〜0.3% 収束を確認（2026-07-10）。
- 残余: 自動追従のアンカーはスペーサー下端基準（`scrollTo("chat-bottom", anchor: .bottom)`）。スペーサー高が 0 の初回フレームは一瞬コンテンツが composer 下に潜り込みうる（計測反映後に収束・知覚困難）。
