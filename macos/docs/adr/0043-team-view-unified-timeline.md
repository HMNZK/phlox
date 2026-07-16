---
status: superseded
superseded-by: 0070
last-verified: 2026-07-10
---

> 2026-07-10: 表示決定（フラット統合タイムライン）は ADR 0070（グループチャット＋ツリー埋め込み）で置き換えた。tick＋シグネチャゲートの性能決定は 0070 が継承する。

# ADR 0043: チームビュー（統合タイムライン）でメイン＋サブエージェントの会話を1本に可視化する

> **このファイルの役割**: なぜシングル／グリッドに加えて「チームビュー」を新設し、複数セッションの会話を1本の時系列タイムラインへ統合する設計を選んだかの決定・文脈・結果。
> **書かないもの**: 現行のコンポーネント構造・型（→ `architecture/team-timeline-view.md`）。

## 文脈

Phlox はメインエージェント（Claude）が `spawn` でサブエージェント（codex/cursor）を起動し、3者でオーケストレーション／議論する使い方を想定している。しかし従来 UI は **1セッションの出力しか表示できず**、メインが spawn したサブとの会話を一望する手段がなかった（シングル＝選択1件、グリッド＝タイルごとに独立表示）。

調査の結果、次が判明した:
- セッション親子は `parentSessionID` で一貫して保持され、`SessionTree.buildForest` で決定的に木化できる（既存・テスト済み）。
- 3種（claudeCode/codex/cursor）はいずれも `supportsStructuredChat: true` で、appServer 親から spawn された子も appServer へ昇格し、構造化 `[ChatItem]` transcript を持つ（`DashboardViewModel.sessionChatMessages(for:)` で取得可能）。
- 一方 `.pty` セッション（トップレベル単独起動や pty 親からの子）は構造化メッセージを持たず、端末スクロールバックしか取れない。

## 決定

1. **表示モードに `.team` を追加**する（`ViewMode { single, grid, team }`）。ツールバートグルを3セグメント化（`person.3`）、`toggleViewMode` を3値巡回にする。
2. **統合タイムライン方式**を採る（ユーザー決定。エージェント別カラム／主チャット＋折り畳みは棄却）。選択中セッションから **`SessionTree` でルート祖先を解決し、その全子孫**を集め、各セッションの会話を **timestamp 昇順で1本のスレッド**へマージする。各発言に発言エージェント名＋ブランド色を付す。
3. **マージは純関数 `TeamTimelineModel.merge` に切り出す**。timestamp 欠損は timestamp あり群の後ろへ、同値／両欠損は「セッション順→元順」で決定的に並べる（`(timestampカテゴリ, timestamp, sessionOrder, itemOrder)` の辞書式順序＝有効な strict weak ordering）。ブラックボックステストで固定する。
4. **バックエンド差の吸収**: appServer セッションは既存 `ChatItemView` を **read-only 再利用**して構造化描画、pty セッションは `readText` の端末スクロールバックを1テキスト項目として **フォールバック表示**する。
5. **右サイドバーのメトリクスをモード非依存化**: `selectedChatSession` の `viewMode == .single` 限定 guard を撤去し、グリッド／チームでも選択中 appServer セッションの経過時間・総コストを表示する。

## 棄却案

- **エージェント別カラム**: 誰の発言か分離は明快だが、3者が交互に議論する「チャット」体験にならない（時系列の因果が読み取りにくい）。ユーザーは統合タイムラインを選択。
- **主チャット＋サブ折り畳み**: 改修は最小だが、サブの発言が主の従属表示になり対等な議論に見えない。
- **pty 会話の構造化再パース（CLI jsonl 解析）**: コスト大。主シナリオ（appServer 親→appServer 子）は構造化データを持つため、pty は端末テキストのフォールバックに留めた。

## 結果

- サブエージェント会話が初めて一望できるようになった。既存基盤（`SessionTree`／`ChatItemView`／`SessionInfoPanel`）の再利用で新規表面積を最小化（新規は `TeamTimelineModel`／`TeamTimelineView` の2ファイル）。
- **残るトレードオフ**: `TeamTimelineView.makeTeam` は body 評価ごとに forest 再構築＋全 transcript 読込＋マージを行う。ライブ多エージェント時の描画コストは実機 runtime で要測定（jank があれば sessionNodes／transcript 版数でのメモ化を追加）。
  - **追記（2026-07-07）**: 実機で CPU 暴走として顕在化し、予告どおり版数メモ化（`TeamTimelineStore`＋`transcriptRevision`）を実装した。併せて表スタイル・LazyVStack 起因の非収束ループも修正（→ ADR 0045・delivery/0024・現行構造は architecture/team-timeline-view.md）。
