---
status: active
last-verified: 2026-07-10
---

# 0067: Thinking インジケータのサイン波アニメーションと viewport pause

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
- **既知の残余（スコープ外の改善候補）**: `ThinkingIndicatorCell` 内の hangAssessment 用 1Hz `TimelineView(.periodic(by: 1))` は task-2 以前からの既存挙動で、viewport pause の対象外（契約の不変条件「hangAssessment 表示は変えない」を優先）。将来リッチ化や整理をする場合は同じ可視性シグナルへ乗せられる。
- 「thinking 中に同一ウィンドウ内でスクロールアウトした瞬間」の残余更新は isAtBottom 近似で停止する（旧実装は 3.6Hz で無条件継続だったため、いずれのケースでも旧実装以下のコスト）。
