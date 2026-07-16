---
status: active
last-verified: 2026-07-16
---

# 空状態のエージェント選択カード（composer-agent-ux, 2026-07-10）

> **このファイルの役割**: シングルビューでセッション未選択のときに出る「エージェント選択カード」の現行構成。
> **書かないもの**: spawn の内部仕様（→ claude-chat-session-lifecycle.md）、チャット UI 部品（→ chat-mode-ux-components.md）。

## 挙動

セッション未選択の空状態（`DashboardDetailView.singleSelectEmptyState`）は、**プロジェクトが選択されているときのみ**利用可能なエージェント CLI のカード群を画面中央に表示する（判定は `StartAreaPolicy.content(hasSelectedProject:hasSelectedSession:)` の純関数）。プロジェクト未選択時は `SelectProjectPlaceholderView`（「プロジェクトを選択してください」）を表示する。シングルビュー中にサイドバーでプロジェクト**名**を選ぶと `AppRouter.selectProjectFromSidebar` が開いているセッションを閉じて（`selectedSession=nil`）この空状態へ入る（＝この画面が新規セッションの開始点になる。ADR 0086）。各カードはエージェント（アイコン＋表示名）の下段に**起動モードの2ボタン「チャット」「ターミナル」**を持ち（Pattern A、ADR 0082）、押したモードに対応するバックエンド（チャット=`.appServer` / ターミナル=`.pty`）で新規セッションが spawn され選択状態になる（そのまま入力できる）。チャットを既定として微強調し、ターミナルは控えめに併置する。

## 構成（Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentStartCards.swift）

- `AgentStartCardMode { chat, terminal }` — `.backend`（chat→`.appServer` / terminal→`.pty`）と表示名 `.label`（「チャット」/「ターミナル」）。SessionBackend への写像はここに集約。
- `AgentStartCardsModel.cards(available:)` — `DashboardViewModel.availableAgentKinds`（バイナリ解決できた CLI のみ・claudeCode 常に先頭）を順序保持でカードモデル化する純関数。
- `AgentStartCardsModel.modes(for: descriptor)` — `supportsStructuredChat ? [.chat, .terminal] : [.terminal]`。非チャット対応エージェントはターミナルのみを出す純関数。
- `AgentStartCardsLayoutPolicy` — カード列の並び方向を決める純関数。`requiredHorizontalWidth(cardCount:)`（= n×カード外形幅 172 + 間隔 + 左右 padding）と `shouldStackVertically(availableWidth:cardCount:)`（2枚以上かつ利用可能幅が必要幅未満で true）。定数はビュー実値と一致させ受け入れテストが凍結。
- `AgentStartCardsView` はルートを `GeometryReader` で包み、その提案幅（`proxy.size.width`）をポリシーに渡して **横並び（`HStack`）／縦積み（`ScrollView`+`VStack`）を切替**える（狭幅で見切れない。計測方式の理由は ADR 0090）。テスト用フック `onLayoutDecision`（既定 nil）が判定値を配線テストへ報告する。
- `AgentStartCardsView` / `AgentStartCardButton` — `AgentBrandIcon`（DesignSystem のロゴアセット）＋表示名を上段に、下段に `modes(for:)` のモードボタンを `HStack` で並べる。チャットボタンは `HoverableSurfaceButtonStyle`（エージェント色を濃いめ base 0.16 / hover 0.22 / pressed 0.28）で**既定として微強調**、ターミナルボタンは `HoverableSoftButtonStyle`（控えめ）。カード本体は `agentColor` の薄い背景（0.08）＋枠。`isDisabled`（`isCreating`）中は opacity 0.5＋各ボタン `.disabled`（多重起動防止）。
- `onSelect: (AgentKind, SessionBackend)`。配線は `DashboardView.createSessionFromKind(kind:backend:)` → `createSession(ref: AgentRegistry.descriptor(for: kind).ref, projectID: router.selectedProjectID, backend:)`。ユーザーがサイドバーでプロジェクトを選択していれば `selectedProjectID`（`AppRouter.selectedProjectID`）を優先してそのプロジェクトで spawn する。既存 `createSession` と同じ `isCreating` / `spawnError` alert パターン。成功時は新セッションを選択し、所属プロジェクトを展開する。

## 前提・境界

- プロジェクト未登録時の空状態（「プロジェクトを追加」）は従来どおり別ビューで、カードは出ない。
- custom agent descriptor / `supportsStructuredChat == false` はチャットボタンを出さず**ターミナルのみ**。
- 「＋」新規セッションメニュー（`DashboardView.newSessionMenuItems`）とチームビューの「＋」（`TeamTimelineView`・非討論時）も同じ `modes(for:)` で agent × mode をフラットに列挙する（項目名「<表示名> — チャット/ターミナル」）。
- 受け入れテスト: `DashboardFeatureTests/AcceptanceAgentStartCardsTests.swift`・`AcceptanceAgentModeLaunchTests.swift`・`AcceptanceAgentStartCardsLayoutTests.swift`（いずれも凍結）・白箱 `AgentStartCardsTests.swift`・`AgentModeLaunchWhiteboxTests.swift`・`AgentStartCardsLayoutWhiteboxTests.swift`（実ビュー配線の ImageRenderer 検証含む）・参照 PNG `AgentStartCardsRenderPNGTests.swift`。
