---
status: active
last-verified: 2026-07-17
---

# チームビュー (Beta)（旧アゴラ・グループチャット）の構造

> **このファイルの役割**: チームビュー＝3番目の表示モード（`.team`）の現行コンポーネント・データフロー・型（「今こう動いている」）。
> **書かないもの**: なぜこの設計かの rationale（→ `adr/0072-agora-flat-group-chat.md`。旧ツリー埋め込みは `adr/0070`、旧フラット統合は `adr/0043`＝いずれも superseded）。

## 表示モード

`ViewMode { single, grid, team }`（`Router/AppRouter.swift`）。ツールバー `ViewModeToggle` は3セグメント（help は「チームビュー」）。`DashboardDetailView` の `switch router.viewMode` で `.team` は `TeamTimelineView(viewModel:router:isCreating:onSelectAgentKind:)` を描画（**型名・内部識別子は旧称 Agora/TeamTimeline のまま**＝ユーザー可視文字列のみ改称。ADR 0072 決定1 の方針を継承）。

ユーザー可視の名称は `TeamViewBranding`（SessionFeature）に一元化: `title == "チームビュー"`・`betaSuffix == "Beta"`・`displayTitle == "チームビュー (Beta)"`（機能自体がベータの位置づけ）。討論ロールプロンプト（`AgoraRolePromptTemplate`）内の呼称も「チームビュー討論」。2026-07-17 に「アゴラ」から全ユーザー可視表記を改称（凍結 `AcceptanceTeamViewRenameTests`）。

## 空状態（シングルと共通ポリシー）

`StartAreaPolicy.content(hasSelectedProject:hasSelectedSession:)`: セッション選択中 → タイムライン本文／プロジェクトのみ選択 → エージェント選択カード／どちらも未選択 → 「プロジェクトを選択してください」。

## データフロー（tick 駆動・signature ゲート。ADR 0043→0070 の性能決定を継承）

```
.task(id: selectedSessionID) → 350ms ごとに refreshTimeline
  → TeamTimelineSignature.make(selectedSessionID, selectedProjectID, 全 sessionNodes の版数成分)
      ※ selectedProjectID は後方互換のデフォルト引数（nil）で追加。
        makeSources の依存入力とシグネチャ入力は常に一致させる（ADR 0072 決定5）
  → TeamComposerTarget.resolveRootSessionID で選択セッションの木の根を解決
  → composer readiness を毎 tick 算出し、値が変わった時だけ store へ publish（独立チャネル）
  → store.refreshAgoraTimelineIfNeeded(signature:messageLimitPerSession: 200) { makeSources }
      signature 不変なら何もしない。変化時のみ:
      → SessionTree.buildForest → AgoraParticipantsPolicy.orderedProjectSessionIDs(
            forest:, projectID: selectedProjectID ?? 選択セッションのプロジェクト)
         ＝対象プロジェクト内の全ルート木を forest 順で flatten（並列ルートを全員給餌）
      → AgentTimelineSource 化（appServer: transcript の ChatItem 列 / pty: readText を1件の terminalText）
      → AgoraParticipantsPolicy.participants(orderedIDs:parentByID:)
         ＝ルート＋直接の子のみ（孫・循環除外。暫定既定＝Agora 本体 run で確定・差し替え前提の隔離）
      → AgoraTimelineBuilder.build(sources:participants:)
         ＝参加者で絞って TeamTimelineModel.merge（timestamp 昇順・欠損は後ろ・同値は sources 順）へ委譲
body: store.items を VStack（非遅延。LazyVStack 禁止 = ADR 0045）で描画
```

## 行の描画（フラット・グループチャット）

- `AgentChatRowPolicy.showsSpeakerHeader(for:)` が false（`userMessage`）→ 右寄せ吹き出し、true → エージェント色アイコン＋**セッション名**＋timestamp のヘッダ＋本文。
- 本文の描画はコンテンツで分岐する。`AgentChatRowPolicy.usesAgentMessageBubble(for:)` が true（`agentMessage`）→ `AgoraAgentMessageBubble`（左寄せバブル・`RichMarkdownView` による markdown・ユーザー吹き出しと対称）。それ以外は appServer が `ChatItemView` read-only、pty が monospaced ブロック。＝ユーザー・エージェント双方がバブルチャット UI で並ぶ（2026-07-11 UX 修正）。
- **表示するのは「結果」だけ**（討論観戦の可読性）。`AgoraTimelineContentPolicy.includes(_:)` が `userMessage`/`agentMessage`/`error` のみ true、`reasoning`/`commandExecution`/`fileChange`/`subAgentMarker`/`turnCost` を除外する純関数。appServer transcript は `filteredTranscript(_:)` を通してからタイムラインへ流す（2026-07-11 UX 修正）。
- 発言者ヘッダのクリックで `router.openSingle(sessionID:)`（シングルビューへドリルダウン）。
- サブセッションの埋め込みカード・接続線・折りたたみは**存在しない**（ADR 0072 で廃止）。

