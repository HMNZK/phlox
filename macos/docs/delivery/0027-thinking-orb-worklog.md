---
status: completed
last-verified: 2026-07-30
---

# 0027: Thinking 表示の点描 orb 化 worklog

「Thinking...」のシマー表示を、thinking-orbs（MIT・Web/Canvas 2D）の Swift 移植による点描 orb へ置き換え、
実行中の活動を 6 状態で出し分けるようにした。決定理由は **ADR 0142**。

## 成果物

- **移植エンジン（共有）** `macos/Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb/`
  - `ThinkingOrbCore.swift`（決定論ハッシュ・フィボナッチ格子・射影・z ソート塗り）
  - `ThinkingOrbProfiles.swift`（基本プロファイル・個数/半径スケール・(状態,サイズ)プリセット解決）
  - `ThinkingOrbModes.swift`（orbits / globe / rubik / wave / ribbon / morph の点群生成）
  - `ThinkingOrbView.swift`（AppKit/UIKit 共用。display link 駆動・非表示で停止・ReduceMotion で静止）
  - `ThinkingOrbState.swift`（`AgentActivityState` → モード・表示ラベル）
- **ドメイン（共有）** `macos/Packages/AgentDomain/Sources/AgentDomain/AgentActivityState.swift`
  （6 状態と `AgentActivityClassifier`＝読み取り系ツール名の集合・待機状態の判定）
- **導出（各プラットフォーム）** `ChatRecap.deriveActivityState`（macOS）/ `ChatRecapIOS.deriveActivityState`（iOS）
- **表示面 3 つ**
  - macOS チャット `ThinkingIndicatorCell`（＋サブエージェントドロワー）
  - macOS ダッシュボード `AgoraThinkingIndicatorRow`
  - iOS セッション詳細 `DSThinkingIndicator`
- **削除（本変更で孤児化）**: `ThinkingShimmerView`（macOS）とその白箱/受け入れテスト、
  DashboardFeature 側のシマー純関数テスト、`DSThinkingAnimationModel`（iOS）とその受け入れテスト、
  アゴラ行の点滅ドット（`AgoraThinkingDots` / `AgoraThinkingDotsAnimation`）。
  macOS の圧縮中インジケータが使う `ThinkingAnimationModel.shimmer*` は**残存**。
- **帰属**: `THIRD_PARTY_NOTICES.md` に「Ported source」節を追加（MIT / Jakub Antalik）。

## 状態スナップショット（検証）

実走したもの（すべて pass）:

| 対象 | 結果 |
|---|---|
| `macos/Packages/DesignSystem` | 89 tests / 20 suites pass（うち orb 13 件を新規追加） |
| `macos/Packages/AgentDomain` | 240 tests / 11 suites pass（うち分類 6 件を新規追加） |
| `macos/Packages/SessionFeature` | 723 tests / 76 suites pass（うち活動状態 9 件を新規追加） |
| `macos/Packages/DashboardFeature` | 1484 tests / 138 suites pass |
| `ios/Packages/PhloxKit`（`make test`） | 643 tests / 123 suites pass（うち活動状態 8 件を新規追加） |
| macOS アプリ Debug ビルド | BUILD SUCCEEDED |
| iOS シミュレータ向け `Features` ビルド | BUILD SUCCEEDED |

視覚確認: 6 状態 × 2 サイズをオフスクリーン描画して目視（orbits の粒子・globe の走査・rubik の帯回転・
morph の円→三角ブレンド・ribbon の帯・wave の波が原実装どおり出ることを確認）。

## 追補: 状態語のシマー復帰（同日・ADR 0143）

デバッグ版での目視で「シマーが無くなった」ため、orb は残したまま状態語のラベルにシマーを戻した。

- **追加（共有）** `macos/Packages/DesignSystem/Sources/DesignSystem/Shimmer/`
  - `ShimmerBandModel.swift`（帯の純関数。ADR 0067 の凍結値を移設。目視を受けて周期 1.6s → 2.0s、
    下限明度 0.45 → 0.55 へ変更。基準色も secondary → 本文色に変え、ライトモードでの可読性を確保）
  - `ShimmerTextView.swift`（任意ラベル対応。macOS は Core Animation 駆動、iOS は TimelineView + LinearGradient）
- **移設・削除**: `ThinkingAnimationModel.shimmer*`（macOS）を削除し、圧縮中インジケータは
  `ShimmerBandModel` を使う。`DSFont.bodyPointSize` / `ChatScaledFont.bodyPointSize(scale:)` を追加。
- **表示面 3 つ**（チャットの Thinking セル・アゴラ行・iOS セッション詳細）を `ShimmerTextView` へ差し替え。
- 追加検証（すべて実走・pass）: DesignSystem 110 tests / 22 suites（シマー 21 件を新規追加）、
  SessionFeature 723、DashboardFeature 1484、iOS PhloxKit 643、macOS アプリ Debug ビルドと
  iOS シミュレータ向け `Features` ビルドは BUILD SUCCEEDED。
- 視覚確認: シマーの帯が乗ったラベルをオフスクリーン描画して目視（帯が中央で明るく端が暗い＝平坦な塗りでないこと）。

## 積み残し

- 実機・実セッションでの動作確認（起動しての目視）は未実施。稼働中のリリース版を落とさない方針のため、
  デバッグ版の起動確認はユーザーの判断に委ねる。
- 20px プリセットは原実装の調整値をそのまま使用。実チャットでの見え方に応じて `OrbPresets` の
  1 か所で調整できる。
- iOS の SwiftUI 経路（TimelineView + LinearGradient）はユニットテストで通っていない
  （パッケージのテストは macOS ターゲットで走るため AppKit 経路のみ）。iOS 向けビルドで
  コンパイルのみ確認済み。
