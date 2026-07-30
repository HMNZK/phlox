---
status: active
last-verified: 2026-07-10
---

# 0067: Thinking インジケータのシマーアニメーションと viewport pause

> **拡張**（2026-07-19・ui-fixes run / task-3）: 「Thinking...」テキスト自体にも、明度が**左→右へ流れるシマー**を追加した。本 ADR と同じ純関数方針を踏襲する——`ThinkingAnimationModel` に純関数 `shimmerPhase(date:)`（時間に線形前進・周期 `shimmerPeriod`・戻り値 `[0,1)`）と `shimmerBrightness(position:phase:)`（`position==phase` で最大 1.0・離れるほど `shimmerMinBrightness` へガウス減衰）を足し、既存 `timelineSchedule(isVisible:)`（30fps 上限・非表示時は空エントリ）と `isTimelineVisible` で駆動し、`LinearGradient` の mask で文字へ適用する。`Timer`/`repeatForever`/アニメ用 `@State`/新規 `GeometryReader` は不使用、`reduceMotion` 時は静的表示。凍結オラクル `AcceptanceThinkingShimmerTests`（DashboardFeature）が純関数仕様を担保。

> **拡張**（2026-07-20・thinking-remove-ellipsis run）: メインチャットの**跳ねドット（サイン波の `StaticThinkingDots`）を廃止**し、Thinking インジケータをシマーのみにした（`ThinkingIndicatorCell` から `StaticThinkingDots` を除去、孤児化した `ThinkingAnimationModel.dotState`/`DotState`/`period` とドット専用テストを削除。シマー純関数と viewport pause は不変）。あわせて **iOS も同一セマンティクスのシマーへ移植**（`DSThinkingIndicator`／`DSThinkingAnimationModel`。入力は iOS 慣習の `Date` ではなく `TimeInterval`。定数・式は macOS と一致）。iOS は従来シマーを持たず点滅ドットのみだったため、ドット除去だけでは静止表示になる不整合を避ける狙い（ユーザー決定 B）。**ダッシュボードの別実装 `AgoraThinkingDots`（`AgentChatRowPolicy`）はスコープ外で不変**。凍結オラクル `ThinkingShimmerAcceptanceTests`（iOS PhloxKit）が iOS シマー純関数仕様を担保。本文の「サイン波の波打つドット」は本注記により置換され、現行はドットなし・シマーのみ。

> **拡張**（2026-07-24・agent-grid-jank run / task-1 → ADR 0117）: シマーの**駆動方式のみ**を SwiftUI `TimelineView`（30fps）から Core Animation 駆動の `NSViewRepresentable`（`ThinkingShimmerView`）へ移した。実測で、`TimelineView` が SwiftUI の依存グラフ（AttributeGraph）とアクセシビリティ木を毎フレーム再構築させ、複数セッション・グリッドでメインスレッドを占有していた（`sample` でメインの約半分が `AccessibilityViewGraph.postUpdate`）。CA 化でシマーの見た目（明度帯・周期 `shimmerPeriod`）と純関数契約（`shimmerPhase`/`shimmerBrightness`/`shimmerBandCenter`・`AcceptanceThinkingShimmerTests`）・reduceMotion 静止経路・viewport pause シグナル（`isTimelineVisible`）はすべて不変のまま、シマー駆動のメインスレッド負荷を隔離実測で ~24%→~0%（9タイル）にした。本 ADR の「シマーは `LinearGradient` の mask で TimelineView 駆動」の記述は駆動方式に限り ADR 0117 で置換される（純関数・viewport pause の方針は不変）。詳細・落とし穴（CAGradientLayer.locations は 0..1 内・帯幅は host 幅換算）は ADR 0117。