## Thinking インジケータ（生成中の可視化）

タイムライン末尾に、生成中の参加者ごとに `AgoraThinkingIndicatorRow`（アイコン＋セッション名ヘッダ＋「Thinking...」＋ドットアニメーション）を出す。表示対象は `AgoraThinkingPolicy.thinkingSessionIDs(sources:statusesByID:)`＝status が `.running` の参加者（sources の表示順を維持）。ドットは `TimelineView(.animation)` 駆動だが、`accessibilityReduceMotion` かつ非アクティブウィンドウ（`controlActiveState != .key`）では静止フレームに落とす（常時 30fps 固着の回避。2026-07-11 UX 修正）。

## 参加者チップ列＋「＋」ボタン

ヘッダに participants 順のチップ（アイコン＋種別名＋セッション名）を並べ、右端の「＋」で並列セッションを追加起動する（`onSelectAgentKind(kind:backend:)` 経由＝カードと同じ spawn 経路。非討論時は `AgentStartCardsModel.modes(for:)` で agent × mode をフラット列挙し「<表示名> — チャット/ターミナル」項目を出す。ADR 0082）。有効条件は spawn 経路の project 解決 `selectedProjectID ?? defaultProjectID(forSelectedSession:)` と厳密一致（ADR 0072 決定4）。討論中はチップ列を `AgoraDiscussionHeaderView`（発言カウンタ「n/max」＝`utteranceCount/maxUtterances`・停止ボタン・役割名付き参加者チップ）に置換し、「＋」は claude チャット固定で追加後 `addAgoraDiscussionParticipant(id:role:)` により討論へ登録する。spawn 失敗は DashboardView と同型のアラートで可視化する。

## 入力欄（`Dashboard/TeamComposer.swift`）

宛先は選択セッションの木の根（`TeamComposerTarget.resolveRootSessionID`・循環安全）。「宛先: <根の displayName>」表示。活性＝readiness の独立 publish チャネル。送信は `ControllableSession.sendText(_:submit:)`、失敗時は下書き復元（非空の再入力は上書きしない）。契約は `AcceptanceAgentViewRowsTests`（rowPolicy 3＋composerTarget 4・凍結）。

送信は `AgoraComposerRouting.action(phase:canStartDiscussion:text:)` の3分岐（凍結 `AcceptanceAgoraRoutingTests` 相当）: 討論中（discussing/concluding）→ `submitAgoraUserUtterance`（発言合流・カウント外）、非討論で討論開始可能 → `startAgoraDiscussion(agenda:)`（議題投入）、開始不能な文脈 → 従来の根宛て送信を温存。討論中の宛先表示は「討論」。

キー入力は `NSViewRepresentable`（`TeamComposerTextInput`／`SubmitAwareTeamTextView`）で、シングルビュー入力欄と同じ `ComposerKeyRouting.action(...)` を共有する（`TeamComposerKeyRouting` が薄くラップ）。判定: Enter（keyCode 36/76・修飾なし）→ 送信、Shift+Enter → 改行、IME 変換中（`hasMarkedText()` で検出し `isComposing` として渡す）→ システムへ委譲（＝変換確定の Enter では送信しない）、Cmd+Enter も送信。以前は SwiftUI 標準の入力欄で Enter が送信に配線されていなかった不具合を、この共有ルーティングで解消した（2026-07-11 UX 修正・凍結 `TeamComposerSubmitTests`）。

## 参加者の役割リネーム

