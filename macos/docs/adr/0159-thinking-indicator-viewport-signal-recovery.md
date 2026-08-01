---
status: active
last-verified: 2026-08-02
---

# 0159: Thinking インジケータ可視性シグナルの固着解消と、非アクティブウィンドウでの継続

> 採番注記: 0158 は別ブランチ（debug-signing-tcc-stability）が使用中のため 0159 から採る。

## 状況

セッション実行中に、transcript 最下部の Thinking インジケータ（点描 orb ＋ シマーする状態語 ＋ 経過秒）が**止まったまま戻らない**というユーザー報告があった。観測された像は「状態語が静止し、直下の経過秒が `0s` のまま固定」で、**シマーと経過秒が同時に止まる**。ユーザーの体感では「作業時間が長いターン」「サブエージェントを開いたとき」に起きていた。

原因はコード読解と単体テストの実測で 2 つに切り分けられた。

### 原因1: 可視性シグナルがスクロール通知でしか再評価されない

ADR 0067 決定4 は、非 Lazy VStack では `onAppear`/`onDisappear` でスクロール画面外を検出できないため、`ChatAutoFollow` の `isAtBottom`（最下部から 80pt 以内）を viewport 可視性のシグナルとして流用した。この配線自体は妥当だが、**シグナルを更新する契機がスクロール系イベントしか無かった**:

- `NSScrollView.willStartLiveScroll` / `didEndLiveScroll`
- `NSView.boundsDidChangeNotification`（clip view の bounds＝**スクロール位置**の変化）

**コンテンツ側の寸法変化は購読していなかった。** そのため次の変化では再評価されない:

- ストリーミングでコンテンツが伸びる／描画予算 `TranscriptRenderBudget` が先頭ブロックを落として縮む
- **サブエージェント右ペインの開閉**でメインカラム幅が変わり、折り返しで高さが変わる（`ChatSessionView.mainColumnWidth`）
- composer 高さの変化（`bottomScrollContentMargin`）

一度 `false` が書かれると、回復にはスクロール・新着デルタ・status 変化・scroll view の差し替えのいずれかが要る。**長考中やサブエージェント待ちはそのどれも来ない時間帯**であり、そこで固着する。

この機序は凍結した受け入れテストで実測確認した（実 `NSScrollView` に bridge を attach し、スクロールせずに documentView の高さを 1000→2000 にすると、可視性コールバックが**一度も呼ばれない**）。

### 原因2: `scenePhase == .active` を可視性の条件にしていた

ADR 0067 決定3 の可視性合成は `isInViewHierarchy && isInTranscriptViewport && scenePhase == .active` だった。macOS では他アプリを前面にしただけでウィンドウは非キー＝`.inactive` になるため、**画面に見えているのに経過秒が止まる**。省電力としては合理的だが、ユーザーには「固まった」としか見えない。

## 決定

1. **可視性シグナルをコンテンツ寸法変化でも再評価する**。`ChatAutoFollowScrollEventBridge` が documentView の frame 変化と documentView の差し替えを観測し、`ChatAutoFollowGeometry.isAtBottom` を再評価する。**値が前回と変わったときだけ**コールバックする（bridge 側の `lastViewportVisibility` と `ChatTranscriptView.updateThinkingIndicatorViewport` の二重ガード）。
   - `isAtBottom` の判定式・**80pt しきい値は変更しない**（ADR 0067 決定4 の近似を維持。下記「棄却した代替案」）。
   - **新規 GeometryReader は置かない**（ADR 0067 の棄却案・ADR 0010 のハング原因系）。
2. **可視性のシーン条件を `scenePhase != .background` にする**。可視だが非キー（`.inactive`）では動かし続け、不可視（最小化・非表示＝`.background`）でのみ止める。規則の正本は `ThinkingAnimationModel.isTimelineVisible` の 1 箇所に置き、呼び出し側（`ThinkingIndicatorCell` / `CompactingIndicatorCell`）は `scenePhase` をそのまま渡す。

