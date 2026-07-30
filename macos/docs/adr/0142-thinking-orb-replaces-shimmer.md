---
status: accepted
last-verified: 2026-07-30
---

# ADR 0142: Thinking 表示を点描 orb に置き換え、活動状態を transcript から導出する

> **このファイルの役割**: 「Thinking...」のシマー表示を点描 orb（thinking-orbs の Swift 移植）へ置き換えた理由と、
> 6 状態をどこから導出するかの決定理由。
> **書かないもの**: 現行の描画モジュール構成（→ [architecture/overview.md](../architecture/overview.md)）、
> ライセンス表記（→ [THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md)）。

## 文脈

実行中の表示は 3 面あり、いずれも「Thinking...」の 1 種類しか出せなかった。

- macOS チャットの Thinking セル（`ThinkingShimmerView`＝ADR 0117 の Core Animation 駆動シマー）
- macOS ダッシュボードのアゴラ行（静的テキスト＋点滅ドット）
- iOS セッション詳細（`DSThinkingIndicator`＝TimelineView のシマー）

エージェントは実際には「読んでいる／実行している／書き換えている／回答を書いている／人間の応答を待っている」
と質の違う時間を過ごしているのに、表示は全部同じだった。待っているのが自分なのかエージェントなのかも読めない。

[thinking-orbs](https://github.com/Jakubantalik/thinking-orbs)（MIT）は 6 状態それぞれに専用の点描アニメーションを持つ。
ただし React + Canvas 2D の Web パッケージで、Phlox は macOS / iOS とも完全ネイティブ（WKWebView をどこにも使っていない）。

## 決定

**エンジンを Swift/CoreGraphics へ移植し、6 状態を transcript から導出して両アプリの Thinking 表示を置き換える。**

- **WebView で埋め込まない。** ADR 0117 は「シマーで SwiftUI の表示木を再評価させない」ために
  Core Animation 駆動へ移した経緯があり、そこへ WebView を持ち込むのは逆行する。移植なら
  同じ「SwiftUI の外で毎フレーム描く」構造を保てる。
- **描画は共有パッケージ `DesignSystem` に 1 本だけ置く。** iOS の `PhloxKit` は
  `macos/Packages/{AgentDomain,DesignSystem}` を SSOT として参照済み（ADR 0001）。
  `ThinkingOrbView` は AppKit / UIKit で下層ビューだけを分岐し、点群を作る純関数
  （`OrbModeRenderer`）と調整値（`OrbPresets`）はプラットフォーム非依存で共有する。
  シマー時代は macOS と iOS で位相計算を二重に持っていた（`ThinkingAnimationModel` と
  `DSThinkingAnimationModel`）。同じ二重化を繰り返さない。
- **アニメーションは display link で回し、SwiftUI の状態を触らない。** ADR 0117 と同じ方針。
  非表示のとき（transcript の最下部が viewport 外・シーン非アクティブ）は display link を止め、
  ReduceMotion 時は代表フレーム 1 枚だけを描く。
- **状態はドメインの `AgentActivityState` として `AgentDomain` に置き、transcript から純関数で導出する。**
  UI の enum にしない。macOS の `ChatItem` 列と iOS の `ChatMessage` 列は別型なので、走査だけは
  各プラットフォーム（`ChatRecap` / `ChatRecapIOS`）に置き、分類規則（読み取り系ツール名の集合、
  待機状態の判定）は `AgentActivityClassifier` に集約して両者が同じ答えを返すようにする。

導出規則（recap と同じく最後のユーザー入力以降だけを見る。最後に現れた項目が勝つ）:

| 状態 | 出どころ | 表示語 | orb のモード |
|---|---|---|---|
| `waiting` | `status` が `awaitingApproval` / `awaitingUserQuestion` | Waiting... | wave |
| `searching` | 直近が読み取り系ツール（Read / Grep / Glob / WebSearch / `rg` / `cat` …） | Searching... | globe |
| `running` | 直近がそれ以外のコマンド実行・サブエージェント | Running... | rubik |
| `editing` | 直近が `fileChange` | Editing... | morph |
| `writing` | 直近が `agentMessage`（回答本文の出力中） | Writing... | ribbon |
| `thinking` | 直近が `reasoning`、または該当なし | Thinking... | orbits |

ツール名は既存の表示用コマンド文字列の先頭トークン（`"Read /path"`・`"Grep pattern"`）から取る。
専用のツール名フィールドを ChatItem に足していない ＝ ワイヤと保存形式を変えずに済む。

## 結果

- 3 面すべてが同じ規則で状態を出し分ける。`waiting` だけは処理中でなくても出すため、
  Thinking セルの表示ゲートに `isAwaitingUser` を足した（`showsProcessingIndicator` 自体は変えていない。
  composer など他の表示面の意味を動かさないため）。
- シマー実装は役目を終えたので削除した: `ThinkingShimmerView`（macOS）、`DSThinkingAnimationModel`（iOS）、
  アゴラ行の点滅ドット。ADR 0117 の判断（＝アニメーションを SwiftUI の外で回す）自体は本 ADR が引き継ぐ。
  なお macOS の圧縮中インジケータは同じシマー純関数（`ThinkingAnimationModel.shimmer*`）を使い続けるため、
  そちらは残している。
  > **訂正**（2026-07-30・[ADR 0143](0143-activity-label-keeps-shimmer.md)）: ラベルを静的テキストにしたのは誤りだった。
  > シマーは**状態語のラベル側に戻した**（orb はそのまま）。共有の `ShimmerTextView` / `ShimmerBandModel`
  > （`DesignSystem`）が後継で、`ThinkingAnimationModel.shimmer*` は共有モデルへ移して削除済み。
- 移植元は MIT。`THIRD_PARTY_NOTICES.md` に「Ported source」節を起こして帰属を記載した。
- 調整値（各モードの点数・半径・速度）は原実装の数値をそのまま持ち込んでいる。見た目を変えたいときは
  `OrbPresets` の 1 か所だけを触ればよい。