> **後継**（2026-07-30・thinking-orbs run → ADR 0142）: Thinking インジケータの表示自体を**点描 orb**（thinking-orbs の Swift 移植）へ置き換えたため、本 ADR が定義した「Thinking... テキストのシマー」は**Thinking 表示としては廃止**された。凍結オラクル `AcceptanceThinkingShimmerTests`（DashboardFeature）と`ThinkingShimmerWhiteboxTests` も削除し、回帰保護は `ThinkingOrbEngineTests` / `ThinkingOrbHostViewTests`（DesignSystem）が引き継ぐ。ただし**シマー純関数（`ThinkingAnimationModel.shimmerPhase`/`shimmerBrightness`/`shimmerBandCenter`）は残存**する——圧縮中インジケータ（`CompactingIndicatorCell`）が引き続き使うため。viewport pause のシグナル（`isTimelineVisible`）と reduceMotion 静止経路の方針は orb でも不変。詳細は ADR 0142。**続報**（同日・[ADR 0143](0143-activity-label-keeps-shimmer.md)）: シマーは**状態語のラベルへ戻した**。本 ADR が凍結した帯の仕様（余白 0.6・帯幅 0.22）は `DesignSystem.ShimmerBandModel` へ値を変えず移設し、凍結オラクルは `ShimmerBandModelTests` が引き継ぐ。**周期 1.6s → 2.0s・下限明度 0.45 → 0.55 へ変更**（実チャットでの目視で、速すぎる／ライトモードで薄すぎることが判ったため）。

## 状況

transcript の Thinking インジケータは3点の二値点滅（`TimelineView(.periodic(by: 0.28))` + opacity 切替）で、「安易な点滅ではないリッチな表現にしたい」というユーザー要望があった（composer-agent-ux run / task-2）。一方、この領域には ADR 0010 の事故実績（view body 評価中の @Observable state 変更 → 無限再無効化 → CPU 100% 固着）があり、リッチ化は CPU ハザードと隣り合わせである。

## 決定

1. **アニメーション状態は純関数で導出する**: `ThinkingAnimationModel.dotState(index:dotCount:date:)`（`SessionFeature/ThinkingAnimation.swift`）が、TimelineView の date のみを入力にサイン波（周期 2.4s・ドットごとに位相差）で opacity [0.35,1.0]・scale [0.85,1.15]・yOffset [−1.5,+1.5] を返す。`Timer`・`withAnimation(.repeatForever)`・アニメーション目的の `@State` は使わない（ADR 0010 の一方向データフローを維持）。
2. **更新周波数は 30fps を上限とする**: `AnimationTimelineSchedule(minimumInterval: 1/30)`。
3. **非表示中はエントリを発行しない**: カスタム `ThinkingTimelineSchedule` が `isVisible == false` でエントリ列を空にする（`AnimationTimelineSchedule(paused:)` は初期描画エントリを返しうるため、空列で停止を明示保証）。可視性は `isInViewHierarchy（onAppear/onDisappear）&& isInTranscriptViewport && scenePhase == .active` の純関数合成。
4. **viewport 可視性は ChatAutoFollow の isAtBottom を流用する**: transcript は非 lazy VStack のため onAppear/onDisappear ではスクロール画面外を検出できない。既存の `ChatAutoFollowScrollEventBridge`（`NSView.boundsDidChangeNotification` 観測）から「最下部が見えているか」を取り出し、最下部セルである Thinking インジケータの可視性シグナルとする。**GeometryReader は新設しない**（ADR 0010 で撤去した経緯）。

## 棄却した代替案

- **Timer / repeatForever / @State 駆動のアニメーション**: ADR 0010 の再発リスク。棄却。
- **GeometryReader によるセル単位の厳密な viewport 判定**: 過去のハング原因系。isAtBottom 近似（部分可視でも停止しうる）は CPU 保護側に倒れる安全な近似として採用。
- **「macOS 14 では viewport 検出不可」として残余リスク受容**: 差し戻しレビュー（stage2）が ChatAutoFollow の既存観測で実現可能と反証したため棄却し、配線を実装。

## 結果・残余

- 受け入れテスト（`AcceptanceThinkingAnimationTests`）が決定論・周期性・連続性・多階調・波位相・有界を符号化し凍結。白箱テストが viewport pause（空エントリ）を検証。
- **既知の残余（スコープ外の改善候補）**: `ThinkingIndicatorCell` 内の hangAssessment 用 1Hz `TimelineView(.periodic(by: 1))` は task-2 以前からの既存挙動で、viewport pause の対象外（契約の不変条件「hangAssessment 表示は変えない」を優先）。将来リッチ化や整理をする場合は同じ可視性シグナルへ乗せられる。〔追記 2026-07-17: この残余は ADR 0094 で解消（`HangStatusTimelineSchedule` を同じ可視性シグナルへ配線）〕
- 「thinking 中に同一ウィンドウ内でスクロールアウトした瞬間」の残余更新は isAtBottom 近似で停止する（旧実装は 3.6Hz で無条件継続だったため、いずれのケースでも旧実装以下のコスト）。
