---
status: active
last-verified: 2026-07-11
supersedes: 0070
---

# ADR 0072: チーム表示を「アゴラ」に改称し、ツリー埋め込みを廃してフラットグループチャットにする

> **このファイルの役割**: なぜツリー埋め込み（ADR 0070 の決定2）を1日で廃し、「プロジェクト内の並列セッションを時系列フラットに混ぜるグループチャット」を選んだかの決定・文脈・結果。
> **書かないもの**: 現行のコンポーネント構造・型（→ `architecture/team-timeline-view.md`）。

## 文脈

ADR 0070 はサブセッションを spawn 位置へ埋め込みカードとして再帰挿入する「マインドマップ方式」を採った。ユーザーフィードバック（2026-07-11）でこの方式は廃止と明言され、方向が変わった: エージェントビューは**並列でセッションを起動し、それらを1本のグループチャットとして表示する場**にしたい。将来的にはファシリテーター駆動のマルチエージェント討論「Agora」構想（役割注入・議題駆動の自動招集・最大ターン/エージェント数・n:n 議論）の土台になる（Agora 本体は次 run・別 ADR）。

## 決定

1. **改称**: 「チームタイムライン／チーム表示」→「**アゴラ（Agora）**」（古代ギリシャの公共広場）。今回はユーザー可視文字列のみ変更し、型名・ファイル名（`TeamTimelineView` 等）は据え置く（churn 回避。Agora 本体 run で再判断）。
2. **フラットマージへ回帰**: 木構築（`AgentChatTimelineBuilder` の anchor 挿入）をやめ、休眠していた `TeamTimelineModel.merge`（ADR 0043 のフラット統合・凍結テスト green 維持中）を土台に再利用する。`AgoraTimelineBuilder.build(sources:participants:)` が参加者で絞って merge へ委譲する（merge 本体は不変）。
3. **参加者ポリシーの隔離**: 表示範囲は `AgoraParticipantsPolicy` の1関数に隔離。暫定既定＝「対象プロジェクト（`selectedProjectID ?? 選択セッションのプロジェクト`）内の全ルート＋各ルートの**直接の子**」（孫＝作業用 spawn・循環参照は除外）。範囲はユーザー「あとで考える」のため Agora 本体 run で確定・差し替える前提の設計。
4. **参加者チップ列＋「＋」ボタン**: ヘッダに参加セッションのチップを並べ、右端の「＋」から並列セッションを追加起動できる（既存のエージェント選択カードと同じ spawn 経路）。**有効条件は spawn 経路の project 解決（`selectedProjectID ?? defaultProjectID(forSelectedSession:)`）と厳密一致させる**（View 側に独自条件を置いた最初の実装はレビューで乖離を指摘され修正）。
5. **シグネチャへの入力対応**: source 給餌が `selectedProjectID` に依存するため、再構築シグネチャ `TeamTimelineSignature.make` にも `selectedProjectID` を含める（後方互換のデフォルト引数）。**「makeSources の依存入力」と「差分ゲートのシグネチャ入力」は常に一致させる**——不一致はプロジェクト切替時の stale 表示になる（ステージ2レビューが検出した HIGH）。
6. **維持**: グループチャット行スタイル（ユーザー右寄せ・エージェント左寄せ＋アイコン＋セッション名＝0070 決定1）・composer の根宛て送信と readiness 独立チャネル（同3・5）・tick＋シグネチャゲート・遅延配置禁止・200件間引き（同4）は継承。

## 棄却案

- **ツリー埋め込みの継続**（0070 決定2）: ユーザーが明示的に廃止を指示。凍結受け入れテスト8件（AcceptanceAgentChatTimelineTests）は仕様廃止として PM が凍結解除・削除（テスト弱体化ではなく契約自体の廃止。decision-log 記録）。
- **選択セッションの木のみ表示**: 「並列セッションのグループチャット」要求と両立しない。単一木給餌の初期実装はステージ1レビューが要求未達（MEDIUM）として検出し、プロジェクト全ルート給餌へ修正。
- **型名の一括リネーム**: 差分ノイズが大きく Agora 本体 run の設計確定前に行う価値が薄い。

## 結果

- 受け入れテスト: `AcceptanceAgoraTimelineTests`（参加者選別5＋フラットマージ5）を凍結。既存凍結（`TeamTimelineStoreAcceptanceTests`・`TeamTimelineModelTests`・`AcceptanceAgentViewRowsTests`・`AcceptanceStartAreaPolicyTests`）は green 維持。DashboardFeature 全量 1180 green・E2E 15 green。
- 実 Debug: アゴラ表示（チップ列＋「＋」・右/左のフラットチャット・宛先付き composer）を目視確認、表示中 CPU 0.1〜0.2% に収束（ADR 0045 の再発なし）。
- 旧ツリー実装は `AgentChatTimelineRows.swift` を削除。`AgentChatTimelineBuilder`・`refreshAgentTimelineIfNeeded` は allowed_paths 外の既存白箱テストが参照するため残置（死んだ本番経路＝負債。次 run で棚卸し）。