討論参加者は spawn 直後の花名のまま残さず、役割名へ自動リネームする。`DashboardViewModel.addAgoraDiscussionParticipant(id:role:)`／`startAgoraDiscussion`（ファシリテーター）から `renameAgoraParticipantIfRegistered` を呼び、`coordinator.participants` への登録成立を確認してからのみ改名する（登録拒否・非討論では花名を維持）。名前は `AgoraParticipantNaming.name(role:)`（role を trim、nil/空/空白は nil＝改名なし）。衝突判定は永続化される `name` に加え `displayName` も既存名集合に含め、重複時は「役割名 N」（半角スペース区切り・最小空き番号）で連番化する（自 id は集合から除外し再登録での不要な繰り上げを防ぐ）。`addParticipant` の enqueue のみ `awaitCompletion: true`＝drain 完了まで await を復帰させないため、復帰時点で participants 反映済みが保証され登録判定が空振りしない（2026-07-11 UX 修正・凍結 `AcceptanceAgoraRenameTests`）。

## 型と契約の正本

- 純関数: `AgoraParticipantsPolicy`（参加者選別2モード: `discussionParticipants` 非 nil＝討論中はその集合のみ・階層無視／nil＝ルート＋直接の子。集合は `TeamTimelineStore` の二次フィルタまで貫通し「参加者全員 root」の暗黙前提に依存しない）・`AgoraTimelineBuilder`（merge 委譲）— 凍結 `AcceptanceAgoraTimelineTests`（10件）＋`AcceptanceAgoraDiscussionUITests`（7件）。
- 表示ポリシー純関数（2026-07-11 追加）: `AgoraTimelineContentPolicy`（`includes`/`filteredTranscript`＝結果のみ表示）・`AgoraThinkingPolicy`（`showsThinking(status:)`/`thinkingSessionIDs(...)`）— 凍結 `AcceptanceAgoraTimelineDisplayTests`。`AgentChatRowPolicy.usesAgentMessageBubble(for:)` はバブル分岐の純関数。命名は `AgoraParticipantNaming.name(role:)`（凍結 `AcceptanceAgoraRenameTests`）。入力欄キー判定は `TeamComposerKeyRouting`→共有 `ComposerKeyRouting`（凍結 `TeamComposerSubmitTests`）。
- 討論エンジン系: `AgoraDiscussionEngine`（純粋状態機械・凍結 `AcceptanceAgoraEngineTests` 21件）・`AgoraDiscussionCoordinator`（Effects 注入の配線層・凍結 `AcceptanceAgoraCoordinatorTests` 8件・DashboardViewModel の 350ms tick から駆動）・`AgoraUtteranceExtraction`／`AgoraRolePromptTemplate`／`AgoraDiscussionSettings`（凍結 各 10/6/5件）。討論の操作面は `DashboardViewModel`（`agoraDiscussionCoordinator`・`startAgoraDiscussion`・`stopAgoraDiscussion`・`submitAgoraUserUtterance`・`addAgoraDiscussionParticipant`）。設計判断は ADR 0080。
- 招集の着地チェーン: `scripts/phlox spawn --role` → `ControlServer.parseSpawn`（role 付き claudeCode は backend 既定 appServer。`ControlServerSpawnRoleTests`）→ `ControlSpawnContext` @TaskLocal → `ControlActionHandler.handleSpawn` → `dashboard.persistSessionRole` ＋ `dashboard.agoraParticipantLanded(id:role:requester:)` → 討論中なら `addAgoraDiscussionParticipant` で自動登録＋参加プロンプト注入（役割なしは要求者が参加者の場合のみ。`AgoraIntegrationRegressionTests`）。
- 旧フラット API（`TeamTimelineModel.merge`・`TeamTimelineNodeOrdering`・`TeamTimelineStore.refreshIfNeeded`）は現役の土台（凍結 `TeamTimelineStoreAcceptanceTests`・`TeamTimelineModelTests`）。
- 旧ツリー API（`AgentChatTimelineBuilder`・`refreshAgentTimelineIfNeeded`・`agentEntries`）は**本番経路から切断済みの残置**（既存白箱テストが参照するため。負債＝次 run で棚卸し。ADR 0072 結果）。

## 既知の制約

- ストリーミング中は signature が毎 tick 変化し再構築が走り続ける（ADR 0043 から継承の実測課題）。
- 討論状態は in-memory のみで永続化なし（ADR 0080。完全自由発言の成立は 2026-07-11 の実機検証で確認済み）。
- signature には討論参加者集合が成分として入る（ADR 0072 決定5 の継承。`TeamTimelineSignature.make(discussionParticipantIDs:)` に1本化）。