## 棄却した代替案

- **80pt しきい値を「インジケータが実際に見えているか」へ変える**: ユーザー決定で**据え置き**（ゲート①・2026-08-02）。厳密なセル単位判定は GeometryReader を要し ADR 0067 が棄却済み、しきい値の緩和はグリッド表示（多セッション同時）で動くセルを増やして CPU を押し上げる。今回は「戻ってこない」固着だけを直し、変更範囲と回帰リスクを最小にした。**結果として「80pt 以上スクロールを上げると、インジケータが見えていても止まる」挙動は残る**（ただしスクロールを戻せば必ず回復する）。
- **`scrollToBottomIfNeeded` のタイミング変更**: `.transcript`/`.status` が同一更新サイクル内で `proxy.scrollTo` を呼ぶため、レイアウト確定前に可視性をサンプリングしうるという仮説があった。決定1 が入れば伸長直後に必ず再評価が走り実害を失うため、**手を入れなかった**。
- **Timer による定期ポーリング・遅延再評価**: 症状を覆うだけで根本原因（購読していない）に到達しない。ADR 0067 決定1 の「Timer を使わない」方針にも反する。棄却。

## 検証

- **単体（凍結オラクル）**: `AcceptanceThinkingIndicatorViewportRecoveryTests`（伸長で false・伸縮だけで false→true 復帰・同値の重複発火なし・detach 後の無反応）、`AcceptanceThinkingIndicatorScenePhaseTests`（`.active`/`.inactive` で true・`.background` で false）。`ChatAutoFollowViewportWhiteboxTests` が documentView 差し替え経路を守る。`swift test` は SessionFeature **821**・DesignSystem **111** で green。
- **変異検証**: 独立レビュアーが 4 種の変異（KVO 登録除去／差し替え時に観測を移さない／新 documentView へ addObserver しない／旧 observer を解除しない）を standalone ビルドで実行し、いずれも red になることを確認した（テストがトートロジーでないことの実証）。
- **実機（Debug 版をリリース版と併存起動して実測）**:

  | 確認項目 | 結果 |
  |---|---|
  | サブエージェントペインを開いた状態で経過秒が進む | 46s → 58s（12 秒待機に一致）。**従来 0s のまま固着していた経路** |
  | 非アクティブウィンドウで進む | 1m20s → 1m36s（15 秒待機に一致） |
  | 最小化中は止まる | 実行中 CPU が 可視 14.7〜20.4% → 最小化 0.3〜0.7%（約 30 倍の低下） |
  | 最小化から復帰後に再開する | 57s → 1m10s（12 秒待機に一致） |
  | ターン終了後の CPU 収束 | 0.0〜0.7%（ADR 0010/0030 クラスの自走ループは発生せず） |

## 結果・残余

- **トレードオフ（意図的に受け入れた）**: 決定2 により、可視だが非キーのウィンドウで実行中は **1 コアあたり約 15〜20% の CPU** を使い続ける（従来はここで停止していたので約 0%）。最小化すればほぼ 0% に落ちる。ユーザーが体験を優先して選んだ結果である。
- **残余1（決定として残した挙動）**: 80pt より上へスクロールすると、インジケータが画面に見えていても停止する（ADR 0067 決定4 の近似のまま）。スクロールを最下部へ戻せば回復する。
- **残余2（未検証）**: 長時間ターンの観測は最長 2 分 30 秒までで、SC が求めた「3 分以上」には届いていない。グリッド表示（複数セッション同時）での CPU も測っていない。
- **残余3（許容した挙動）**: documentView 差し替え直後に可視性が `true → false → true` と一過性にフラップする（自己回復するため許容）。
- **残余4（未発火の前提）**: bridge 内の `MainActor.assumeIsolated` は、AppKit が通知を main thread で配信する前提に依存する。実機の検証範囲では発火していない。
