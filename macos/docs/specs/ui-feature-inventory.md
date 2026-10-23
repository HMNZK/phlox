---
status: active
last-verified: 2026-10-13
---

# Phlox macOS UI 機能インベントリ

この文書は、Phlox macOS アプリの UI を 0 から再構築するためのモック作成者向けに、既存 UI の機能・状態・文言を「画面/サーフェス（情報設計上の単位）」別に棚卸ししたものである。4名の担当（App/ 全体、DashboardFeature、SessionFeature、DesignSystem/TerminalUI/ChatRenderKit/エージェント種別/Localizable/ControlServer系）がパッケージ単位で並行調査した結果を、画面軸に組み替えて統合している。根拠は現行コードの `file:line` を正とし、docs/ADR/コメント由来の記述は「未確認（文書のみ）」「推測」と明記して区別する。対象範囲は macOS デスクトップアプリ（`App/` + `Packages/*/Sources`）のみで、iOS アプリ・CLI・Control API 単体の仕様は対象外（UI に現れる範囲でのみ言及する）。

> **2026-10-12 の更新範囲**: 新規チャット画面・プロジェクト単位のタブ・共通ターミナルの廃止・ヘッダーと使用量のバー・略号と図形の廃止・カスタムエージェントの廃止（ADR 0183〜0187）に関わる箇所だけを実装に合わせた（§1・§2 の図と上部バー、§3 の関連行、§9・§10、§14 の新規チャット行、§16.1、§17 の状態の行、§19 の設定行）。それ以外の章は 2026-09-29 時点の記述のままで、未再確認。チームビュー（§6）・右端ドロワー（§8）・インスペクタの一部は、別の変更でコードから無くなっているか構成が変わっている。
>
> **2026-10-13 の追加更新**: ADR 0188（新規チャットはタブではなくモード・下書きはアプリに 1 つ）と ADR 0189（アクセントは白黒）に合わせ、§2 の図・ヘッダーの行・タブ列、§9・§10、§17 の空状態の行、§19 のキー、§20 のアクセントの行だけを直した。

---

## 1. 画面マップ

| 画面/サーフェス | 役割 | 開き方 | 主な子領域 | 章 |
|---|---|---|---|---|
| メインウィンドウ | プロジェクト/セッションの一覧・操作の中心 | アプリ起動 | サイドバー・detail(single/grid/team)・インスペクタ・ドロワー・上部バー | 2〜11 |
| 設定ウィンドウ | アプリ全体設定 | メニュー/トップバー歯車/`Cmd+,` | 一般・外観・エージェント・接続・詳細の5タブ | 12 |
| Agent Console（エージェント管理ウィンドウ） | Claude/Codex/Cursor CLI設定の直接編集 | `Cmd+Shift+,`/トップバーのレンチ/設定「エージェント管理を開く」 | Claude/Codex/Cursorの各パネル | 13 |
| メニューバー（アプリメニュー） | キーボード操作の入口 | メニューバー | 表示/セッション/ウィンドウ系コマンド | 14 |
| 通知・Dock・初期化エラー画面 | システム通知・未読表示・起動失敗時のフォールバック | 自動発火/アプリ起動失敗時 | バナー通知・Dockバッジ・`InitErrorView` | 15 |

メインウィンドウの領域分割（テキスト図）:

```
[ヘッダー 38pt: 左=サイドバートグル（常に出す）＋選択中のタブの名前（左寄せ）  右=表示モード（単体/グリッド）・インスペクタトグル]
[左サイドバー(可変幅、既定280)] | [中央（単体）: 上段=プロジェクトのタブ / 下段=そのプロジェクトのチャット→項目（ターミナル・変更・ファイル・ブラウザ・シミュレーター）のタブ / 本体] | [右インスペクタ(可変幅、既定300)]
[最下部: 使用量のバー（全幅 24pt。全ハーネスの全枠を横に並べる。既定は残りの横棒、設定で数値%）]
```

---

## 2. メインウィンドウ — 全体構成

メインウィンドウは `DashboardView`（`Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift:88-181`, `navigationShell` 本体 `:183-419`）が `GeometryReader` + `HStack` で左から右へ4領域を並べる、単一ウィンドウ・単一階層構成。上部バーは実際の titlebar と重なる形でオーバーレイ配置（`.ignoresSafeArea(.container, edges: .top)` `DashboardView.swift:423`）。

- 左サイドバー: `DashboardSidebarView`。`router.sidebarVisible` で開閉、幅 `sidebarWidth`（既定280, `DashboardView.swift:13`）。ドラッグでリサイズ（`ResizeGripView`, `:328-345`。掴みしろ20pt、hover/drag中accent色3pt発光バー、`Packages/DesignSystem/Sources/DesignSystem/ResizeGripView.swift:11-65`）。
- 中央 detail: `DashboardDetailView`（`Dashboard/DashboardDetailView.swift`）。`router.viewMode`（`Router/AppRouter.swift:6-10`）により single / grid / team の3モード切替。
- 右インスペクタ: `InspectorView`（ファイルツリーだけ。2026-10-13 に使用量とセッション情報のタブを廃止。ADR 0192）。`router.inspectorVisible` で開閉、幅 `inspectorWidth`（既定300）。
- 右端ドロワー: `TerminalPanelView` / `EditorPanelView`。`router.terminalPanelVisible` / `editorPanelVisible` の組で開閉。両方表示時は `VSplitView` で縦積み（`DashboardView.swift:648-659`）。既定幅560pt・最小280pt（`PanelDrawerLayout.swift:9-10`）。ドラッグでリサイズ（`:367-403`）。

ビューモード（`ViewMode`, `Router/AppRouter.swift:6-10`）:
1. **single**: 選択中の1セッションのみ表示（`SessionView` / `ChatSessionView` を `SessionFeature` へ委譲, `DashboardDetailView.swift:67-80`）。→ 4章
2. **grid**: `SessionGridView` で複数セッションをタイル表示、プロジェクト絞り込み・セッション選択の2軸フィルタあり（`DashboardDetailView.swift:42-54`）。→ 5章
3. **team**（「チームビュー (Beta)」, `TeamViewBranding.swift:5`）: `TeamTimelineView` で複数エージェントの発言を1本のタイムラインに集約表示。→ 6章

セッション未選択の単体表示では、プロジェクトが 0 件でも `NewChatView`（`DashboardDetailView.swift`。旧 起動カードとフォルダの登録案内は廃止）。送信先のプロジェクトが決まっていれば、そのプロジェクトを選んだまま子タブの場所に出す（`router.showsNewChat`）。→ 9章

### 2.1 ヘッダー（`Dashboard/DashboardToolbar.swift`）

中央とインスペクタの上に渡る 38pt（`DSLayout.toolbarHeight`）の帯。単体とグリッドで並びを変えない。設定の歯車とエージェント管理はサイドバー下端（`DashboardView.swift` の `sidebarFooter`）にある。使用量のチップ・「対応待ち」ボタン・worktree のメニューはヘッダーに無い（ADR 0184・0186、unified-new-chat-start.md §6.9）。選択中のタブの名前（セッション名・ファイル名・「ターミナル」・「変更 N」・新規チャット画面では「新規チャット」）は、サイドバートグルの右に左寄せで出る（`HeaderTabTitle`、識別子 `header-tab-title`。最大幅 360pt・末尾を省略。グリッド表示とプロジェクト 0 件では出さない。unified-new-chat-start.md FR-41）。

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定/種別差 | 根拠 file:line |
|---|---|---|---|---|---|
| サイドバー開閉 | ボタン（左端。常に出す。信号の右）。隠しているときだけ対応待ちの件数のバッジを添える | — | 表示/非表示 | — | `DashboardToolbar.swift`（`SidebarToggleButton`） |
| 表示モード切替（単体/グリッド） | セグメントボタン 2 種（右寄せ。幅 960pt 未満では名称なしのアイコンだけ） | `router.viewMode` | 選択中セグメントの面表現 | — | `DashboardToolbar.swift`（`ViewModeToggle`、`ToolbarDensity`） |
| インスペクタ開閉 | ボタン（右端） | — | 表示/非表示 | — | `DashboardToolbar.swift`（`inspectorToggleButton`） |
| グリッド絞り込み・表示セッションの選択・レイアウトのプリセット | グリッド表示のときだけ、ヘッダーの下に出る表示範囲のバー | 「表示範囲」・対象名・N 件・プリセット名 | 絞り込み中/選択中 | ペインレイアウト永続化（`PaneLayoutStore`） | `GridModeBar.swift`、`GridScopeSummary.swift`、`GridSessionPicker.swift`、`PaneLayoutPresetMenu.swift` |

### 2.2 タブ列（`Tabs/SessionTabBar.swift`・`Tabs/SessionTabsContainer.swift`、単体表示のみ）

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定/種別差 | 根拠 file:line |
|---|---|---|---|---|---|
| 上段: プロジェクトのタブ | クリックでそのプロジェクトへ切り替え。✕（選択中・ホバー中だけ）でプロジェクトの削除確認。右クリックで「プロジェクト名を変更…」。右端の「＋」でプロジェクトを追加（⌘O と同じ）。入りきらないときは 180→96pt に縮め、残りは「ほか n ⌄」 | サイドバーの全プロジェクト（並びもサイドバーと同じ） | 選択中のプロジェクト | 識別子 `tabs.project.<n>`・`tabs.project.add`・`tabs.overflow` | `SessionTabBar.swift`（`TabAccessibilityIdentifier`）、`ProjectTabs.swift` |
| 下段: チャット → 項目のタブ | クリックで切り替え。✕・⌘W は種類ごとに動きが違う（チャット=セッションの削除確認、ターミナル=実行中なら確認、ファイル=未保存なら確認）。新規チャットはタブにならない。「＋」（`tabs.item.add`）で 新規チャット ⌘N（新規チャット画面を出す）/ ターミナル / 変更 / ファイルを開く… / ブラウザ / シミュレーター を選ぶ | そのプロジェクトのセッション（サイドバーと同じ並び）＋項目（`ProjectTab`。プロジェクトごとに並びを持つ） | 選択中・左右の分割（⌘\） | 識別子 `tabs.item.<n>`・`tabs.item.add`。保存は `phlox.projectTabs.v1`（変更・ファイルと選択・分割だけ。旧い `.newChat` は読み込み時に捨てる） | `SessionTabsContainer.swift`（`ChildTabBar`・`NewTabChooser`）、`ProjectTabs.swift` |

共通ターミナル（ホームで開く、タブ列の右端）は廃止した。ターミナルはプロジェクトのタブの下に一本化し、シェルは `ProjectTerminalStore` がタブごとに持つ（`UserTerminal/ProjectTerminalStore.swift`、ADR 0187）。

---

## 3. サイドバー（`Dashboard/DashboardSidebarView.swift`）

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| プロジェクト一覧表示 | — | プロジェクト名・展開状態。右端にセッション数・実行中件数は出さない | 展開/折りたたみ | — | `DashboardSidebarView.swift`, `SidebarRows.swift` |
| プロジェクト追加 | 見出し右「+」クリック | NSOpenPanel でフォルダ選択 | — | — | `DashboardSidebarView.swift:92-109`, `DashboardView.swift:758-772` |
| プロジェクト展開/折りたたみ | シェブロンクリック | `expandedProjectIDs` | 展開/折りたたみ（アニメーション0.12s） | — | `DashboardSidebarView.swift:111-126, 232-242` |
| プロジェクト選択（single起点） | フォルダアイコンクリック | `router.selectedProjectID` | 選択中/未選択 | — | `:127-129, 331-335` |
| プロジェクトでグリッド絞り込み | プロジェクト名クリック | `router.gridFilterProjectID` | 絞り込み中バッジ表示 | — | `:130-131, 337-345`, `SidebarRowEmphasis.swift:19-35` |
| プロジェクト名変更 | 「…」メニュー→名前を変更／右クリック | alert + TextField | — | — | `DashboardSidebarView.swift:133-136, 355-357, 401-403`, `DashboardView.swift:171-180, 888-899` |
| プロジェクト削除 | 「…」メニュー→削除／右クリック | 確認ダイアログ（子孫件数を含む文言、フォルダ自体は削除されない旨） | 破壊的操作 | — | `DashboardSidebarView.swift:137-139, 356-357`, `DashboardView.swift:129-147`, `DashboardViewModelSupportingTypes.swift:19-33` |
| 新規チャット（プロジェクト行の「＋」） | プロジェクト行の「＋」（ホバー時。「⋯」と同じ枠なしのボタン。メニューは挟まず押した時点で切り替え）、右クリック・「⋯」の「新規チャット」、サイドバー下端の「＋ 新規チャット ⌘N」 | `NewChatEntryActions` が `router.showNewChat(projectID:)` を呼ぶ。そのプロジェクトを送信先にして新規チャット画面（タブではなくモード）を出す。セッションは作らない | — | 9 章・10 章 | `SidebarRows.swift`（プロジェクト行の「＋」）、`DashboardSidebarView.swift`（プロジェクトメニューの「新規チャット」）、`DashboardView.swift`（`sidebarFooter`）、`NewChatEntryActions.swift` |
| 未割当セッション表示 | — | 「その他」セクション | — | — | `DashboardSidebarView.swift:71-81` |
| セッション行表示 | — | セッション名。右端に状態の文字（「実行中」「承認待ち」「質問あり」「エラー」「無応答」「完了」。待機中は何も出さない）。略号・状態の図形・未読の丸は出さない（ADR 0184） | 実行中は名前全体が点滅（動きを減らす設定では静止）。未読は題名を主文字色・やや太く | — | `SidebarRows.swift`、`SidebarRowEmphasis.swift` |
| セッションツリー展開/折りたたみ | 子持ち行のシェブロン | `SessionTreeViewModel.Row` | 展開/折りたたみ | — | `DashboardSidebarView.swift:146-153, 176-189, 525-542` |
| セッション選択 | 行クリック | `router.selectedSession` | 選択中はグレーの面 | — | `DashboardSidebarView.swift`, `SidebarRowEmphasis.swift` |
| セッション名ホバー | 名前にマウスホバー | 名前・エージェント・状態・経過時間・プロジェクト名とセッション数・作業ディレクトリをカード表示 | ポインタをカードへ移しても表示を維持 | — | `SidebarRows.swift` |
| 要注意（未読完了・質問待ち）表示 | — | セッション行の面の強調。注意が必要な状態の右端の文字は注意の色 | 選択中でも状態の色を優先 | — | `SidebarRowEmphasis.swift`, `DashboardSidebarView.swift` |
| セッション名変更 | 右クリック→名前を変更 | alert + TextField（空欄で短縮ID表示に戻る） | — | — | `DashboardSidebarView.swift:205-208`, `DashboardView.swift:901-917` |
| セッションのプロジェクト変更（未割当→割当） | 右クリック→プロジェクトを変更 | NSOpenPanel でフォルダ選択→再起動 | 破壊的（ターミナル内容喪失を警告） | — | `DashboardSidebarView.swift:209-212`, `DashboardView.swift:148-160, 774-794` |
| セッションを別プロジェクトへ移動 | 右クリック→別のプロジェクトへ移動（サブメニュー） | 移動先候補（現在以外の全プロジェクト） | — | — | `DashboardSidebarView.swift:213-225`, `DashboardViewModel.swift:1257-1270` |
| セッション削除 | 右クリック→削除（destructive） | 確認ダイアログ（子孫件数を含む文言） | 破壊的操作 | — | `DashboardSidebarView.swift:227-229`, `DashboardView.swift:112-128` |
| 空状態（プロジェクトなし） | 「+」ボタン | — | 空 | — | `DashboardSidebarView.swift:244-265` |

### 3.1 実装済み・UI未配線（サイドバー関連）

DashboardViewModel には実装されているが、DashboardFeature全体・App層いずれにもUI呼び出し箇所が無い（grep確認、テストのみ使用）:

| 機能 | 備考 | 根拠 file:line |
|---|---|---|
| `reorderSession(_:with:)` | サイドバーでのドラッグ並べ替えを想定した実装と推測されるが呼び出し元なし | `DashboardViewModel.swift:875-890` |
| `runningBreakdown(in:)` / `runningSessionCount(in:)` | プロジェクトの実行中セッション数集計（visible/nestedOrchestration内訳）。サイドバーのプロジェクト行等での表示箇所は見当たらない | `DashboardViewModel.swift:706-764` |

---

## 4. セッション画面 — single表示（`SessionFeature`）

Phlox のセッション画面には大きく2系統の ViewModel/表示モデルがある。

- **Chat型（app-server / structured）**: `ChatSessionViewModel`（`ChatSessionViewModel.swift`, 約3235行）。Codex app-server、および Claude/Cursor の構造化イベント経路を扱う。`NormalizedChatEvent`/`ThreadEvent` ストリームで駆動される。
- **PTY型（ターミナル）**: `SessionViewModel`（`SessionViewModel.swift`, 約863行）。Claude Code は hook イベントで、Codex/Cursor の PTY 実行時は hook なしの出力監視フォールバックで状態を追う。

両者は `ControllableSession` プロトコル（`ControllableSession.swift:85-224`）に適合し、`SessionNode`（`.pty` / `.appServer`）で束ねられる。単独表示時は `ChatSessionView.swift` がメインカラムを構成する（サブエージェントの右パネルは 2026-09 に廃止。子は上部の札の帯に名前と状態だけを出す）。PTY型の単体表示は `SessionView.swift`（ターミナル、`viewModel.terminalCoordinator`出力、`SessionView.swift:6,17-39`。エージェント種別差は汎用`AgentSessionIcon`のアイコンのみ）。

### 4.1 メッセージ/ツールカードの種類

| 種類名 | 表示内容 | ユーザー操作 | 状態遷移 | エージェント種別差 | 根拠 file:line |
|---|---|---|---|---|---|
| ユーザーメッセージ (`UserMessageCell`) | 右寄せ吹き出し、本文、添付画像バッジ | ホバーでコピー・タイムスタンプ | ホバーのみ | なし | `ChatMessageCells+Basic.swift:34-93`, `ChatItem.swift:27` |
| アシスタントメッセージ (`AgentMessageCell`) | 左寄せMarkdown本文+コードフェンス | ホバーでコピー・タイムスタンプ | ホバーのみ | avatar色/シンボルは`agentDescriptor`依存 | `ChatMessageCells+Basic.swift:117-146`, `ChatTranscriptView.swift:320-333` |
| 推論(reasoning) (`ReasoningSummaryView`) | `DisclosureCard`折りたたみ | 開閉トグル | pending/streaming依存 | なし（Claude/Codex共通`.reasoning`） | `ChatMessageCells+Structured.swift:195-238` |
| コマンド実行単体 (`CommandExecutionCell`) | `DisclosureCard`、コマンド文字列+出力 | 開閉トグル | `isRunning`バッジ | なし | `ChatMessageCells+Structured.swift:277-335` |
| コマンドグループ (`CommandGroupCell`) | 連続`commandExecution`をまとめて折りたたみ | 開閉、「さらに表示」（20行制限）、行コピー | `isRunning`は最終アイテム依存 | なし | `ChatMessageCells+CommandGroup.swift:6-330` |
| ファイル変更 (`FileChangeCell`) | `DisclosureCard`、+/-行数バッジ、diff色分け | 開閉、行数上限超で「さらに表示」、コピー | 行数で既定展開/折りたたみ（既定折りたたみ閾値200行、展開後一括描画上限500行、`isExpanded`はユーザー明示トグルまで常に折りたたみ） | なし | `ChatMessageCells+Structured.swift:337-527`, `ChatMessageRenderCache.swift:167-184` |
| エラー (`ErrorMessageCell`) | 赤系背景、警告アイコン+本文 | なし（表示のみ） | なし | なし | `ChatMessageCells+Basic.swift:207-243` |
| サブエージェントマーカー (`SubAgentMarkerCell`) | 説明文+`subagentType · status`、状態アイコン | クリックでサブエージェント選択 | running→completed／failed | 自由文字列、汎エージェント共通 | `ChatMessageCells+Structured.swift:7-68`, `SubAgentModel.swift:3-7` |
| ターンコスト (`TurnCostCell`) | 右寄せ淡色USD金額 | なし | なし | なし | `ChatMessageCells+Basic.swift:148-185` |
| タスクリスト (`TaskListCell`) | `DisclosureCard`、各行にステータスアイコン | 開閉トグルのみ | pending→inProgress→completed | なし | `ChatMessageCells+TaskList.swift:10-91` |
| ユーザー質問カード (`UserQuestionCell`) | 質問文+選択肢(単一/複数)+自由入力、secretはマスク表示 | 選択肢クリック/入力/送信ボタン/閉じるボタン | pending→answered／expired | Codexは`ChatApprovalBroker`経由、閉じ操作もCodex/Claudeで分岐 | `UserQuestionCell.swift:16-353`, `ChatItem.swift:19-23` |
| 承認バナー (`ApprovalBanner`) | コマンド/ファイル変更/権限の承認待ちカード | Accept/Decline/Cancelボタン | `ChatApprovalKind`: command/fileChange/permissions | 下記4.2節参照 | `ChatSessionAccessories.swift:363-423`, `ChatApprovalBroker.swift:6-225` |
| 圧縮中インジケータ (`CompactingIndicatorCell`) | シマーテキスト+犬アニメ(6ステージ) | なし | `isCompacting`のみ | なし | `CompactingIndicatorCell.swift:22-100` |
| Thinkingインジケータ (`ThinkingIndicatorCell`) | オーブ+活動状態ラベル、ハング時は経過時間+中断ボタン | ハング時「中断」ボタン | `AgentActivityState`、`isStalled`（無応答120秒でハング検知、Chat型のみ実装） | avatarは`agentDescriptor`依存 | `ChatMessageCells+Structured.swift:70-193`, `ChatHangPolicy.swift:19-35` |
| 接続待ちインジケータ (`ChatConnectingIndicator`) | レーダー回転アニメ(Canvas) | なし | reduceMotionで静的化 | なし | `ChatConnectingIndicator.swift:5-111` |
| メッセージ種別ディスパッチ (`ChatItemView`) | なし | `ChatItem`のcase毎に上記各セルへ振り分け（reasoning/commandExecutionは本文・出力が空かつ非実行中ならEmptyView） | ADR 0116対応の`Equatable`実装（クロージャは比較対象外、`item`/`isRunningCommand`/`agentDescriptor`のみで同値判定） | avatarは`agentDescriptor`依存 | `ChatMessageCells.swift:5-92` |
| Markdown本文レンダリング (`RichMarkdownView`) | リンククリック | `Markdown(markdown)`をテーマ適用して表示、テーマは`themeID:scale:languageCode:role`キーでプロセス内キャッシュ | フォントスケール・テーマ・ロケールに追従 | なし | `RichMarkdownView.swift:9-53` |
| 圧縮中インジケータの演出詳細（6ステージのご当地ストーリー：海→川→砂漠→火山→氷山→宇宙） | なし（自動再生） | 犬は画面固定X=40ptで世界側がスクロール、1ステージ14.2秒（走行11.0秒＋イベント2回）、装備獲得演出、5ステージ踏破後にゴール演出 | `TimelineView`が渡す日時のみを入力とする純関数で状態導出（Timer/repeatForever禁止、ADR 0010） | なし | `CompactingDogAnimation.swift:16-59` |
| Codexサブエージェント/プランのインライン表示 (`CodexSessionSurface`) | 子スレッド行クリックで選択・展開表示、「停止」ボタン | プランタスクリスト(`TaskListCell`再利用)、子スレッド一覧（要約・ステータス）、選択中の子スレッドtranscript、エラー表示 | `subAgents.stopState(for:)`が`.available`でない間は停止ボタン無効、`threadId`変化で自動再取得(`task`/`onChange`) | Codex専用（`viewModel.agentRef == .builtin(.codex)`以外は非表示） | `CodexSessionSurface.swift:17-93` |

その他の関連機能: メッセージ単位コピー（ホバー時checkmark）`ChatMessageCopyButton.swift:12-70`／コードブロックコピー`ChatCodeCard.swift:4-41`／トランスクリプトMarkdownエクスポート（推論・出力・タイムスタンプのON/OFFオプション付）`ChatTranscriptExport.swift:5-211`／コマンド連続グルーピング`ChatTranscriptGrouping.swift:3-132`／「以前のメッセージを表示」ボタン（ウィンドウ拡張）`ChatTranscriptView.swift:171-318`。

共通セル部品: アバター行ラッパー`AvatarMessageRow`（`ChatMessageCellsCommon.swift:14-20`）／タイムスタンプ表示`ChatTimestampText`（`HH:mm`形式`en_US_POSIX`固定、`.distantPast`は非表示、フォントスケール・テーマに追従、`:22-44`）／折りたたみカード`DisclosureCard`（ラベル部クリックで開閉、chevron90度回転、`isToolCall`で文字色分岐、VoiceOverへ展開状態通知、`:46-132`）。

描画パフォーマンス関連: 描画結果メモ化キャッシュ`ChatMessageRenderCache`（Markdown分割/diff分類/シンタックスハイライト/diff行view/コマンド出力表示データの5種をNSCacheでメモ化、countLimit=512、`ChatMessageRenderCache.swift:22-106`）／テキスト選択方針（本文・コード・コマンド出力は選択可`.textSelection(.enabled)`、file change diff行は選択不可`.textSelection(.disabled)`＝diff1行のテキスト選択がセッション切替1回あたり最大1987msの原因だったため無効化、コメントに実測値記載、代替は`FileChangeCell`のセクションコピーボタン、`ChatTextSelectionPolicy.swift:15-47`）／ビューポート可視性シグナル`onViewportVisibilityChange`（ウィンドウ非nilかつ非隠蔽かつ表示範囲内で可視、表示範囲外セルのアニメーション/描画更新を停止、`ViewportVisibility.swift:6-95`）。

**不明点**: `SubAgentStrip`・`ChatSubAgentModel`の内部実装詳細、`ChatRecap.deriveActivityState`本体、`TranscriptItemPresentation`の既定展開ロジック本体は未読了（担当外ファイル）。通知文言「入力待ち」が完了時にも使われている点は実コードのまま記載、バグか仕様か未確認。

### 4.2 承認・ユーザー質問（Codex/Claude/Cursor共通経路の確定）

当初「ApprovalBanner はCodex専用ではないか」という未確認事項があったが、実コードで解消済み。`ChatApprovalBroker`は Codex 専用ではなく、**Claude/Codex/Cursor いずれの構造化チャットセッションにも共通で1個ずつ生成・配線される**。

- セッション生成時（`makeChatSessionViewModel`）は `plan.descriptor.ref`（Claude/Codex/Cursor 問わず）に関係なく `ChatApprovalBroker()` を1個生成し、その `broker.serverRequestHandler` を `environment.structuredClientFactory(...)` に共通の引数として渡す。エージェント種別による分岐は無い。（`Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift:658-665,678-683`）
- `ChatSessionViewModel` 側も `approvalBroker.requests` / `approvalBroker.userInputRequests` を購読するコードはエージェント種別で分岐しておらず、どのエージェントの承認要求であっても同じ `pendingApprovals` 配列・同じ `ApprovalBanner` に載る。（`ChatSessionViewModel.swift:1564-1573`）

したがって「UI側の受け皿（ApprovalBanner・ChatApprovalBroker・pendingApprovals）はエージェント種別を問わず単一実装」と確定できる。ただし実際にどのエージェントが承認要求を送ってくるかは各クライアント実装（Claude用/Codex用/Cursor用の`structuredClientFactory`実装、`SessionFeature`パッケージ外）側の挙動に依存し、それ自体は未確認。

### 4.3 コンポーザ（入力欄）

| 機能 | ユーザー操作 | 表示データ | 状態 | エージェント種別差 | 根拠 file:line |
|---|---|---|---|---|---|
| 複数行テキスト入力 | タイプ入力 | `text`バインディング | `editorHeight` | 共通 | `ChatComposer.swift:436-513` |
| プレースホルダー表示 | — | `UIWording.composerPlaceholder` | 未入力かつIME非変換中 | 共通 | `ChatComposer.swift:112-119` |
| 高さ自動調整(36〜160pt) | 行数変化 | `usedTextHeight` | — | 共通 | `ComposerHeightPolicy.swift:11-31` |
| 構文ハイライト(`/`コマンド、`@`ファイル、keyword) | タイプ | `ComposerHighlight.spans` | — | Claudeのみ`highlightsKeywords:true` | `ChatComposer.swift:103`, `ComposerHighlight.swift:4-67` |
| IME変換中の入力保護 | 日本語等IME | `isComposing` | — | 共通 | `ChatComposer.swift:592-639` |
| Undo/Redo | ⌘Z/⌘⇧Z | — | — | 共通 | `ComposerKeyRouting.swift:52-64` |
| 送信 | Enter単独／⌘Enter | — | IME変換中は無効(Enter単独) | 共通 | `ComposerKeyRouting.swift:76-90` |
| 改行挿入 | ⇧Enter | — | — | 共通 | `ComposerKeyRouting.swift:80-81` |
| ⌘V貼り付け(テキスト/画像分岐) | ⌘V | — | — | 共通 | `ComposerKeyRouting.swift:66-74` |
| composer幅で footer レイアウト切替 | ウィンドウリサイズ | 600pt/490pt閾値 | standard/compact/minimal | 共通 | `ComposerLayout.swift:15-48` |
| 入力履歴スクラババー（先端12件） | ホバー/クリックでジャンプ | `scrubberTicks` | — | 共通 | `ChatInputHistoryScrubber.swift:41-93,195-216` |
| 画像ペースト添付 | ⌘V | `ComposerPasteImageOutcome` | 元画像20MB/枚・4枚まで・合計80MB | Claude/Codexのみ対応（UI添付層。ワイヤ層の扱いは下記「不整合」参照） | `ComposerAttachments.swift:159-165`, `ChatComposer.swift:912-949` |
| 添付ボタン「+」でファイル/画像選択 | クリック→NSOpenPanel | — | — | 画像添付はClaude/Codexのみ、他はファイル参照挿入 | `ComposerSettingsControls.swift:559-661` |
| 添付チップ表示・削除 | ×クリック | `ComposerAttachmentChipPresentation` | — | 共通 | `ChatComposer.swift:1028-1102` |
| `@path`ファイル参照挿入 | +ボタンで非画像選択 | `"@\(path)"` | — | 共通 | `ComposerAttachments.swift:118-121` |
| `/`スラッシュコマンド候補 | `/`入力 | 選択エージェントのコマンド・スキル、有効なプラグイン、実行時受領 | 背景走査＋TTL5秒キャッシュ、部分一致 | 共通 | `ComposerSuggestions.swift`、`AgentSkillLocations.swift` |
| Codex skill候補混入 | `/`入力 | 新規チャットはローカル候補を初回送信時に照合、既存セッションは `skills/list` | キャッシュ・部分一致 | Codex限定 | `ComposerDraftInput.swift`、`CodexSkillSelectionState.swift` |
| `@`ファイル参照候補 | `@`入力 | ワークスペース走査(除外.git等) | TTL5秒キャッシュ、非同期coalescing | 共通 | `ComposerSuggestions.swift:57-79,682-745` |
| サジェスト選択移動/確定/却下 | ↑↓/Enter・Tab/クリック/Esc | `SuggestionReplacement` | — | 共通 | `ComposerKeyRouting.swift:35-49`, `ComposerSuggestions.swift:390-407` |
| エージェント別コントロール集合 | — | `[.model,.effort,.permission]`等 | `composerControls(for:)` | Codex/Claudeは同じ項目、Cursorはeffortなし | `ComposerSettingsControls.swift:25-36` |
| モデル選択 | メニュークリック | `availableModels` | — | Codexは`modelMenu`、他は`spawnModelMenu` | `ComposerSettingsControls.swift:130-352` |
| Reasoning effort選択 | 独立チップのメニュークリック | Claudeは固定候補、Codexは選択モデルの対応候補 | — | Claude/Codexで同じ表示チップ、Cursorはなし | `ComposerSettingsControls.swift` |
| 権限モード選択 | メニュークリック | プロファイル/permission mode/operation mode | — | 3エージェントで選択肢が異なる | `ComposerSettingsControls.swift:38-65,143-278` |
| Planモード切替 | メニュー選択 | `isPlanMode` | — | 全3エージェント共通で"plan"オプションあり | `ComposerSettingsControls.swift:424-436` |
| 現在Gitブランチ表示(30秒ポーリング) | — | `GitBranchReader.currentBranch` | — | 共通 | `ComposerContextIndicator.swift:223-239` |
| ブランチ切替ポップオーバー | ブランチ名クリック→行クリック | `git checkout`実行 | idle/loading/presented、checkoutError | 共通 | `ComposerContextIndicator.swift:241-360`, `GitBranchSwitcher.swift:20-21` |
| コンテキスト使用率ドーナツ | ホバーでポップオーバー | トークン使用率(80%以上で警告色) | — | 共通 | `ComposerContextIndicator.swift:5-50,144-186` |
| 送信ボタン | クリック | `canSubmit` | — | 共通 | `ChatComposer.swift:326-355` |
| 停止(中断)ボタン | クリック | `onInterrupt` | `isRunning`時のみ表示 | 共通 | `ChatComposer.swift:311-323` |
| 送信滞留診断ログ | 送信後バックグラウンド計測 | `send-diagnostics.log` | 3秒タイムアウト | 共通（AgentKind別ログ） | `SubmitDiagnosticRecorder.swift` |

**不明点**: 入力履歴の矢印キー(↑↓)呼び出しは調査対象ファイル内に実装が見当たらず（↑↓はサジェスト候補移動にのみ使用）。矢印キー履歴機能自体が存在しない可能性、または`ChatSessionViewModel.swift`側の未確認箇所にある可能性がある。`CodexImageInputState`/`CodexQuestionDetector`の実際の呼び出し元は担当外ファイルの可能性。

### 4.4 サブエージェントの札の帯（右パネルは 2026-09 に廃止）

札は名前＋状態アイコンだけで、押しても何も開かない。詳細は `architecture/chat-subagent-display.md`。

| 機能 | ユーザー操作 | 表示データ | 状態 | 根拠 |
|---|---|---|---|---|
| 札の帯（単一・グリッド共通） | なし | `stripSubAgents`。実行中と失敗だけ出る（完了・停止確認済みは消え、失敗は✕まで残る）。「メイン」の札は見た目のみ | `SubAgentStatus` | `ChatSessionAccessories.swift` の `SubAgentStrip` / `SubAgentStripRow` |
| 札の状態アイコン | なし | 実行中=ローディング／失敗=失敗マーク／それ以外=なし | `SubAgentChipPresentation.statusIcon(for:)` | `ChatSessionAccessories.swift` |
| 札のホバー操作 | 札にポインタを置く | 実行中で止められる（Codex・宛先が分かったClaude）=停止ボタン(■)／実行中で止められない=何も出さない／失敗=✕で帯から消す | `SubAgentChipPresentation.control` | `ChatSessionAccessories.swift` |
| 札の名前 | なし | 親が付けた名前。Codex=`agent_path` 末尾、Claude=Task の `description` | — | `CodexSubAgentState.swift`（`purpose(for:)`）, `ClaudeChatClient+SubAgentContent.swift` |
| Codex子thread一覧更新 | 自動 | `codexSubAgentState.children` | debounce（Codexのみ） | `ChatSessionViewModel.swift:415-487` |
| サブエージェント個別停止 | 停止ボタン | Codex=`turn/interrupt`、Claude=`stop_task`。確認まで「停止中」、確認で札が消え会話マーカーは「停止」。失敗・15秒タイムアウトで実行中へ戻る | — | `ChatSessionViewModel.stopSubAgent(displayID:)`, `ClaudeChatClient+StopTask.swift` |

### 4.5 Esc・巻き戻し・履歴再開・自動スクロール

| 機能 | ユーザー操作 | 表示データ/状態 | 状態遷移条件 | エージェント種別差 | 根拠 file:line |
|---|---|---|---|---|---|
| ターン中断 | 中断ボタン/Esc単発 | `.running/.awaitingApproval`→`.idle` | Esc押下 or ボタン | Chat型は`client.interrupt()`、PTY型はEscバイト送出 | `ChatSessionViewModel.swift:930-970`, `SessionViewModel.swift:459-470` |
| Escキーの優先順位付き一元処理（`performChatEscape`） | Escキー（composerフォーカス時はNSTextView.keyDown、非フォーカス時は`.onKeyPress`） | 優先順: (1)履歴ピッカー表示中は閉じる→(2)`handleEscapeKey`の状態機械へ（サブエージェントドロワーを閉じる段は廃止） | — | なし | `ChatEscapeHandling.swift:12-23,28-36` |
| Escダブルタップでリバートピッカー | Esc2連打(1.5秒以内) | `isHistoryPickerPresented=true` | `EscapeRevertPolicy.isDoubleEscape` | Chat型のみ | `ChatSessionViewModel.swift:989-1011` |
| 会話巻き戻しピッカー表示 | Esc2連打起動 | `ChatHistoryRevertPicker`をoverlay表示（背景40%黒＋タップで閉じる、0.15秒フェード）、上下矢印選択、Enter確定 | `isHistoryPickerPresented` | Chat型のみ | `ChatHistoryRevertPicker.swift:9-143`, `ChatEscapeHandling.swift:43-63` |
| リバート確定 | ピッカーで過去メッセージ選択 | transcript切り詰め、`client.resetConversation()` | running中は先にinterrupt | Codex/spawn型でID再採用方法が異なる | `ChatSessionViewModel.swift:1013-1095` |
| 下書き復元の1ショット通知消費 | リバート確定後の`draft`復元 | `draftRestoration`の`onChange`で`consumeDraftRestoration()` | `newValue != nil`のときのみ | なし | `ChatEscapeHandling.swift:39-42` |
| 履歴から再開 | ChatHistoryStartView選択（履歴カード一覧、クリック選択） | transcript全置換 | `shouldOfferHistoryStart` | Claude/Codexのみ（Cursor非対応） | `ChatSessionViewModel.swift:379-591`, `ChatHistoryStartView.swift:5-192` |
| Compact圧縮 | `/compact`送信 | `isCompacting=true→false` | — | Chat型共通 | `ChatSessionViewModel.swift:116-119` |
| 自動スクロール追従の状態機械 | ライブスクロール開始/終了 | `ChatAutoFollowController.State`: `.following`/`.userScrolling`/`.detached` | 手動スクロールで最下部から離れると`.detached`、最下部へ戻すと`.following`復帰（最下部判定は閾値80pt） | なし | `ChatAutoFollow.swift:4-85` |
| 新着イベントでの自動スクロール可否 | なし（自動） | `ChatBottomScrollPolicy.shouldScrollToBottom` | `isFollowing`のときのみ最下部へ | なし | `ChatAutoFollow.swift:55-71` |
| セッション切替時に追従状態を`.following`へリセット | セッション切替 | `sessionDidChange()` | 契約はacceptanceテストで凍結 | なし | `ChatAutoFollow.swift:38-44` |
| PTY:信頼プロンプト自動応答 | なし(自動) | Enter自動送信 | "Do you trust..."検出（Codex PTY型のみ） | Codex PTY型のみ | `CodexSessionAdapter.swift:42-49` |
| PTY:対話質問検知 | なし(自動) | `.awaitingApproval`へ | — | Codex PTY型のみ | `CodexSessionAdapter.swift:52-85` |

---

## 5. グリッドビュー（`SessionGridView` / `PaneLayoutView`、実体は`SessionFeature`）

呼び出し元は `DashboardDetailView.swift:42-54`。実体は `Packages/SessionFeature/Sources/SessionFeature/SessionGridView.swift`（薄いラッパー）→`PaneLayoutView.swift`（本体）。旧「k×k等分グリッド」は撤去済みで、現在は二分木の分割ツリー`PaneTree`による可変比率レイアウト（コメントで明記、`PaneLayoutView.swift:15-18`）。

| 機能 | ユーザー操作 | 表示データ・挙動 | 状態 | エージェント種別差 | 根拠 file:line |
|---|---|---|---|---|---|
| タイル配置（列数固定なし） | — | `PaneTree.frames(in:spacing:)`で矩形を絶対計算しZStackへ配置。ビュー階層をフラットに保ちAppKit(NSView)の再アタッチを避ける設計 | — | なし | `PaneLayoutView.swift:9-18,58-119` |
| レイアウトプリセット適用 | トップバーの`PaneLayoutPresetMenu`（2.1節既出） | balanced/single/columns2-3/rows2-3/grid2x2/mainLeftStackRight/mainTopStackBottom | — | なし | `PaneLayoutPresetMenu.swift:9-19`（ツリー生成ロジックは`PaneTree`側、未読） |
| タイルをドラッグして入れ替え/分割挿入 | タイルヘッダを`.draggable`でドラッグし別タイル上へドロップ | ドロップ位置が中央なら`.swap`（入れ替え）、端（leading/trailing/top/bottom）なら`.split`（既存ペインを50:50で分割し差し込む） | ドラッグ中は移動先タイルへハイライト表示（`fillSelected`の半透明矩形）、`PaneDropZone.target`が判定 | なし | `PaneLayoutView.swift:83-146,384-447`, `PaneDropZone.swift:16-56`, `SessionGridView.swift:7-13`（`DraggedSession`はJSON転送のTransferable）, `PaneLayoutAction.swap`/`.insertBySplitting`（`PaneLayoutAction.swift:5-9`） |
| 分割線ドラッグでサイズ変更（ライブゴースト、確定は遅延） | ハンドルをドラッグ | `PaneDividerDragMachine`が`.preview(ghost)`、最小幅240pt・最小高160ptでクランプ | ドラッグ中は未確定、mouseUpで`PaneLayoutAction.setDivider(id,leadingFraction:)`確定 | なし | `PaneDividerHandleView.swift:99-116`, `PaneDividerDrag.swift:31-165`, `PaneLayoutView.swift:20-22,106-115`, `PaneTree.swift:129-132` |
| 分割線ダブルクリックで等分 | ハンドルをダブルクリック | `PaneLayoutAction.equalize(split.id)` | — | なし | `PaneDividerHandleView.swift:53-55` |
| 分割線ホバー視覚フィードバック＋カーソル変更 | ホバー | 発光バー、`.pointerStyle`/`NSCursor` | — | なし | `PaneDividerHandleView.swift:56-77,120-171` |
| 分割線の掴みしろ拡張(8pt) | なし | `PaneTree.dividerHitThickness=8` | — | なし | `PaneTreeGeometry.swift:61-62,193-212` |
| タイルクリックでフォーカス | タイル本文クリック | `focusedID = session.id`（`router.selectedSession`にバインド） | フォーカス中は枠線強調（`textSecondary`太線＋内側リング） | なし | `PaneLayoutView.swift:71-72,223-243,297-322` |
| タイルヘッダーmouseDownで即時選択 | ヘッダーmouseDown | `selectImmediately()`→`onSelect()` | — | なし | `PaneLayoutView.swift:324-327,392-399` |
| ウィンドウレベルでのタイルクリック選択 | 任意位置mouseDown | `NSEvent.addLocalMonitorForEvents` | — | なし | `PaneTileClickSelection.swift:6-16,83-137` |
| タイル内コンテキストメニュー | 右クリック | 「名前を変更」「プロジェクトを変更」（ptyのみ）「削除」 | — | 「プロジェクトを変更」は`.pty`のみ | `PaneLayoutView.swift:244,269-276` |
| タイルを閉じる | ヘッダの×ボタン | `onRemove`呼び出し（呼び出し元でDashboardView側の削除確認ダイアログへ） | — | なし | `PaneLayoutView.swift:369-377` |
| タイルヘッダの表示縮退 | タイル幅が240pt未満 | ステータスラベル・セカンダリ名・プロジェクト名を省略しコンパクト表示 | `isCompact` | なし | `PaneLayoutView.swift:329-367` |
| 要注意/停止ハイライト | — | `SessionAttentionPolicy.requiresAttention`が真の間、背景・枠を強調色に（赤枠3pt/フォーカス2pt/通常1pt、`GridTileBorderPolicy`） | — | なし | `PaneLayoutView.swift:278-320`, `GridTileBorderPolicy.swift:16-27` |
| タイル本文 | — | `.pty`はSwiftTerm(`TerminalView`)埋め込み、`.appServer`は`GridChatColumn`（承認バナー＋トランスクリプト＋コンポーザ＋Codex子スレッド表示を内包） | — | `CodexSessionSurface`はCodex子スレッド表示 | `PaneLayoutView.swift:254-266`, `GridChatColumn.swift:10-95` |
| グリッドタイル内送信/中断 | 送信ボタン/Enter・中断ボタン | `viewModel.sendText`/`turnInterrupt()` | — | なし | `GridChatColumn.swift:133-148` |
| グリッドタイルでのライブリサイズ中レイアウト凍結 | ウィンドウリサイズ中 | `stableWidth`で凍結 | isLiveResizing | なし | `GridChatColumn.swift:19-30,96-118` |
| グリッドタイル内Codexスキル/スラッシュ候補 | `/`入力 | `updateCodexSkillSuggestions()` | — | Codex限定 | `GridChatColumn.swift:275,351-375` |
| グリッドタイル内キーワードハイライト | 入力中 | `highlightsKeywords` | — | Claude Code限定でON | `GridChatColumn.swift:275` |
| グリッドタイル内Esc処理 | Escキー | `.chatEscapeHandling`（4.5節のEsc一元処理を単一/グリッド両ビュー共通で適用） | — | なし | `GridChatColumn.swift:120-125`, `ChatEscapeHandling.swift:28-36` |
| グリッド内サブエージェント選択（本文差し替え） | ストリップアイコンクリック | `selectedSubAgentTranscript`切替 | — | なし | `GridChatColumn.swift:36-56,128-131` |
| .orchestration子セッションの表示可否 | — | サイドバー・絞り込み無しグリッドでは`.orchestration`起動のセッションを常に除外。特定プロジェクトへ絞り込んだグリッド表示（`gridSessionNodes(in:)`）に限り`.orchestration`子セッションもタイルとして含める | プロジェクト未絞り込み時は非表示、絞り込み時のみ表示 | なし | `DashboardViewModel.swift:425-432,493-503,523-526`（コメントで明記: `:429`「.orchestration サブセッションも含む」, `:523`「内部 orchestration を除外」） |
| グリッド空スコープ表示 | — | `GridScopeSummary` の空メッセージ＋絞り込み解除ボタン | 空 | — | `DashboardView.swift:218-219,480-511` |
| グリッド絞り込み・表示選択 | 2.1節既出（`GridScopeSummary`・`GridSessionPicker`） | — | — | 既出 |

備考: 「D&D」はセッション（タイル）の入れ替え・分割挿入専用で、プロジェクト間ドラッグ移動や外部ファイルドロップは見当たらない。DashboardFeature内に`onDrag`/`onDrop`/`.draggable`/`dropDestination`の呼び出しは無い（grep確認）ため、この機能はSessionFeature側に実装が閉じている。セッションツリー構築（親子木、循環参照防止）は`SessionTree.buildForest(from:)`（`SessionTree.swift:72-162`）、展開/折りたたみは`SessionTreeViewModel.swift:17-24`。

**不明点**: `PaneLayoutAction`を実際に処理するreducer本体（`DashboardViewModel`）はSessionFeature外。明示的なキーボードショートカットでのペイン切替（Cmd+数字等）は発見できず、存在しないと推測（未確定）。エージェント種別によるペイン**構造**自体の差異は無い（機能面の差異のみ）。

---

## 6. チームビュー・Agora討論（`Dashboard/TeamTimelineView.swift` ほか Agora*）

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| タイムライン表示 | 縦スクロール | 全参加セッションの発言・ツール実行・端末出力を1系列に統合 | 空/表示中 | LazyVStack不使用（無限自走ループ回避のADR方針、コード上はコメントのみで未確認） | `TeamTimelineView.swift:66-98,283-288` |
| 発言元ヘッダから該当セッションへドリルダウン | ヘッダクリック | — | シングルビューへ遷移 | — | `:634-665`, `AppRouter.swift:94-98` |
| Thinking インジケータ表示 | — | 実行中セッションの「考え中」アニメーション | running時のみ | — | `TeamTimelineView.swift:398-408`, `AgentChatRowPolicy.swift:67-134` |
| セッションチップ一覧（非討論時） | 水平スクロール | 参加セッションのアイコン・名前 | — | — | `TeamTimelineView.swift:127-139,549-580` |
| エージェント追加（通常時） | 「+」メニュー | 利用可能エージェント種別×モード(chat/terminal) | `isCreating`中/プロジェクト未解決で無効 | — | `:145-187,267-281` |

討論エンジンは3層構成: `AgoraDiscussionEngine`（純粋状態機械、I/O禁止）→`AgoraDiscussionCoordinator`（副作用実行・直列キュー）→`TeamTimelineView`（UI）。

| 機能 | ユーザー操作/契機 | 表示データ・挙動 | 状態遷移 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| 討論開始 | コンポーザへ議題を入力して送信（非討論・討論可能時） | ファシリテーター役のClaudeチャットセッションをspawn→役割プロンプト＋議題を注入 | `idle`→`discussing` | — | `AgoraComposerRouting.swift:12-25`, `AgoraDiscussionCoordinator.swift:70-73,175-193`, `AgoraDiscussionEngine.swift:163-178` |
| 参加者登録（ファシリテーターのspawn --role着地／「＋」手動追加） | ファシリテーター自身のツール実行 or ヘッダ横「+」ボタン | 役割名（`AgoraParticipantNaming`で命名衝突時は「役割名 2」等に採番、討論参加登録自体は`AgoraParticipantNaming`未使用でロール文字列そのまま保持）＋参加プロンプト注入 | `maxAgents`到達で登録拒否（討論外の通常セッションとして残留） | `phlox.agora.maxAgents`（既定5） | `AgoraDiscussionCoordinator.swift:79-98`, `AgoraDiscussionEngine.swift:180-198`, `AgoraDiscussionSettings.swift:8,13`, `AgoraParticipantNaming.swift:9-27` |
| 発言上限 | — | PASSを除く実発言数が上限到達で`concluding`（ファシリテーターへ最終まとめ要求）→ファシリテーター応答で`ended(.utteranceLimitReached)` | `discussing`→`concluding`→`ended` | `phlox.agora.maxUtterances`（既定30、残り`warningRemaining`(既定5)以下で警告文言を配送に付加） | `AgoraDiscussionEngine.swift:275-295,239-245`, `AgoraDiscussionSettings.swift:7,12,17` |
| 発言順制御 | — | `freeSpeech`（既定・アイドル検知で配送）/`roundRobin`（発言完了ごとに次者へ）の2方式 | スケジューラ切替はTeamTimelineView内にUI切替導線なし | `phlox.agora.scheduler`（既定`freeSpeech`）。**設定UIは設定ウィンドウ詳細タブに存在**（12.5節参照） | `AgoraDiscussionSettings.swift:10,18`, `AgoraDiscussionEngine.swift:206-210,297-300,26-29` |
| 発言タイムアウト | — | 配送後`turnTimeoutSeconds`（既定180秒）応答が無い参加者の待機状態を解除しスキップ | — | `phlox.agora.turnTimeoutSeconds`（設定UIは12.5節） | `AgoraDiscussionSettings.swift:9,14`, `AgoraDiscussionEngine.swift:212-221` |
| 連続発言制限 | — | 同一参加者が`consecutiveSpeakLimit`（既定2、設定UIなし）連続で発言すると次回配送で発話を促さない | — | 固定値（設定キー無し） | `AgoraDiscussionEngine.swift:40,457-459`, `AgoraDiscussionSettings.swift:15,41` |
| 停滞検知・打開 | — | 全参加者PASSが`(参加者数-1)×stallPassRounds`（既定2）周回続くとファシリテーターへ「討論が停滞しています。次の論点を提示してください。」を配送 | — | 固定値（設定キー無し） | `AgoraDiscussionEngine.swift:247-249,347-376`, `AgoraDiscussionSettings.swift:16,42` |
| ユーザー発言の合流 | 討論中にコンポーザから送信 | 発言数にはカウントされず全参加者へ配送対象としてログに追加 | — | — | `AgoraDiscussionCoordinator.swift:101-109`, `AgoraDiscussionEngine.swift:303-311` |
| 討論停止 | ヘッダ「停止」ボタン | 以後の観測・配送を停止 | 任意フェーズ→`ended(.stopped)` | — | `AgoraDiscussionHeaderView.swift:59-60`, `AgoraDiscussionCoordinator.swift:112-116`, `AgoraDiscussionEngine.swift:223-226` |
| 討論中のClaude追加 | 「+」円ボタン | 新規Claude appServerセッションをspawnし討論参加 | 追加中は無効化 | — | `TeamTimelineView.swift:149-161,238-258` |
| タイムライン表示内容の絞り込み | — | `userMessage`/`agentMessage`/`error`のみ表示、`reasoning`/`commandExecution`/`fileChange`等の生成過程は非表示 | — | — | `AgoraTimelineDisplayPolicy.swift:11-26` |
| Thinkingインジケータ表示 | — | 参加セッションが`running`状態の間だけ末尾に表示 | running時のみ | — | `AgoraTimelineDisplayPolicy.swift:29-47` |
| タイムラインのフラットマージ | — | 参加者集合に含まれるソースの発言のみ`TeamTimelineModel.merge`で時系列統合、非参加者の発言は除外 | — | — | `AgoraTimelineBuilder.swift:14-32` |
| 350ms周期の観測tick | — | 参加者のidle検知・turn完了検知・タイムアウトチェックを350ms毎に実行（非討論時は5秒間隔にフォールバック、`TeamTimelineView.swift:16-17`） | — | — | `TeamTimelineView.swift:14-17,290-309`, `AgoraDiscussionCoordinator.swift:118-124` |
| コンポーザ送信先ラベル表示 | — | 討論中は「討論」、非討論時は対象ノード名 | — | — | `TeamTimelineView.swift:189-211`, `ComposerDestinationLabel+Agora.swift` |
| 討論中の発言カウンタ表示 | — | 「n/max」 | — | `maxUtterances`（Coordinator側で管理） | `AgoraDiscussionHeaderView.swift:24-44,52-64` |
| 討論中の参加者チップ表示 | — | 名前・役割・司会フラグ | — | — | `:9-22,66-77` |
| チームコンポーザ入力 | テキスト入力（NSTextViewラップ）、Cmd+Enter等で送信 | プレースホルダ・IME合成対応・高さ自動伸縮（最大6行） | フォーカス/未フォーカス、送信可否で送信ボタン色変化 | — | `TeamComposer.swift:12-116,133-164,298-382` |
| 送信失敗時のドラフト復元 | — | 失敗時に送信テキストを下書きへ戻す | — | — | `TeamComposer.swift:101-115`, `TeamComposer.swift:166-170`（`TeamComposerDraftPolicy`） |
| セッション起動失敗アラート | — | エラーメッセージ表示 | — | — | `TeamTimelineView.swift:52-60,544-547` |

備考: `AgoraDiscussionSettings`はAppStorageキーの読み出しのみを提供する純粋構造体。DashboardFeature内には変更UIが無いが、**設定ウィンドウ「詳細」タブに最大発言数・最大エージェント数・ターンタイムアウト・スケジューラの編集UIが存在する**（12.5節、`App/SettingsView.swift:265-273`）。「チームビュー討論」機能の存在はLocalizable.xcstringsのキー「討論」（line1126）や`ControlActionHandler.swift:62-64`のコメントからも示唆される。

---

## 7. 右インスペクタ（`Dashboard/InspectorView.swift`）

ファイルツリー（`FileTreeInspectorView`）だけを出す。タブの切り替えは無い。2026-10-13 に「使用量」（CLI ごとのカード・リセット時刻・手動更新・Cursor の誘導）と「セッション」（経過時間・総コスト・Git ブランチ）のタブを機能ごと廃止した（ADR 0192）。使用量は画面下部のバー（§2）で見る。

## 8. 右端ドロワー

### 8.1 エディタパネル（`Editor/EditorPanelView.swift`, `GitCommitPanel.swift`）

| 機能 | ユーザー操作 | 表示データ | 状態 | 根拠 file:line |
|---|---|---|---|---|
| レイアウト自動切替（左右分割⇄上下積み） | ウィンドウ/ドロワー幅変化 | 閾値 `changeListMinWidth(180)+detailPaneMinWidth(360)+divider(1)=541` | split/stacked | `EditorPanelView.swift:9-27,87-90,112-149` |
| 変更ファイル一覧表示 | — | パス・変更種別アイコン（modified/added/untracked/deleted/renamed）・バイナリ表示 | ready/noProject/notARepository、リストエラー表示 | `:29-50,173-230` |
| 変更を更新 | 更新ボタン | — | 更新中はスピナー・ボタン無効化 | `:184-199` |
| ファイル選択（差分/内容プレビュー） | 行クリック | Diff/Content（構文ハイライト付き）、500行区切り「さらに表示」 | 選択中はハイライト背景 | `:249-353` |
| コミット対象チェック | チェックボックス | `pathsSelectedForCommit` | 選択/未選択 | `:232-247` |
| ファイル編集・保存 | `TextEditor` | 下書き・未保存インジケータ | ダーティ/クリーン | `:286-305,356-364` |
| 外部変更による保存競合の警告 | 保存時に検知→alert | 「上書き」/「キャンセル」 | conflictDetected | `:100-107,356-372` |
| 共有スコープ注意バナー | — | 「このプロジェクトの全変更を表示…」 | `.shared` スコープ時のみ | `EditorPanelView.swift:176-178`, `GitCommitPanel.swift:158-177` |
| コミットメッセージ入力 | TextField（複数行対応） | — | ワークフロー実行中は無効化 | `GitCommitPanel.swift:19-23` |
| コミット実行 | 「コミット」ボタン | — | `canCommit`かつ非ビジー時のみ有効 | `:132-138` |
| プッシュ実行 | 「プッシュ」ボタン | プッシュ不可理由表示 | `canPush`かつ非ビジー時のみ有効 | `:31-37,140-146` |
| PR作成 | 「PRを作成」ボタン | PR不可理由・作成後のPR URL表示（選択可能テキスト） | `canCreatePullRequest`かつ非ビジー時のみ有効 | `:39-45,93-99,148-154` |
| Git処理状態表示 | — | 成功/エラーアイコン・メッセージ、エラー時は展開可能な詳細ログ（固定高220ptスクロール） | 処理中はスピナー | `:47-91,108-130` |
| 状態メッセージを閉じる | ×ボタン | — | — | `:78-90` |

**不明点**: `WorkingTree/`配下（`GitWorkflowService`, `WorkingTreeService`, `WorkingTreeTypes`）の詳細実装は未読（UI側からの呼び出し形のみ把握）。

### 8.2 ターミナルパネル（`UserTerminal/TerminalPanelView.swift`）

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| ユーザー用シェル表示 | — | SwiftTerm(`TerminalView`) 埋め込み | ドロワー開閉に関わらずPTYは維持（`TerminalPanelSession`がApp/Window scene寿命で保持） | ターミナルフォントサイズ（`TerminalFontSettings`、`Cmd+=`/`Cmd+-`） | `TerminalPanelView.swift:8-69,72-117`, `TerminalFontSettings.swift:6` |
| 初回起動/シェル再起動 | ドロワー表示時に自動 `.task` | — | 未起動→起動中→起動済み | — | `TerminalPanelView.swift:58-64,113-115` |
| 入力送信・リサイズ | ターミナル操作 | — | 送信/リサイズ失敗時はエラー行を端末に出力 | — | `:21-42` |

TerminalUIパッケージ（`Packages/TerminalUI/Sources/TerminalUI`、PTY疑似端末の共通実装。ターミナルパネル・グリッドタイル・single表示すべてで共有）:

| 機能/型 | UIに出る形 | 根拠 file:line |
|---|---|---|
| SwiftTerm埋め込み疑似端末 | `IMETerminalView`(SwiftTerm.TerminalViewサブクラス)をAppKitで表示 | `TerminalCoordinator.swift:97,42-49` |
| テーマ連動カラースキーマ | 背景/前景/ANSI16色がアプリテーマに追従 | `TerminalCoordinator.swift:6-38,127-133` |
| フォントサイズ変更 | 等幅フォントのサイズ変更 | `TerminalCoordinator.swift:163-166` |
| IME変換中テキストのオーバーレイ | 未確定文字を淡いピンクベージュ背景＋濃いピンクキャレットで独自描画 | `IMETerminalView.swift:5-9,65-83`, `MarkedTextOverlayView.swift:33-38,50-83` |
| IMEキャレット/選択範囲可視化 | 2px縦棒キャレット／選択範囲塗り | `MarkedTextOverlayView.swift:91-112` |
| スクロールバー表示制御 | スクロール可能時のみオーバーレイ表示 | `IMETerminalView.swift:42-51`, `TerminalHostingView.swift:70-81` |
| リサイズ時の全行再描画（ゴースト対策） | ウィンドウ/グリッドリサイズ時に強制再描画 | `TerminalHostingView.swift:53-68` |
| フォーカス自動付与／クリックでフォーカス | View出現時に自動firstResponder、mouseDownで委譲 | `TerminalHostingView.swift:36-51` |
| ANSI画面のSGR付きテキストエクスポート | モバイル転送用に色/装飾付きテキスト化 | `AnsiScreenEncoder.swift:4-40`, `TerminalCoordinator.swift:221-225` |
| プレーンテキスト抽出（折返し結合オプション） | viewportのプレーンテキスト化、ソフトラップ行の論理行結合 | `TerminalCoordinator.swift:179-219` |
| 最下部への自動追従スクロール | ペイン切替・マウント時に最新出力へ追従 | `TerminalCoordinator.swift:227-236`, `TerminalView.swift:46-50` |
| セッション再起動時のバッファ完全リセット | alt buffer残留除去＋空画面復帰 | `TerminalCoordinator.swift:248-268` |
| デバッグ用ターミナルダンプ | セル単位fg/bg/style出力（開発者向け、通常UI非表示） | `Debug/TerminalDump.swift:10-133` |
| 複数コンテナ間の端末所有権付け替え | 単体表示⇄グリッド表示の再親付けで描画崩れ防止 | `TerminalView.swift:58-119` |
| SwiftUI `NSViewRepresentable`埋め込み | パネル/グリッドへのマウント | `TerminalView.swift:16-56`（呼び出し元: `SessionFeature/SessionView.swift:34`, `DashboardFeature/UserTerminal/TerminalPanelView.swift:101`） |

---

## 9. 新規チャット画面（`NewChat/NewChatView.swift`）

旧「空状態・起動カード」（`AgentStartCards.swift`、チャット/ターミナルのモードボタン）は 2026-10-12 に廃止し、共通の新規チャット画面に置き換えた（[ADR 0183](../adr/0183-unified-new-chat-start-screen.md)、要件は [unified-new-chat-start.md](unified-new-chat-start.md)、設計は [unified-new-chat-start-design.md](unified-new-chat-start-design.md)）。単体表示では、どのプロジェクトのタブにも属さない画面（モード）として出る。出している間は上段のタブを選択せず、送信先は `router.newChatProjectID`（`ProjectTab.newChat` は旧い保存を読むためだけに残る。ADR 0188）。送信するまでセッションも CLI のプロセスも作らない。

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| 送信先のフォルダを選ぶ | ポップアップの項目 | 新規チャット画面のプロジェクトのチップの最後の「フォルダを選ぶ…」（NSOpenPanel）。プロジェクトは送信したときに作る | 常時（0 件ならこれだけ） | — | `NewChatView.swift`（`newChat.projectPicker`）、`ProjectFolderPanel.swift` |
| 挨拶の見出し | — | Phlox のアイコン＋ 10 種類の文言からランダムに 1 つ（画面を出すたびに選び直し、入力中は替えない） | — | — | `NewChatView.swift`（`NewChatGreetings`） |
| メッセージ入力欄 | 文字入力・貼り付け・↩ で送信。画像の貼り付け・「＋」で添付。`/` でコマンド候補、`@` でファイル候補（プロジェクトと作業場所を基準に取り直す） | 本文・添付 | 下書き（アプリに 1 つ。メモリだけ。全ウィンドウで共有） | — | `NewChatView.swift`（`newChat.composer`・`newChat.attachments`）、`NewChatDraftStore.swift` |
| ハーネス・モデルのチップ | クリックでポップオーバー（上に絞り込み欄、ハーネスごとの区切りにモデル、選択中にチェック、既定に「既定」のタグ） | ハーネスのロゴ（`AgentBrandIcon`）とモデルの表示名 | 未検出のハーネスは区切りごと「未検出」で選べない | 初期値は `phlox.newChat.lastHarness` と最後に使った設定 | `NewChatView.swift`（`newChat.harnessModelPicker`・`newChat.modelMenu`・`newChat.modelSearch`）、`NewChatDraftStore.swift`（`NewChatModelMenuSection`） |
| effort・権限（Cursor は mode）のチップ | クリックで選択（権限の項目に「計画」を含む）。⇧Tab で effort を巡回。幅 620pt 未満では 1 つの「…」メニューにまとめる | 選んだハーネスの候補（Codex の effort は `model/list` の結果、権限は内蔵の 3 つ） | モデルが effort を持たなければ出さない | `phlox.lastUsedChatSettings.<agentID>.*` | `NewChatView.swift`（`newChat.effortPicker`・`newChat.permissionPicker`・`newChat.settingsOverflow`） |
| プロジェクトのメニュー | クリックで送信先のプロジェクトを選び直す（本文・添付・設定は残り、上段のタブの選択は変えない） | プロジェクト名 | プロジェクト未選択なら送れない | — | `NewChatView.swift`（`newChat.projectPicker`） |
| 作業場所のメニュー | 「既存ディレクトリ」（初期値）/「新しい worktree」 | — | git リポジトリでなければ「新しい worktree」は選べない（理由を説明文で出す） | worktree の判断はこの選択と、復元時は保存済みの作業フォルダ（プロジェクト設定は廃止） | `NewChatView.swift`（`newChat.workspacePicker`） |
| 送信 | ↩ またはボタン（アクセントの丸） | — | 本文も添付も空なら押せない。送れない理由（プロジェクト未選択・ハーネス未検出・画像を送れない）は送ろうとしたときだけ入力欄の下にエラーの色で 1 行（プロジェクト未選択ならチップも赤枠） | — | `NewChatView.swift`（`newChat.sendButton`・`newChat.sendUnavailableReason`） |
| 提案チップ 5 個 | クリックで定型文を入力欄に足す（送信はしない） | コードレビュー・バグ修正・テスト追加・コードの説明・リファクタ | — | — | `NewChatView.swift`（`newChat.suggestion.<n>`） |
| 履歴から再開… | 提案チップの列の最後に、同じ見た目のチップで出す。クリックでポップオーバー。選ぶとその会話を再開 | 本体フォルダと、そのプロジェクトの過去の worktree（`Project.worktreePaths`）の会話。読み込み中・履歴なし・失敗と「再試行」を区別 | 選択中のハーネスが Claude Code か Codex で、履歴があるときだけ出す | — | `NewChatHistoryPopover.swift`（`newChat.historyResume`・`newChat.history.entry.<id>`・`newChat.history.retry`）、`DashboardViewModel.swift`（`newChatHistoryEntries`） |

---

## 10. 新しいチャットの作成（全入口とガードレール）

| 入口 | 場所 | 根拠 file:line |
|---|---|---|
| メニューバー「ファイル ▸ 新規チャット」 | `⌘N`。プロジェクト 0 件でも押せる（案内を出す） | `App/PhloxApp.swift`（`FileCommands`）、`NewChatEntryActions.fileMenu()` |
| サイドバー下端「＋ 新規チャット」 | ボタン | `DashboardView.swift`（`sidebarFooter`）、`NewChatEntryActions.sidebarFooter()` |
| プロジェクト行の「＋」・右クリック/「⋯」の「新規チャット」 | そのプロジェクトで開く | `SidebarRows.swift`、`DashboardSidebarView.swift`、`NewChatEntryActions.projectPlus`・`projectMenu` |
| グリッドのセッション 0 件の空状態 | 「新規チャット」ボタン | `DashboardView.swift`、`NewChatEntryActions.gridEmptyState` |
| 下段の「＋」（タブを追加）／⌘T「新しいタブ…」 | メニューの先頭「新規チャット ⌘N」 | `SessionTabsContainer.swift`（`NewTabChooser`） |
| 単体表示でプロジェクトを選んだとき | タブが 1 つも無いプロジェクトだけ、送信先をそのプロジェクトにして新規チャット画面を出す | `AppRouter.swift`（`ensureProjectSelection`・`showNewChat`） |

どの入口も画面（`router.showNewChat(projectID:)`）を出すだけで、セッションは作らない。ターミナルでエージェントを動かすセッションを画面から始める入口は無い（ADR 0185。Control API・CLI の `backend: pty` と保存済みセッションの復元は残る）。

ライフサイクル:
1. **作成**: 送信すると `NewChatDraft.makeLaunchRequest` が入力一式を `NewChatLaunchRequest` に固めて下書きを空にし、`NewChatView` が `DashboardViewModel.launchNewChat` を呼ぶ。内部は `spawnNewSession(backend: .appServer, isolationOverride: usesWorktree, initialSettings:, keepsRowOnLaunchFailure: true, onRowAppended:)`。行が出た時点で `router.completeNewChat` が送信先のプロジェクトのタブにその行を開いて選ぶ（`DashboardViewModel.swift`、`AppRouter.swift`）。起動の成功を確かめてから初回メッセージを `sendFirstMessage` で送る。
   - 作成中は `NewChatView.isLaunching` が多重送信を抑える。「新しい worktree」では worktree の作成が終わってから行が出る（その間はトースト）。
   - 深さ・レート制限は今のまま（親子連鎖の深さ上限 3、1 秒あたり 5 回、`SpawnPolicy.swift`）。親が appServer（チャット）セッションなら子も appServer へ昇格。
   - CLI バイナリ未検出ではエラーにし、ワークスペースを後始末する。
   - 状態: starting → running（サイドバーの行の右端に文字で反映）。
   - 失敗: VM ができる前（worktree 作成・Codex の app-server 起動）は今のダイアログを出して本文を下書きに戻す。起動後の失敗は行を残し、本文を入力欄に戻して「再起動」「閉じる」を出す（`ChatLaunchError`、`markLaunchFailed`、`restartNewChat`）。
2. **表示**: single/grid の各モードで表示形態が変わる（4・5 章参照）。
3. **名前変更・プロジェクト移動・ワークスペース変更（再起動を伴う）**: 右クリックメニューから。ワークスペース変更・プロジェクト移動は内部的に`restartSession`（hook再設置→hookストリーム差し替え→再起動→永続化）を共有。
4. **停止/削除**: サイドバー右クリック「削除」、グリッドタイルの削除操作、下段のチャットのタブの ✕・⌘W いずれも確認ダイアログ経由で`viewModel.removeSession(id)`。対象の子孫セッションも深い順にまとめて除去（カスケード削除）。
   - 削除の認可: `SpawnPolicy.isAuthorizedToRemove` — 自己kill/リクエスタなし/祖先関係なら許可、`privilegedRequesters`は無条件許可。
5. **未読完了**: `hasUnseenCompletion`。サイドバーでは題名を主文字色・やや太くして見分け、選択で既読化（丸の印は廃止）。

プロジェクト（ワークスペース）ライフサイクル: 追加（NSOpenPanel→`addProject`。上段のタブの「＋」・⌘O・サイドバー見出しの「＋」）→表示（上段のタブ・サイドバーの展開/選択/絞り込み）→名前変更（上段のタブの右クリック「プロジェクト名を変更…」・サイドバーのメニュー。表示名のみ、フォルダ名は不変）→削除（上段のタブの ✕・サイドバーのメニュー。配下セッション全停止・子孫件数警告、フォルダ自体は削除されない。そのプロジェクトのターミナル・ブラウザ・シミュレーター・ファイル文書も閉じる。送信先がそのプロジェクトなら送信先を空にし、下書きの本文は残す）。worktree で分けるかのプロジェクト単位の設定は廃止した（新規は新規チャット画面の作業場所の選択、復元は保存済みの作業フォルダで決める）。

Control API経由（デスクトップUI外、リモート/モバイル制御用、参考記載）: 承認一覧・応答（`DashboardViewModel+ControlApprovals.swift`）、セッションの役割永続化（`ControlActionHandler.persistSessionRole`）、ユーザー質問への応答（`ControlActionHandler.respondToUserQuestion`）。`POST /sessions`・CLI `spawn`・子セッションの起動は常に既存ディレクトリで動く（worktree を作らない）。デスクトップUIからの直接操作は無く、SessionFeature側のチャットUIが主戦場と推測（未確認）。

---

## 11. アラート/確認ダイアログ（全画面共通）

| 機能 | 発生契機 | 表示データ | 根拠 file:line |
|---|---|---|---|
| セッション起動失敗アラート | `spawnNewSession`系がthrow | エラーメッセージ | `DashboardView.swift:93-101,733-755` |
| セッション後始末（クリーンアップ）失敗警告 | `viewModel.workspaceCleanupWarning` | タイトル/メッセージ | `DashboardView.swift:102-111` |
| セッション削除確認 | 削除操作 | 「このセッションと子孫N件を削除しますか?」 | `:64-73,112-128` |
| プロジェクト削除確認 | プロジェクト削除操作 | 子孫件数を含む文言、フォルダ自体は削除されない旨 | `:75-86,129-147`, `DashboardViewModelSupportingTypes.swift:19-33` |
| ワークスペース変更確認 | セッションのプロジェクト変更操作 | 「再起動され進行中の作業は失われます」 | `DashboardView.swift:148-160` |
| セッション名変更ダイアログ | 名前変更操作 | TextField（空欄で短縮ID表示） | `:161-170,901-917` |
| プロジェクト名変更ダイアログ | 名前変更操作 | TextField | `:171-180,880-899` |
| スキル削除確認ダイアログ | Agent Console Claudeスキルパネル | `.confirmationDialog` | `App/AgentConsole/Claude/ClaudeSkillsPane.swift:50-75` |
| 会話書き出し `NSSavePanel` / 書き込み失敗 `NSAlert` | メニュー「会話を書き出す」 | — | `App/AgentConsole/Shared/ChatTranscriptExportAction.swift:44-63` |

---

## 12. 設定ウィンドウ（`Settings` scene、5タブ）

`App/PhloxApp.swift:118`、タブ定義は `SettingsGroup.all`（`App/SettingsView.swift:80-89`、識別子 `Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift:9-15`）: 一般`general` / 外観`appearance` / エージェント`agents` / 接続`connection` / 詳細`advanced`。

### 12.1 一般タブ

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| 表示言語切替 | Picker（システム/日本語/English） | 現在の言語 | — | `phlox.appLanguage`（既定`system`） | `App/SettingsView.swift:149-158`、`App/LanguageSettings.swift:4-30` |
| ~~デフォルトの開き方~~ | — | — | — | 2026-10-12 に廃止（チャットとターミナルを入口で分けたので選ぶ場面が無い。ADR 0185） | — |
| セッション完了バナー通知 | Toggle | — | — | `phlox.notify.banner`（既定true） | `App/SettingsView.swift:174-176` |
| 完了サウンド | Toggle | — | — | `phlox.notify.sound`（既定true） | `App/SettingsView.swift:177-179` |
| 通知テスト | Button | — | — | — | `App/SettingsView.swift:180-183`（`SessionCompletionNotifier.notifyCompleted`） |
| 起動時自動アップデート確認 | Toggle | — | 永続先はSparkle内部/UserDefaults未確認 | — | `App/SettingsView.swift:188-194` |
| 今すぐアップデート確認 | Button | — | `!canCheckForUpdates`で無効 | — | `App/SettingsView.swift:195-199` |

### 12.2 外観タブ

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| テーマ選択 | テーマ行タップ（`ThemeStore.all`） | テーマ一覧 | 選択中がハイライト | `phlox.theme`（既定`AppTheme.phlox.id`） | `App/SettingsView.swift:208-212,455-528` |
| アプリアイコン選択 | アイコン行タップ（`AppIconStore.all`） | アイコン一覧 | 選択即時`NSApp.applicationIconImage`反映 | `phlox.appIcon`（既定`AppIconStore.defaultOption.id`） | `App/SettingsView.swift:220-227,587-639` |

### 12.3 エージェントタブ

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| エージェント別 権限バイパストグル | Toggle（エージェントごと1行） | エージェント一覧 | — | `phlox.bypass.<agent>`（既定true） | `App/SettingsView.swift:238-246,319-362` |
| エージェント管理を開く | Button | — | — | — | `App/SettingsView.swift:249-254`（`openWindow(id: "agent-console")`） |

### 12.4 接続タブ（ペアリング）

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| タブ自体の表示条件 | — | — | `mobileToken`が非nilかつ`MobileConnectionGuidePolicy.showsSettingsConnectionSection`がtrueの時のみ表示 | — | `App/SettingsView.swift:130-133` |
| 端末名入力 | TextField（既定"iPhone"） | — | — | — | `App/SettingsView.swift:368,372-373` |
| QRコード表示 | Button | QR画像（`PairingQRView`）。CoreImageのQRコード、correctionLevel M | `!isPairingQREnabled`で無効。60秒で自動非表示 | — | `App/SettingsView.swift:379-392`、`App/MobileTokenViewModel.swift:43,113-123,127,195-203`、`App/PairingQRView.swift:42-60` |
| QR警告文言表示 | — | "QRにはフルアクセス権限のトークンが含まれます。60秒後に自動的に非表示になります。" | — | — | `App/PairingQRView.swift:9-22` |
| ペアリング無効理由表示 | — | 理由テキスト（ループバックのみ/明示ホスト等、`MobileProxy.BindMode`: loopbackOnly/explicitHost/tailscaleにより出し分け） | 条件付き表示 | — | `App/SettingsView.swift:374-378`、`App/MobileTokenViewModel.swift:95-110`、`MobileProxy/MobileProxy.swift:22` |
| エラー表示 | — | `lastError` | 条件付き赤字表示 | — | `App/SettingsView.swift:393-397`、`App/MobileTokenViewModel.swift:16-17` |
| 接続済み端末一覧・名前変更・失効 | 「名前を変更」で行内編集→保存／キャンセル（Esc）、または「失効」Button（destructive） | 端末名・ペアリング日時・接続状態。名前の前後の空白を除去し、空なら保存不可。保存失敗時は入力を保持してエラー表示 | 空なら非表示 | 名前変更で接続情報は維持 | `App/SettingsView.swift` の `MobileDeviceRow`、`App/MobileTokenViewModel.swift` の `rename(id:name:)` |
| ペアリング成立の自動反映 | 端末側QR読取→ControlServer経由で認証成立 | `MobileDevicePairingRelay`が`handleAuthenticatedPairingRecorded()`を呼び、端末一覧が自動更新 | — | — | `App/CompositionRoot.swift:123-129`、`App/MobileTokenViewModel.swift:173-179` |

### 12.5 詳細タブ

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| 最大発言数 | TextField(.number) | — | 範囲チェック無し | `phlox.agora.maxUtterances`（既定30） | `App/SettingsView.swift:265` |
| 最大エージェント数 | TextField(.number) | — | 範囲チェック無し | `phlox.agora.maxAgents`（既定5） | `App/SettingsView.swift:266` |
| ターンタイムアウト（秒） | TextField(.number) | — | 範囲チェック無し | `phlox.agora.turnTimeoutSeconds`（既定180） | `App/SettingsView.swift:267` |
| スケジューラ | Picker（自由発言/ラウンドロビン、xcstrings未登録の直書き`Text`） | — | — | `phlox.agora.scheduler`（既定`.freeSpeech`） | `App/SettingsView.swift:268-273` |
| 使用量の自動更新（オフでも起動時に 1 回は取得） | Toggle | — | — | `phlox.usage.autoRefresh`（既定true） | `App/SettingsView.swift`（`usageForm`） |
| Claude使用量取得 | Toggle | — | — | `phlox.usage.claudeScrape`（既定true） | `App/SettingsView.swift:284-286` |
| 未取得CLIも表示 | Toggle | — | — | `phlox.usage.showUnavailable`（既定false） | `App/SettingsView.swift:287-289` |
| 画面下部に使用量を表示 | Toggle | — | — | `phlox.usage.showInHeader`（既定true） | `App/SettingsView.swift`（`usageForm`） |
| 使用量の表示（バー／数値） | Picker | — | — | `phlox.usage.bottomBarStyle`（既定 `bar`） | `App/SettingsView.swift`（`usageForm`） |
| プライバシーポリシーリンク | Link | 外部URL `https://phlox.cc/privacy` | — | — | `App/SettingsView.swift:300-303` |
| アプリ情報表示 | — | バンドル名/バージョン/ビルド | 読み取り専用 | — | `App/SettingsView.swift:309-311,660-666` |

---

## 13. Agent Console（エージェント管理ウィンドウ）

`Window(id: "agent-console")`（`App/PhloxApp.swift:131`、`App/AgentConsole/AgentConsoleWindowView.swift`）。

### 13.1 共通（`AgentConsoleWindowView`）

| 機能 | ユーザー操作 | 表示データ | 状態 | 根拠 file:line |
|---|---|---|---|---|
| エージェント切替 | Picker（メニュー形式） | Claude/Codex/Cursor | — | `App/AgentConsole/AgentConsoleWindowView.swift:95-106` |
| セクション切替 | サイドバー行タップ | セクション一覧（アイコン付き） | 選択中ハイライト、ホバー表示 | `AgentConsoleWindowView.swift:108-123,239-286` |
| パンくず表示 | — | "エージェント名 / セクション名" | — | `AgentConsoleWindowView.swift:64-71` |
| メッセージバナー | — | 各エージェントの`errorMessage`/`infoMessage` | 閉じるボタンで`clearMessages()` | `AgentConsoleWindowView.swift:216-226,289-317` |
| 起動時ロード | 自動（`.task`） | PATH/バイナリ解決→各エージェントの設定・バージョン・プラグイン読込 | ロード中/失敗はモデル側フラグで表現 | `AgentConsoleWindowView.swift:81,150-188` |
| 共通UI部品: 状態セクション見出し・行 (`AgentConsoleStatusSection`/`AgentConsoleStatusRow`) | なし | セクション見出し（アイコン+タイトル）、ラベル/値/mono値/注記の1行表示 | — | `AgentConsoleStatusParts.swift:4-55` |
| 共通UI部品: 件数タイル (`AgentConsoleStatusTile`) | なし | アイコン+タイトル+大きな数値+補足（各パネルの4タイル概要で使用） | — | `AgentConsoleStatusParts.swift:58-96` |
| 共通UI部品: 絞り込み検索欄 (`AgentConsoleSearchField`) | テキスト入力、×で全消去 | 虫眼鏡アイコン+プレースホルダ | 未入力時は×非表示 | `AgentConsoleStatusParts.swift:99-130` |
| 共通UI部品: バージョン等の補助チップ (`AgentConsoleMetaChip`) | なし | シンボル+テキストのカプセル表示 | — | `AgentConsoleStatusParts.swift:133-152` |
| 共通UI部品: CLI未検出案内 (`AgentConsoleUnavailableNotice`) | なし | 「\<コマンド名\>コマンドが見つかりません」+インストール案内文 | 各パネルでCLI未検出時に表示 | `AgentConsoleStatusParts.swift:155-172` |
| 共通UI部品: 1件追加フォーム (`AgentConsoleAddField`) | テキスト入力→Enter/追加ボタン | プレースホルダ付きテキストフィールド+追加ボタン | 空文字は追加ボタン無効 | `AgentConsoleStatusParts.swift:175-193` |
| 共通UI部品: リスト行カード (`AgentConsoleCard`) | ホバー | 枠線なしの面、ホバー/選択中で塗り濃度変化（0.12秒アニメーション） | `isHighlighted`/ホバー | `AgentConsoleStyle.swift:15-38` |
| 共通UI部品: 静的グループ面・見出し・空状態 (`AgentConsoleGroup`/`AgentConsoleGroupHeader`/`AgentConsoleEmptyState`) | なし | 淡い面のグループ枠、字間広めの見出し、0件時の薄いアイコン+メッセージ | — | `AgentConsoleStyle.swift:41-99` |
| 共通UI部品: ツールバー丸アイコンボタン (`AgentConsoleIconButton`) | クリック | 26×26ptの丸ボタン、ホバースタイル+`.help()`ツールチップ | — | `AgentConsoleStyle.swift:102-116` |
| 共通UI部品: 主ボタンスタイル (`AgentConsoleActionButtonStyle`) | クリック/ホバー/押下 | 枠線なしの塗り面で押下可否を表現、`isProminent`でアクセント色/中間色を切替 | 無効時は不透明度0.4 | `AgentConsoleStyle.swift:119-155` |
| ペイン本文共通レイアウト (`agentConsoleScrollBody`) | 縦スクロール | 左右余白付きの縦スクロールコンテナ（設定ウィンドウと同じ手触りに統一） | — | `AgentConsoleStyle.swift:157-170` |

Agent Console のセクション（`AgentConsoleSection`、`Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift:38-58`）: Claude=ステータス/プラグイン/スキル/パーミッション/メモリ/フック/ステータスライン/出力スタイル、Codex=ステータス/設定/プラグイン/MCP/メモリ/信頼済みディレクトリ、Cursor=ステータス/パーミッション/モデル/MCP/設定。

### 13.2 Claude パネル

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| ステータス概要（4タイル：プラグイン数/マーケットプレイス数/パーミッションルール数/フック数） | — | 各カウント | — | — | `Claude/ClaudeStatusPane.swift:97-128` |
| CLI詳細（バージョン/実行パス） | DisclosureGroup展開 | — | — | — | `ClaudeStatusPane.swift:46-54` |
| 設定情報（settings.json パス/モデル/Effort/出力スタイル） | — | — | 未作成なら"未作成" | — | `ClaudeStatusPane.swift:55-64` |
| メモリファイル一覧 | — | あり/未作成 | — | — | `ClaudeStatusPane.swift:65-73` |
| Finderで開く／再読込 | Toolbarボタン | — | — | — | `ClaudeStatusPane.swift:79-94` |
| フック一覧・追加・削除 | イベント別グループ、追加フォーム、削除ボタン | matcher/timeout/command | 空なら"登録されているフックはありません" | settings.json `hooks` | `Claude/ClaudeHooksPane.swift:16-152` |
| メモリファイル編集（CLAUDE.md/AGENTS.md相当） | ファイル選択Picker、TextEditor編集、保存(`Cmd+S`)/元に戻す | ファイル内容 | 未保存表示、未作成注記 | ファイルベース | `Claude/ClaudeMemoryPane.swift:17-98` |
| 出力スタイル選択 | カード選択（単一選択） | ビルトイン+ユーザー定義スタイル一覧 | — | settings.json | `Claude/ClaudeOutputStylePane.swift:13-52` |
| パーミッションルール（allow/ask/deny） | バケット選択+ルール追加、移動、削除 | ルール一覧（バケットごと） | バケット別空表示 | settings.json | `Claude/ClaudePermissionsPane.swift:15-181` |
| プラグイン管理（インストール済み/追加可能） | セグメントPicker、検索、有効/無効Toggle、更新/アンインストール、インストール | プラグイン一覧（バージョン/スコープ/マーケットプレイス） | CLI無しで`AgentConsoleUnavailableNotice`、操作中はToolbar全体無効 | — | `Claude/ClaudePluginsPane.swift:22-373` |
| マーケットプレイス管理 | 追加(URL/owner-repo)、削除、一括更新 | マーケットプレイス一覧 | — | — | `ClaudePluginsPane.swift:179-238` |
| スキル管理（SKILL.md） | 検索、選択編集、保存(`Cmd+S`)、削除確認ダイアログ（ゴミ箱へ） | スキル一覧（スコープ/ディレクトリ名/説明） | 空表示2種 | ファイルベース | `Claude/ClaudeSkillsPane.swift:40-297` |
| ステータスライン設定 | Toggle+コマンド/余白入力、保存/元に戻す | — | 未保存表示、空コマンドで保存無効 | settings.json | `Claude/ClaudeStatusLinePane.swift:14-105` |

### 13.3 Codex パネル

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| ステータス概要（4タイル：プラグイン/MCP/信頼済み/マーケットプレイス） | — | 各カウント | — | — | `Codex/CodexStatusPane.swift:99-130` |
| 設定情報（config.toml パス/モデル/思考の深さ/人格/承認方式/サンドボックス） | — | — | 未作成なら"未作成" | config.toml | `CodexStatusPane.swift:55-66` |
| 一般設定編集（承認方式/サンドボックス/モデル等） | Picker（enum項目）/テキスト+適用ボタン（モデル） | 現在値 | バックアップパス表示 | config.toml各キー | `Codex/CodexSettingsPane.swift:25-160` |
| プラグイン管理 | セグメント、検索、インストール/アンインストール、マーケットプレイス編集 | プラグイン一覧 | CLI無しで通知、ロード中/空表示 | — | `Codex/CodexPluginsPane.swift:21-273` |
| MCPサーバー管理 | transport選択(stdio/http)、追加、削除、再読込 | サーバー一覧（endpoint/transport/認証状態） | 空表示2種 | config.toml `[mcp_servers.*]` | `Codex/CodexMCPPane.swift:12-189` |
| メモリファイル編集 | ファイル選択、TextEditor、保存/元に戻す | 内容、symlink先表示 | 未保存/未作成表示 | ファイルベース | `Codex/CodexMemoryPane.swift:9-107` |
| 信頼済みディレクトリ管理 | 検索、"信頼済みだけ"フィルタ、Toggle、削除 | プロジェクトパス一覧 | 2種類の空表示 | config.toml `[projects."<path>"]` | `Codex/CodexTrustPane.swift:12-114` |

### 13.4 Cursor パネル

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| ステータス概要（4タイル：許可/拒否ルール数、MCP数、選べるモデル数） | — | 各カウント | — | — | `Cursor/CursorStatusPane.swift:98-130` |
| 設定情報（cli-config.json/mcp.jsonパス、モデル、承認方式、サンドボックス） | — | — | 未作成なら"未作成" | cli-config.json | `CursorStatusPane.swift:55-68` |
| 一般設定編集 | Toggle/Picker（承認モード/サンドボックス等） | 現在値 | — | cli-config.json各キー | `Cursor/CursorSettingsPane.swift:21-122` |
| パーミッション（allow/deny、askなし） | バケット選択+追加、移動、削除 | ルール一覧 | 空表示 | cli-config.json `permissions` | `Cursor/CursorPermissionsPane.swift:44-188` |
| モデル選択 | 行タップ「既定にする」 | 利用可能モデル一覧 | 一覧に無い現行モデルは別枠表示 | cli-config.json `model`/`selectedModel` | `Cursor/CursorModelPane.swift:9-98` |
| MCPサーバー管理 | 追加(stdio/http)、削除、有効/無効切替(メニュー) | サーバー一覧 | 有効/無効反映は次回リロードまで遅延（既知の非対称挙動、意図した仕様かバグかコード上からは判別できない） | mcp.json | `Cursor/CursorMCPPane.swift:12-183`、`Cursor/CursorConsoleModel.swift:140-155` |

Agent Console 側（Claude/Codex/Cursor各パネル）はいずれも**UserDefaultsではなくファイルベース**（`settings.json`、`config.toml`、`cli-config.json`、`mcp.json`、メモリ/スキルファイル）で永続化される。

種別ごとの詳細設定項目の対応関係（AgentConfigKit）: Claude Code=権限3バケット(allow/ask/deny)、hook設定(ClaudeHookSettings)、出力スタイル、ステータスライン、プラグイン、スキルファイル、メモリファイル、環境診断。Codex=config.toml上の6設定キー(model/model_reasoning_effort/personality/approval_policy/sandbox_mode/service_tier)、MCP設定、プロジェクト信頼、プラグイン、メモリファイル。Cursor=cli-config.json上の15設定キー（動作系7: approvalMode/sandboxMode/autoAcceptWebSearch/rewind/modelSlashCommands/notifications/hints、表示系6: zenMode/showLineNumbers/showThinkingBlocks/showStatusIndicators/showStatusLineRunningTime/vimMode、Git系2: attributeCommitsToAgent/attributePRsToAgent）、権限2バケット、MCPサーバ管理、モデル設定。

---

## 14. メニューバー（Commands）

| 機能 | ユーザー操作 | 表示データ | 状態 | 関連設定 | 根拠 file:line |
|---|---|---|---|---|---|
| エージェント管理を開く | メニュー/`Cmd+Shift+,` | — | 常時有効 | — | `App/PhloxApp.swift:434-447` |
| ターミナルパネル切替 | メニュー/`Cmd+Option+T` | — | `router==nil`で無効 | — | `App/PhloxApp.swift:449-461` |
| エディタパネル切替 | メニュー/`Cmd+Option+E` | — | `router==nil`で無効 | — | `App/PhloxApp.swift:463-475` |
| アップデート確認 | メニュー | — | `!appUpdater.canCheckForUpdates`で無効 | 自動更新確認トグル | `App/PhloxApp.swift:477-488` |
| サイドバー表示切替 | メニュー/`Cmd+B` | — | `router==nil`で無効 | — | `App/PhloxApp.swift:490-499` |
| インスペクター表示切替 | メニュー/`Cmd+Option+B` | — | `router==nil`で無効 | — | `App/PhloxApp.swift:501-505` |
| 表示モード切替 | メニュー/`Cmd+Control+G` | — | `router==nil`で無効 | — | `App/PhloxApp.swift:507-511` |
| ターミナル文字拡大/縮小 | メニュー/`Cmd+=`・`Cmd+-` | — | `dashboard==nil`で無効 | `TerminalFontSettings.step` | `App/PhloxApp.swift:516-534` |
| 新規チャット | メニュー（ファイル）/`Cmd+N`。旧「新規セッション（Claude/Codex/Cursor 別）」の 3 項目（`Cmd+Shift+N`・`Cmd+Option+N` を含む）は廃止 | 選択中のプロジェクト（無ければ既定のプロジェクト）の新規チャット画面を出す | `router == nil` のときだけ無効（プロジェクト 0 件でも押せる） | — | `App/PhloxApp.swift`（`FileCommands`）、`NewChatEntryActions.fileMenu()` |
| 新しいタブ… | メニュー（ファイル）/`Cmd+T` | 下段の「＋」のメニュー（新規チャット・ターミナル・変更・ファイル・ブラウザ・シミュレーター） | プロジェクト未選択で無効 | — | `App/PhloxApp.swift`（`FileCommands`）、`SessionTabsContainer.swift`（`NewTabChooser`） |
| 次/前のセッション | メニュー/`Cmd+Option+↓`・`Cmd+Option+↑` | — | `dashboard==nil`で無効 | — | `App/PhloxApp.swift:552-557` |
| セッションを閉じる | メニュー/`Cmd+W` | — | 選択セッション無しで無効 | — | `App/PhloxApp.swift:559-565`、AppKit横取り`AppDelegate`内`keyDown` monitor（`PhloxApp.swift:278-282`） |
| 会話を書き出す | メニュー/`Cmd+Shift+E` | エクスポート対象セッション名 | 対象なしで無効 | — | `App/PhloxApp.swift:570-577`、`Shared/ChatTranscriptExportAction.swift:44-63` |
| 会話をMarkdownでコピー | メニュー（ショートカット無し） | — | 対象なしで無効 | — | `App/PhloxApp.swift:579-585` |
| 新規作成メニュー項目の削除 | — | — | 標準「新規」を空で置換（実質非表示） | — | `App/PhloxApp.swift:105` |

---

## 15. 通知・Dock・初期化エラー画面

| サーフェス | 内容 | 根拠 file:line |
|---|---|---|
| 通知（システム通知） | バナー/サウンド、APNs/Live Activity | `App/PhloxApp.swift:380-385`、`Packages/AppBootstrap/Sources/APNsNotificationBridge.swift:120-125,495-546` |
| Dockバッジ | 未読完了数バッジ | `App/PhloxApp.swift:223-241,391-395` |
| 初期化エラー画面 | `InitErrorView`。再試行`Cmd+R`（内部UI詳細は再試行ボタン以外は概要確認のみ） | `App/PhloxApp.swift:698-702`付近 |
| macOS通知センター通知（間接） | フックのstop/アイドル検知で`SessionCompletionNotifier`がバナー・サウンド発行。完了時「入力待ち」タイトル、承認待ち時「承認待ち」タイトル。`RemoteSessionNotifier`プロトコル経由でリモート通知へ委譲可能。通知トリガー条件は`SessionNotificationPolicy`（PTY型は単純化、Chat型は`hasActiveTurn`必須で復元リプレイ・interrupt由来のidleは除外） | `SessionFeature/SessionViewModel.swift:730,740`、`SessionFeature/SessionCompletionNotifier.swift:14-65` |
| プッシュ通知の宛先(App ID)未設定警告 | 「送信先（App ID）が未設定のため、ONでも送信されません。」（Localizable line1181）、外部デバイス(iOS等)とのAPNs連携UIの存在を示す | `Packages/AgentDomain/Sources/AgentDomain/DeviceTokenStore.swift`/`DeviceTokenRegistration.swift`（対応関係、推測含む） |
| メニューバーエクストラ / ステータスアイコン | なし（コード上に`MenuBarExtra`/`NSStatusItem`の宣言は見つからない） | 調査範囲＝App/+AppBootstrap+DashboardFeature+SessionFeature+DesignSystem等。4担当いずれの報告にも記載が無いことを事実として記録 |

外部CLI/Control API由来セッションの一覧反映（間接、参考）: ControlServerのspawnリクエストは`ControlActionDashboard`(AppBootstrap)経由で`DashboardViewModel.spawnSession`を呼び、通常のセッション行として同じサイドバーに現れる（`App/ControlActionDashboard+DashboardViewModel.swift:14-52`, `DashboardFeature/Dashboard/SessionOriginPolicy.swift:16-31`）。承認ダイアログの外部応答（間接）: Control API向け`ApprovalDTO`/`ApprovalDecision`はDashboardFeature側の`ControlApproval`型に変換されてUIに描画（`App/ControlActionDashboard+DashboardViewModel.swift:54-69`）。LocalHTTPServerのUI露出は無い（App/Feature層に`import LocalHTTPServer`が存在せず、grepで不在確認済み）。

---

## 16. 横断章 — エージェント種別と能力差

### 16.1 対応エージェント種別（全一覧）

組込3種のみ。カスタム定義（`agents.json`）は 2026-10-12 に廃止した（ADR 0185）。`AgentRef` は `.builtin(AgentKind)` だけ。

| 種別 | displayName | binaryName | symbol | 構造化チャット対応 | 使用量プロバイダ | 根拠 |
|---|---|---|---|---|---|---|
| claudeCode | Claude Code | claude | sparkles | ○ | claudeRateLimits | `AgentKind.swift:4-8`, `AgentDescriptor.swift:169-186` |
| codex | Codex | codex | chevron.left.forwardslash.chevron.right | ○ | codex | `AgentDescriptor.swift:187-203` |
| cursor | Cursor | cursor-agent | cursorarrow.rays | ○ | cursor | `AgentDescriptor.swift:204-223` |

保存済みのカスタムのセッションは、読み込み時に `JSONSessionStore` が個別に捨てる（捨てた件数があれば起動後に 1 回トーストを出す）。

**未確認**: `AgentKind.allCases`の並び順（ハーネス・モデルのメニューの区切り順に使う）は`AgentKind`定義本体に依存し、本調査では確定できない。

### 16.2 起動オプション・権限/承認モードの種別差

| 項目 | Claude Code | Codex | Cursor |
|---|---|---|---|
| bypassArgs（フルアクセス起動） | なし（hookで制御） | `--dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` | `--force --sandbox disabled` |
| restrictedArgs | — | — | `--auto-review --sandbox enabled` |
| hook統合方式 | `.claudeSettings`（`--settings`+`CLAUDE_HOOKS_URL`） | `.codexHooks`（CWD配下`.codex/hooks.json`自動ロード） | `.cursorHooks`（CWD配下`.cursor/hooks.json`自動ロード） |
| statusBootstrap | `.viaHook`（Notification/Stopイベントで状態遷移） | `.idleOnSpawnComplete`（PTY spawn完了で即idle） | `.idleOnSpawnComplete` |
| resume戦略 | `--session-id`付与→`--resume`で再開、初期IDはPhlox UUID | `resume`をprepend、初期IDはhook経由のCodexネイティブID | `--resume`付与、初期IDは`cursorCreateChat` |
| 権限バケット | allow/ask/deny の3種（`ClaudePermissionBucket`） | approvalPolicy/sandboxMode等のキー選択式（3択） | allow/deny の2種（「毎回たずねる」バケットなし。`CursorPermissionBucket`） |

根拠: `AgentDescriptor.swift:169-223`, `AgentLaunchProfile.swift:56-81`, `AgentConfigKit/Claude/ClaudePermissionRules.swift:4-33`, `AgentConfigKit/Codex/CodexGeneralSettings.swift:8-40`, `AgentConfigKit/Cursor/CursorPermissionRules.swift:4-30`。

### 16.3 モデル選択（UIに出るモデル一覧）

| 種別 | 選択肢例 | 既定 | 根拠 |
|---|---|---|---|
| Claude Code | Default / Opus(1M context) / Fable 5.1 / Sonnet 5 / Haiku 5.5 | "default" | `AgentModelCatalog.swift` |
| Codex | gpt-6.1-sol / gpt-6-astra / gpt-6-sol / gpt-6-luna / gpt-5.6-sol / gpt-5.6-terra / gpt-5.6-luna / gpt-5.5 | 先頭(discovery時はCLI順の先頭) | `AgentModelCatalog.swift:38-43,146` |
| Cursor | Auto / Grok系 / Composer 2.5 / Claude各種 / GPT各種 / Gemini各種 / Kimi/GLM 等37種 | "composer-2.5" | `AgentModelCatalog.swift:47-86,145` |

モデル一覧はCLIから動的取得(`refresh()`)し、失敗時は上記ビルトインへフォールバック（`kindsUsingFallback()`でUIに「取得失敗」を示せる）。（`AgentModelCatalog.swift:110-134`）

### 16.4 ユーザーに見える概念（UI部品有無に関わらず）

| 概念 | 内容 | 根拠 |
|---|---|---|
| SessionStatus 7状態 | starting/idle/running/awaitingApproval(prompt付)/awaitingUserQuestion/completed(exitCode)/error(message) | `SessionStatus.swift:3-13` |
| AgentActivityState 6状態 | thinking/searching/running/editing/writing/waiting（ツール名から自動分類） | `AgentActivityState.swift:5-54` |
| ApprovalDecision | accept/decline/acceptForSession/cancel の4択 | `ApprovalDecision.swift:1-6` |
| HookEvent | sessionStart/notification/stop/preToolUse/postToolUse/userPromptSubmit | `HookEvent.swift:3-10` |
| AskUserQuestion | CLIからの質問(header/question/options[](label+description)/multiSelect) | `StructuredChatKit/StructuredChatTypes.swift:74-80` |
| TurnUsage | 1ターンのコスト・トークン内訳(costUSD/inputTokens/outputTokens/cacheRead/cacheCreation/contextUsed/contextWindow) | `StructuredChatTypes.swift:34-60` |
| SessionTitleState | flower(自動生成花名)/derived(内容から自動生成)/manual(手動命名) の3段階 | `SessionTitleState.swift:4-6` |
| ThinkingRecap | reading/running/editing の直近アクション要約("〜を読み込み中"等) | `ThinkingRecap.swift:5-7,67-69` |
| SessionBackend | pty / appServer の2種類（Codexはapp-server JSON-RPC経由、他はPTY） | `SessionBackend.swift:3-6` |
| WorkspaceCollisionPolicy | 同一作業ディレクトリを共有する複数セッションの衝突検知 | `WorkspaceCollisionPolicy.swift:21-90` |
| WorktreeIsolationOutcome | git worktree隔離: disabled/create/reuse/recreate/abort(理由付き) | `WorktreeIsolationPlanner.swift:28-40` |

### 16.5 不整合: 画像添付対応のエージェント種別差（層による記述の相違、未解消）

調査担当間で表現が異なり、同一機能を異なる層（UI添付層/ワイヤ符号化層）から見ている可能性がある。統合時点では解消せず、両論併記する。

- コンポーザのUI添付層: 「Claude/Codexのみ対応、Cursorは不可」（`ComposerAttachments.swift:159-165`）
- ViewModelの分岐まとめ表: 「常時可(Claude Code) / 選択モデル依存(Codex) / 不可(Cursor)」（`ChatSessionViewModel.swift`分岐、担当c）
- ワイヤ符号化層: 「Claudeのみcontent block送信、他はwarning+テキストへdegrade」（`StructuredChatTypes.swift:15-20`）

要確認: UI上の添付可否（コンポーザボタンの有無）と、実際に送信されるデータ形式（content blockかテキストdegradeか）が別レイヤーで判定されており、Codexの「選択モデル依存」が具体的にどのモデルを指すかは3担当の報告からは確定できない。モック作成時はいずれの記述も削らずUI状態の分岐候補として扱うこと。

---

## 17. 横断章 — 状態の描き分け一覧（画面横断）

| 状態 | 視覚表現 | 主に現れる画面 | 根拠 |
|---|---|---|---|
| starting | サイドバーの行の右端に文字（「起動中」）。タブ・グリッドの見出しには状態を出さない（ADR 0184、要件 D19） | サイドバー | `SidebarRows.swift`、`StatusBadge.swift` |
| idle | 何も出さない（2026-10-13 ユーザー指示で経過時間をやめた） | サイドバー | `SidebarRows.swift` |
| running | サイドバーの行の右端に文字（「実行中」）と、題名を流れる明るい帯（動きを減らす設定では静止）。Thinkingインジケータ。グリッドの赤枠3pt(要注意) | サイドバー/グリッド/single | `SidebarRows.swift`, `ThinkingIndicatorCell` |
| awaitingApproval(prompt) | ApprovalBanner表示 | single/グリッド | 4.2節 |
| awaitingUserQuestion | UserQuestionCell表示 | single/グリッド | 4.1節 |
| completed(exitCode) | 要注意(未読完了)ハイライト、通知バナー | サイドバー/Dock/通知 | 3章, 15章 |
| error(message) | ErrorMessageCell、赤系背景 | single/グリッド | 4.1節 |
| ハング(isStalled) | 経過時間+中断ボタン(無応答120秒) | single/グリッド | `ChatHangPolicy.swift:19-35` |
| フォーカス中(グリッド) | 枠線強調(太線＋内側リング) | グリッド | 5章 |
| 要注意(requiresAttention) | 赤枠3pt、行背景`idleHighlight`、プロジェクトアイコン不透明度変化 | サイドバー/グリッド | 3章, `GridTileBorderPolicy.swift:16-27` |
| 空状態(プロジェクト0件) | 「+」ボタンのみ | サイドバー/detail | 3章, 9章 |
| 空状態(プロジェクト選択済・セッション未選択) | 新規チャット画面（`NewChatView`） | detail中央（モード。上段のタブは選ばない） | 9章 |
| 読込中(Agent Console) | ロード中フラグ、CLI無しで`AgentConsoleUnavailableNotice` | Agent Console | 13章 |
| 圧縮中(isCompacting) | シマーテキスト+犬アニメ6ステージ | single/グリッド | 4.1節 |
| ドラッグ中(グリッド) | ハイライト矩形(`fillSelected`)、ライブゴースト分割線 | グリッド | 5章 |

---

## 18. 横断章 — キーボードショートカット全表

### 18.1 アプリメニュー（App層 Commands）

| ショートカット | 機能 | 根拠 file:line |
|---|---|---|
| `Cmd+Shift+,` | エージェント管理を開く | `App/PhloxApp.swift:441-444` |
| `Cmd+Option+T` | ターミナルパネル切替 | `App/PhloxApp.swift:454-458` |
| `Cmd+Option+E` | エディタパネル切替 | `App/PhloxApp.swift:468-472` |
| `Cmd+B` | サイドバー表示/非表示 | `App/PhloxApp.swift:495-499` |
| `Cmd+Option+B` | インスペクター表示/非表示 | `App/PhloxApp.swift:501-505` |
| `Cmd+Control+G` | 表示モード切替 | `App/PhloxApp.swift:507-511` |
| `Cmd+=` | ターミナル文字拡大 | `App/PhloxApp.swift:521-525` |
| `Cmd+-` | ターミナル文字縮小 | `App/PhloxApp.swift:527-531` |
| `Cmd+N` | 新規Claude Codeセッション | `App/PhloxApp.swift:593-597` |
| `Cmd+Shift+N` | 新規Codexセッション | `App/PhloxApp.swift:593-597` |
| `Cmd+Option+N` | 新規Cursorセッション | `App/PhloxApp.swift:593-597` |
| `Cmd+Option+↓` | 次のセッション | `App/PhloxApp.swift:552-554` |
| `Cmd+Option+↑` | 前のセッション | `App/PhloxApp.swift:555-557` |
| `Cmd+W` | セッションを閉じる（AppKitローカルmonitorで横取り） | `App/PhloxApp.swift:559-565,633-638`、AppDelegate（配線は`PhloxApp.swift:278-282`） |
| `Cmd+Shift+E` | 会話を書き出す | `App/PhloxApp.swift:570-577` |
| `Cmd+R` | 初期化エラー画面の再試行 | `App/PhloxApp.swift:698-702` |
| `Cmd+S`（Claudeメモリパネル） | メモリ保存 | `Claude/ClaudeMemoryPane.swift` toolbar |
| `Cmd+S`（Claudeスキルパネル） | スキル保存 | `Claude/ClaudeSkillsPane.swift:80-110` |
| ショートカット無し | アップデート確認、会話をMarkdownでコピー等 | `App/PhloxApp.swift:482-485,579-585` |

### 18.2 コンポーザ/セッション画面内（SessionFeature、App層Commandsとは別配線）

DashboardFeature内には`keyboardShortcut`/`onKeyPress`/`commands(`の定義は無い（grep確認）。以下はSessionFeature（コンポーザ・チャットビュー）に閉じたキー処理。

| キー | 機能 | 状態/文脈 | 根拠 file:line |
|---|---|---|---|
| Enter単独 | 送信 | IME変換中は無効 | `ComposerKeyRouting.swift:76-90` |
| ⌘Enter | 送信 | — | 同上 |
| ⇧Enter | 改行挿入 | — | `ComposerKeyRouting.swift:80-81` |
| ⌘Z / ⌘⇧Z | Undo/Redo | — | `ComposerKeyRouting.swift:52-64` |
| ⌘V | 貼り付け（テキスト/画像分岐） | — | `ComposerKeyRouting.swift:66-74` |
| ↑↓ | サジェスト候補移動 | 候補表示中のみ（入力履歴の矢印キー呼び出しは発見できず、未確認） | `ComposerKeyRouting.swift:35-49` |
| Enter/Tab | サジェスト確定 | 候補表示中 | `ComposerSuggestions.swift:390-407` |
| Esc | サジェスト却下 / ターン中断 / Escワンショット | 候補表示中はサジェスト却下、それ以外は`performChatEscape`（4.5節） | `ComposerKeyRouting.swift`, `ChatEscapeHandling.swift:12-23` |
| Esc（2連打、1.5秒以内） | 会話巻き戻しピッカー表示 | Chat型のみ | `ChatSessionViewModel.swift:989-1011` |
| Cmd+Enter | チームコンポーザ送信 | チームビュー | `TeamComposer.swift:12-116,133-164,298-382` |

**不明点**: 明示的なキーボードショートカットによるペイン切替（Cmd+数字等）は発見できず、存在しないと推測（未確定）。

---

## 19. 横断章 — 設定項目全表（UserDefaults / @AppStorage）

| キー | 型 | 既定値 | 選択肢 | どこで効くか | 根拠 file:line |
|---|---|---|---|---|---|
| `phlox.appLanguage` | String(enum) | `system` | system/ja/en | 表示言語（全ウィンドウ） | `App/LanguageSettings.swift:4-30`、`App/SettingsView.swift:149-158`、適用箇所`App/PhloxApp.swift:44-48,82,125,139` |
| `phlox.newChat.lastHarness` | String | （未設定） | 組込ハーネスの id | 新規チャット画面で最後に送信したハーネス。次回のハーネスの初期値 | `Environment/LastUsedChatSettingsStore.swift` |
| `phlox.projectTabs.v1` | JSON（`ProjectTabsSnapshot`） | （空） | — | プロジェクトごとの下段のタブ（変更・ファイルと選択・分割）。旧 `phlox.sessionTabs.v1` からは初回だけ読み移す | `Tabs/ProjectTabs.swift` |
| ~~`phlox.defaultSessionBackend`~~ | — | — | — | 2026-10-12 に廃止（設定「デフォルトの開き方」も廃止。保存済みの値は読まず、消さずに放置） | — |
| `phlox.notify.banner` | Bool | true | — | 完了バナー通知 | `App/SettingsView.swift:21,174-176` |
| `phlox.notify.sound` | Bool | true | — | 完了サウンド | `App/SettingsView.swift:22,177-179` |
| `phlox.theme` | String | `AppTheme.phlox.id` | `ThemeStore.all` | 配色テーマ | `App/SettingsView.swift:29,208-212` |
| `phlox.appIcon` | String | `AppIconStore.defaultOption.id` | `AppIconStore.all` | Dockアイコン | `App/SettingsView.swift:31,220-227` |
| `phlox.bypass.<agentID>`（例: `phlox.bypass.claudeCode`, `phlox.bypass.codex`） | Bool | true | — | エージェント別パーミッションバイパス | `App/SettingsView.swift:238-246,319-362` |
| `phlox.agora.maxUtterances` | Int | 30 | — | 議論機能の最大発言数 | `App/SettingsView.swift:38-39,265` |
| `phlox.agora.maxAgents` | Int | 5 | — | 議論機能の最大エージェント数 | `App/SettingsView.swift:41-42,266` |
| `phlox.agora.turnTimeoutSeconds` | Int | 180 | — | 議論機能のターンタイムアウト | `App/SettingsView.swift:44-45,267` |
| `phlox.agora.scheduler` | String(enum) | `.freeSpeech` | freeSpeech/roundRobin | 議論スケジューラ方式 | `App/SettingsView.swift:47-48,268-273` |
| `phlox.usage.autoRefresh` | Bool | true | — | 使用量の自動更新 | `App/SettingsView.swift` |
| `phlox.usage.claudeScrape` | Bool | true | — | Claude使用量取得 | `App/SettingsView.swift:25,284-286` |
| `phlox.usage.showUnavailable` | Bool | false | — | 未取得CLIの表示 | `App/SettingsView.swift:26,287-289` |
| `phlox.usage.showInHeader` | Bool | true | — | 画面下部の使用量のバー表示 | `App/SettingsView.swift` |
| `phlox.usage.bottomBarStyle` | String | `bar` | `bar`／`percent` | 下部バーの各枠を横棒か数値で出す | `App/SettingsView.swift` |
| `appUpdater.automaticallyChecksForUpdates`（永続先未確認） | Bool | — | — | 起動時自動アップデート確認 | `App/SettingsView.swift:188-194`（Sparkle内部かUserDefaultsか未確認） |
| `phlox.chat.subAgentPaneFraction`（廃止） | — | — | — | サブエージェント右パネルの幅（パネル廃止に伴い未使用。既存の保存値は無視される） | — |
| ChatFontSettings（チャット本文文字倍率） | Double | 1.0 | 0.8〜2.0, step0.1 | チャット本文フォントサイズ | `Packages/DesignSystem/Sources/DesignSystem/ChatFontSettings.swift:7-33` |
| TerminalFontSettings.step（ターミナル文字サイズ） | — | — | `Cmd+=`/`Cmd+-`で増減 | ターミナルパネル/グリッドpty/single表示のフォントサイズ | `TerminalFontSettings.swift:6`, `App/PhloxApp.swift:522,528` |
| PaneLayoutStore（レイアウトプリセット/分割ツリー永続化） | JSON(Codable, schemaVersion=1) | — | 正規化・検証を必ず経由 | グリッドの分割ツリー状態 | `PaneTree.swift:126-127,324-346` |

Agent Console側（Claude/Codex/Cursor各パネル）はいずれもUserDefaultsではなくファイルベース（`settings.json`、`config.toml`、`cli-config.json`、`mcp.json`、メモリ/スキルファイル）で永続化される（13章参照）。

---

## 20. 横断章 — デザインシステム現況

Packages/DesignSystem/Sources/DesignSystem 配下 全28ファイルを確認。

| 項目 | 内容/UIに出る形 | 根拠 file:line |
|---|---|---|
| AccentSwitchToggleStyle | ピル型トグル(34×20pt)。ON=accent色トラック+白ノブ右、OFF=灰トラック+白ノブ左。spring(0.28,0.72)アニメ | `AccentSwitchToggleStyle.swift:7-38`（使用例: `App/SettingsView.swift:143`） |
| AgentBrandIcon | claudeCode/codex/cursor のブランドロゴ画像（Icons.xcassets、codexはtemplateカラー化）。未対応種別はSF Symbolか頭文字フォールバック | `AgentBrandIcon.swift:19-73` |
| AgentSessionIcon | AgentBrandIconをラップしa11yラベルにステータス文言付加 | `AgentSessionIcon.swift:16-25`（使用例: `DashboardSidebarView.swift:464`） |
| AppIconStore | 選択可能Dockアイコン5種(white/dark-grad/dark/gradient/light) | `AppIconStore.swift:22-48`（使用例: `App/SettingsView.swift:31,220`） |
| AppTheme / ThemeStore | 全10テーマ(phlox既定,tokyoNight,dracula,catppuccinMocha,gruvboxDark,nord,catppuccinLatte,solarizedLight,githubLight,phloxLight)。background/surface/text3段/accent/status6色/agentColors/terminal(bg,fg,ansi16)。WCAG準拠コントラスト自動導出。accentは各テーマの主文字色（白黒。`accentOnFill`=面の上の文字、ADR 0189） | `AppTheme.swift:59-469`（37ファイルから参照） |
| ChatFontSettings | チャット本文文字倍率(0.8〜2.0, step0.1, 既定1.0) | `ChatFontSettings.swift:7-33` |
| Interaction (macOS) | pointingHandCursor等カーソル拡張、hoverableControlSurface、3種HoverableButtonStyle | `Interaction.swift:13-347` |
| ResizeGripView (macOS) | サイドバー幅リサイズの掴みしろ(幅20pt)、hover/drag中accent色3pt発光バー | `ResizeGripView.swift:11-65`（使用例: `DashboardView.swift:330,342`） |
| SettingsGroup | 設定タブ分類(general/appearance/agents/connection/advanced) | `SettingsGroup.swift:9-15`（使用例: `App/SettingsView.swift:81,121`） |
| Shimmer(BandModel/TextView) | イタリック体ラベルへの左→右シマーアニメ("Thinking..."等)、reduceMotion時は静止 | `Shimmer/ShimmerBandModel.swift:6-53`, `ShimmerTextView.swift:21-103` |
| StatusBadge | SessionStatus(starting/idle/running/awaitingApproval/awaitingUserQuestion/completed/error)の日英ラベル・色・SFSymbol・ヘルプ文 | `StatusBadge.swift:6-117` |
| ~~StatusDot (macOS)~~ | 削除済み（2026-10-12 時点で `Packages/DesignSystem/Sources/DesignSystem/` に無い。状態は行の右端の文字で示す） | — |
| StatusLabel | ステータスのテキストラベル(caption, StatusBadge色) | `StatusLabel.swift:4-20` |
| ThemePreviewModel | 設定画面のテーマ見本データ(背景/文字/選択行/入力欄/端末8色) | `ThemePreviewModel.swift:29-53`（使用例: `App/SettingsView.swift:462`） |
| ThinkingOrb(Core/Modes/Profiles/State/View) | 3D点描思考インジケータ。6モード(orbits思考/globe検索/rubik実行/wave待機/ribbon記述/morph編集)、2サイズ(64pt/20pt)、CADisplayLink駆動 | `ThinkingOrbView.swift:15-40`, `ThinkingOrbState.swift:8-17` |
| Tokens (DSSpacing/DSRadius/DSFont/DSLayout/DSIconSize/DSHitTarget/DSShadow/DSColor) | 8ptグリッド余白(xxs2〜xxl32)、角丸(4/8/12)、フォント階層、影(card/cardHover/gridTile)、AppTheme由来の全セマンティックカラー | `Tokens.swift:5-233`（DSColorは97ファイルから参照） |
| TranscriptTypography | トランスクリプト本文の役割14種(body/heading1-6/processSummary/metadata/code等) | `TranscriptTypography.swift:6-156` |
| UIWording | 一般操作文言28キーの日英切替(composerPlaceholder/copyAction/effortLow〜Max等) | `UIWording.swift:2-145` |
| UIWording+Permissions | エージェント別(claude/codex/cursor/custom)権限設定表示文言。claudePermissionMode/codexApprovalPolicy/codexSandboxMode等7分類の日英対応 | `UIWording+Permissions.swift:35-522` |

### 20.1 未使用の予備部品（推測）

以下4部品は現行コードで外部から呼ばれておらず（grep確認）、モック再構築時は「未使用の予備部品」として扱うか要確認（推測）。

| 項目 | 内容 | 根拠 file:line |
|---|---|---|
| AgentKindBadge | エージェント表示名のカプセル表示（色文字+枠線） | `AgentKindBadge.swift:4-28` |
| CapsuleBadge | 色+ドット(6pt)+SFSymbol+文字の汎用カプセル | `CapsuleBadge.swift:4-34` |
| RunningCountBadge | 実行中セッション数バッジ("N running") | `RunningCountBadge.swift:3-46` |
| StatusCapsuleBadge | StatusBadge語彙をCapsuleBadgeで表示 | `StatusCapsuleBadge.swift:5-22` |

### 20.2 ChatRenderKit（チャット描画支援）

| 機能/型 | UIに出る形 | 根拠 file:line |
|---|---|---|
| diff行種別分類(fileHeader/hunk/addition/deletion/context) | 追加=緑系・削除=赤系等の色分けの元データ | `ChatDiffClassifier.swift:3-9` |
| diff行の新旧行番号追跡 | diffビューの行番号ガター | `ChatDiffClassifier.swift:11-43,94-114` |
| diffノイズ行の除外 | fileHeader/"No newline"注記を非表示 | `ChatDiffClassifier.swift:32-34` |
| ファイル変更サマリ | 「編集済み foo.swift」等のヘッダ、+N/-N行数 | `ChatFilePatch.swift:26-48` |
| Swiftコードのシンタックスハイライト(keyword/string/number/comment/plain) | コードブロックの色分けトークン | `ChatCodeTokenizer.swift`・`ChatSyntaxLexer.swift`・`ChatSyntaxRules.swift` |
| シェルコマンドのハイライト(command/subcommand/variable/operator/option/string/comment) | Bashコマンド表示の色分け | `ChatCodeTokenizer.swift`・`ChatSyntaxLexer.swift`・`ChatSyntaxRules.swift` |
| 既知ツール名のラベル導出 | Read/Write/Edit/Glob/Grep/LS/Task/Skill/WebFetch/WebSearch/NotebookEdit/TodoWrite vs Bash | `ChatToolPresentation.swift:4-21` |
| Reasoningテキストの折りたたみ表示判定 | 「思考」セクションの開閉ヘッダ | `ChatToolPresentation.swift:23-33` |
| 複数ツール実行のグループタイトル | 「ツール実行 ×N」または末尾コマンド60字要約 | `ChatToolPresentation.swift:35-49` |

呼び出し元: `SessionFeature/ChatMessageCells+Structured.swift:258-272`, `ChatCodeBlock.swift:74-111`, `ChatRecap.swift:55`。

---

## 21. 横断章 — UI文言カテゴリ（Localizable.xcstrings）

対象: `App/Localizable.xcstrings`（sourceLanguage: "ja"、キー文字列自体が日本語原文）。**重要**: 117キーはカタログ登録分の全件であり、アプリ全体のUI文言の全件ではない。`App/SettingsView.swift`の`Text("ラウンドロビン")`等、xcstringsに未登録の直書き`Text`が別に存在する（grep 0件で確認、推測ではなく確認済み事実）。

| カテゴリ | 件数 | 代表キー(line) | 備考 |
|---|---|---|---|
| A. セッション管理 | 16 | セッションを閉じる(422), 停止(1137), 起動中…(1148), 開始 %@(1236) | 再起動/削除確認ダイアログ含む |
| B. プロジェクト管理 | 13 | プロジェクトを追加(631), フォルダを選択…(532), プロジェクトを変更しますか?(620) | 削除時「フォルダ自体は削除されない」旨の注記あり(1225) |
| C. 権限・承認/実行モード | 4 | %@: フルアクセス（bypass）(48), 権限(1038) | bypass ON時の危険性警告文(1247) |
| D. 使用量ダッシュボード | 19 | Claudeの使用量を取得(81), Cursorをインストールしに行く(125), 未取得(994) | CLIごとに取得方式が異なる旨の説明文あり(92,103) |
| E. 通知 | 6 | %@ が待機中になりました(4), 完了サウンド（Glass）を鳴らす(884) | プッシュ通知宛先(App ID)未設定警告(1181) |
| F. エラーメッセージ | 11 | CLI実行ファイル未検出(26,37,70), spawn深度/総数/レート上限超過(433,686,1060) | hooks設置失敗時の衝突検知(961) |
| G. 外観・表示切替 | 20 | グリッド表示(323), 単体表示とグリッド表示を切り替え(829), テーマ切替説明(499) | 言語選択(English/日本語) |
| H. アップデート | 4 | アップデートを確認…(257), 起動時に自動でアップデートを確認(1159) | |
| I. 設定/アプリ情報/プライバシー | 9 | バージョン(510), 匿名の利用状況を送信(807) | |
| J. ステータス表示 | 3 | 作業完了(708), 入力待ち(752) | |
| K. オンボーディング/空状態 | 8 | プロジェクトがありません(576), 左の「プロジェクトを追加」から…(906) | 初回起動導線 |
| L. マルチエージェント討論 | 1 | 討論(1126) | 6章参照 |
| M. 汎用UI操作 | 10 | キャンセル(312), 削除(796), 表示(1267/"Reveal") | |
| **合計** | **117** | | |

見落とされがちな機能（担当別調査で拾いにくいもの）:

1. **カタログは全UI文言ではない**: `App/SettingsView.swift:270,272,275,277`の「ラウンドロビン」「スケジューラ」「チームビュー討論」等はxcstrings未登録の直書き文字列（grepで確認）。モック作成時、xcstringsだけを文言源にすると漏れる。
2. **プッシュ通知の宛先(App ID)未設定警告とトークン再発行フロー**: 「送信先（App ID）が未設定のため、ONでも送信されません。」(1181)、「トークンの再発行に失敗しました。」(1277)は外部デバイス(iOS等)とのAPNs連携UIの存在を示す。line1257/1267の「隠す」「表示（Reveal）」はトークンの伏せ字表示トグルの可能性が高い（推測、未確認）。
3. **セッションspawnの三段階ガードレール**: 深度上限(433)・総数上限(686)・レート上限(1060)の3種エラー文言から、子セッション再帰spawnに対する3軸の制限がUIに露出していることが分かる。
4. **hooks自動設置の衝突検知**: 「既存のユーザー設定ファイルがあるため hooks を設置できませんでした。」(961)は、Phloxがエージェント設定ファイルへhooksを自動書き込みし、失敗時にサイレントではなくユーザー通知する設計であることを示す。

---

## 22. 不明点・未確認事項（全担当分の総括）

以下は4担当の調査を突き合わせても解消しなかった不明点のみを掲載する（他担当の追補・実読で解消した項目は本節から除外し、該当章に反映済み）。

- **メニューバーエクストラ（`MenuBarExtra`/`NSStatusItem`）**: 2026-09-23 に `Packages/*/Sources` と `App/` 全体を検索し、使用箇所 0 件を確認した。現行アプリにメニューバー常駐機能は無い。
- **`appUpdater.automaticallyChecksForUpdates`の永続化先**（UserDefaultsキーかSparkle内部か）は`SettingsView.swift`単体からは確認できず未確認。
- **`InitErrorView`/`InitLoadingView`/`InitializingView`の内部UI詳細**（再試行ボタン以外）は概要確認のみ。
- **Cursor MCPパネルの有効/無効切替**が`setMCPEnabled`後に`mcpServers`/`settings`を再読込しない非対称挙動は、意図した仕様かバグかコード上からは判別できない。
- **入力履歴の矢印キー(↑↓)呼び出し**は調査対象ファイル内に実装が見当たらない。↑↓はサジェスト候補選択にのみ使用されている。矢印キー履歴機能自体が存在しない可能性、または`ChatSessionViewModel.swift`側の未確認箇所にある可能性がある。
- **通知文言「入力待ち」が完了(`notifyCompleted`)でも使われている点**は実コードのまま記載。意図的仕様かバグかは未確認。
- **`PaneLayoutAction`の実処理側(reducer)の内部ロジック**: `DashboardViewModel`が担うことは特定できたが、1400-1860行付近（waitUntilDone/sendMessage/Agora系詳細ロジック）は未読で見落としの可能性がある（網羅度: 中）。
- **`SubAgentStrip`・`ChatSubAgentModel`の内部実装詳細**、**`ChatRecap.deriveActivityState`本体**、**`TranscriptItemPresentation`の既定展開ロジック本体**は担当ファイル外のため未読了。
- **「隠す／表示（Reveal）」文言(line1257,1267)の具体的な使用箇所**（トークン伏せ字トグルか等）は特定できておらず「推測」に留まる。
- **画像添付対応のエージェント種別差**: UI添付層とワイヤ符号化層の記述が食い違う（16.5節）。層の違いによるものか矛盾かは未解消。
- **`Environment/`配下の設定群**（`CodexUserHooksSettings`, `CursorShellSanitizer`, `LastUsedChatSettingsStore`, `AppSupportMigrator`, `AppEnvironment`）と`Spawn/`配下（hooks/discovery関連）は非UI寄りのバックエンド設定・移行ロジックと判断し詳細読解を省略。
- **`GridSessionSelectionFilter.swift`, `PaneLayoutStore.swift`, `PaneWidthPolicy.swift`, `TrailingTopBarLayout.swift`, `TopBarInsetPolicy.swift`, `AgentStartCardsLayoutPolicy.swift`, `SessionOriginPolicy.swift`, `SessionReachability.swift`, `SessionRestoreCoordinator.swift`, `SessionPersistenceCoordinator.swift`, `MessagingService.swift`, `ControlDashboardSupport.swift`, `GitBranchReader.swift`, `OrphanReaper.swift`, `OrphanedRemoteSessionMigration.swift`, `CursorModelListProvider.swift`, `CodexNativeSessionDiscoveryController.swift`, `SidebarPresentation.swift`, `TeamTimelineModel.swift`, `TeamTimelineStore.swift`, `TeamComposerTarget.swift`, `AgentLaunchPlanner.swift`, `ClaudeSessionHistory.swift`ほかSpawn配下, `ClaudeChatUsageSource.swift`, `ClaudeUsageProvider.swift`, `ClaudeUsageStaleness.swift`, `CodexUsageProvider.swift`, `CursorUsageProvider.swift`, `UsageMonitor.swift`, `UsageProvider.swift`**: ファイル一覧・シグネチャ検索で存在は確認したが、内容の全文読解は行っていない。
- **Localizable.xcstringsのカテゴリ境界**は帰納的判断であり厳密な仕様分類ではない（一部キーは複数カテゴリに跨る）。
- **ControlServer/HookServer/MobileProxy/LocalHTTPServerの型定義本体**（`ControlTypes.swift`, `HookPayload.swift`など）は、担当サブエージェントが参照箇所ベースで報告した内容に依拠しており、直接全文Readしたものではない。
- **`AgoraRolePromptTemplate`・`AgoraUtteranceExtraction`の本文は未読**（Agora 討論の役割プロンプト・発言抽出の詳細）。
- **Agora 討論の設定を変更する UI の所在は未確認**。

---

## 23. 調査範囲と網羅性

母数は `Packages/*/Sources` と `App/` で SwiftUI View/NSViewRepresentable/Commands を含む 97 ファイルであり、2026-09-23 時点で次を機械照合した（手元で実行、テストには未登録）: ①97 ファイルすべてが機能表の行から引用されている（95 ファイルは `ファイル名.swift:行` 形式、`GridSessionPicker.swift`・`UsageTopBarView.swift` の 2 ファイルは行番号なしのファイル名のみ）②本文の `ファイル名.swift:行` 形式の参照 483 件がすべて実在ファイルの行範囲内。照合したのは「引用があるか」「行番号が範囲内か」までで、各行の記述内容の正しさは照合していない。また View を含まない Policy/Store 系ファイル（例: `GridSessionSelectionFilter.swift`）も画面の挙動を決めるが母数の外であり、§22 に列挙したものは未読である。

---

## 付録: 各担当が確認したファイル一覧（View を含まないファイルも含む）

> この一覧は 2026-09 の調査時点のもの。`AgentStartCards.swift`・`UsageTopBarView.swift`・`DashboardTopBarControls.swift`・`StatusDot.swift` など、2026-10-12 までにコードから無くなったファイルを含む（調査の記録として残す）。

担当ごとの調査対象と確認済みファイルを、重複を除去して1つにまとめる。

### 担当a（App/ 全体 + AppBootstrap の UI 影響範囲）

- `App/PhloxApp.swift`
- `App/AppDelegate.swift`
- `App/CompositionRoot.swift`（View本体は含まないが他パッケージのViewへの配線元として確認）
- `App/ControlActionDashboard+DashboardViewModel.swift`（View無し、Control API連携のみ）
- `App/LanguageSettings.swift`
- `App/MobileTokenViewModel.swift`
- `App/PairingQRView.swift`
- `App/SettingsView.swift`
- `App/AgentConsole/AgentConsoleSection.swift`（本体定義は`Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift`）
- `App/AgentConsole/AgentConsoleWindowView.swift`
- `App/AgentConsole/Claude/ClaudeConsoleModel.swift`
- `App/AgentConsole/Claude/ClaudeHooksPane.swift`
- `App/AgentConsole/Claude/ClaudeMemoryPane.swift`
- `App/AgentConsole/Claude/ClaudeOutputStylePane.swift`
- `App/AgentConsole/Claude/ClaudePermissionsPane.swift`
- `App/AgentConsole/Claude/ClaudePluginsPane.swift`
- `App/AgentConsole/Claude/ClaudeSkillsPane.swift`
- `App/AgentConsole/Claude/ClaudeStatusLinePane.swift`
- `App/AgentConsole/Claude/ClaudeStatusPane.swift`
- `App/AgentConsole/Codex/CodexConsoleModel.swift`
- `App/AgentConsole/Codex/CodexMCPPane.swift`
- `App/AgentConsole/Codex/CodexMemoryPane.swift`
- `App/AgentConsole/Codex/CodexPluginsPane.swift`
- `App/AgentConsole/Codex/CodexSettingsPane.swift`
- `App/AgentConsole/Codex/CodexStatusPane.swift`
- `App/AgentConsole/Codex/CodexTrustPane.swift`
- `App/AgentConsole/Cursor/CursorConsoleModel.swift`
- `App/AgentConsole/Cursor/CursorMCPPane.swift`
- `App/AgentConsole/Cursor/CursorModelPane.swift`
- `App/AgentConsole/Cursor/CursorPermissionsPane.swift`
- `App/AgentConsole/Cursor/CursorSettingsPane.swift`
- `App/AgentConsole/Cursor/CursorStatusPane.swift`
- `App/AgentConsole/Shared/AgentConsoleStatusParts.swift`
- `App/AgentConsole/Shared/AgentConsoleStyle.swift`
- `App/AgentConsole/Shared/ChatTranscriptExportAction.swift`
- `Packages/AppBootstrap/Sources/ClaudeSettingsGenerator.swift`（UI影響のみ確認、View無し）
- `Packages/AppBootstrap/Sources/ShellQuoting.swift`（UI影響無し）
- `Packages/AppBootstrap/Sources/SignalSafeBox.swift`（UI影響のみ確認）
- `Packages/AppBootstrap/Sources/CleanupGuard.swift`（UI影響のみ確認）
- `Packages/AppBootstrap/Sources/TerminationSignalHandlers.swift`（UI影響のみ確認）
- `Packages/AppBootstrap/Sources/SavedPorts.swift`（UI影響のみ確認）
- `Packages/AppBootstrap/Sources/BinaryPathResolver.swift`（UI影響のみ確認）
- `Packages/AppBootstrap/Sources/APNsNotificationBridge.swift`（UI影響のみ確認）
- `Packages/AppBootstrap/Sources/ControlActionHandler.swift`（UI影響のみ確認、View無し）

### 担当b（`Packages/DashboardFeature/Sources/DashboardFeature`）

- `Dashboard/DashboardView.swift`
- `Dashboard/DashboardDetailView.swift`
- `Dashboard/DashboardSidebarView.swift`
- `Dashboard/DashboardTopBarControls.swift`（`DashboardLeadingTopBarControls`, `DashboardTrailingTopBarControls`, `ViewModeToggle`, `ModeSegmentButton`）
- `Dashboard/TeamTimelineView.swift`（複数private View含む）
- `Dashboard/TeamComposer.swift`（`TeamComposerTextInput`はNSViewRepresentable）
- `Dashboard/AgoraDiscussionHeaderView.swift`
- `Dashboard/AgentChatRowPolicy.swift`（`AgoraAgentMessageBubble`, `AgoraThinkingIndicatorRow`）
- `Dashboard/AgentStartCards.swift`
- `Dashboard/GridSessionPicker.swift`
- `Dashboard/InspectorView.swift`
- `Dashboard/UsageTopBarView.swift`
- `Dashboard/PaneLayoutPresetMenu.swift`
- `Dashboard/DashboardDetailView.swift`（旧 `StartAreaPolicy`・`SelectProjectPlaceholderView`・`StartOnboardingView` は廃止）
- `Editor/EditorPanelView.swift`
- `Editor/GitCommitPanel.swift`（`ChangeScopeNotice`含む）
- `UserTerminal/TerminalPanelView.swift`

未確認（Viewマーカー無し、と判断したが目視未実施）: `SessionTreeSidebarSection.swift`（データ型のみと推測、簡易確認済み・View無し）。

追補で実読済み: `AgoraDiscussionCoordinator.swift`, `AgoraDiscussionEngine.swift`, `AgoraDiscussionSettings.swift`, `AgoraParticipantNaming.swift`, `AgoraTimelineBuilder.swift`, `AgoraTimelineDisplayPolicy.swift`, `Packages/SessionFeature/Sources/SessionFeature/SessionGridView.swift`, `PaneLayoutView.swift`。

### 担当c（`Packages/SessionFeature/Sources/SessionFeature`）

- `SessionView.swift`
- `PaneLayoutView.swift`
- `PaneDividerHandleView.swift`
- `PaneLayout/PaneDropZone.swift`
- `SessionGridView.swift`
- `GridChatColumn.swift`
- `PaneTileClickSelection.swift`（NSViewRepresentable/監視系）
- `ChatTranscriptView.swift`
- `ChatMessageCells.swift`
- `ChatMessageCells+Basic.swift`
- `ChatMessageCells+CommandGroup.swift`
- `ChatMessageCells+Structured.swift`
- `ChatMessageCells+TaskList.swift`
- `ChatCodeCard.swift`
- `ChatCodeBlock.swift`
- `RichMarkdownView.swift`
- `UserQuestionCell.swift`
- `CompactingIndicatorCell.swift`
- `CompactingDogAnimation.swift`
- `ChatConnectingIndicator.swift`
- `ChatHistoryStartView.swift`
- `ChatHistoryRevertPicker.swift`
- `ChatMessageCopyButton.swift`
- `ChatSessionAccessories.swift`（ApprovalBanner・SubAgentStrip等を含む、承認UI本体）
- `ChatSessionView.swift`
- `ChatComposer.swift`（NSTextView相当の`IMESafeTextView`ラップを含む）
- `ComposerAttachments.swift`
- `ComposerBranchPickerModel.swift`
- `ComposerContextIndicator.swift`
- `ComposerSettingsControls.swift`
- `ComposerSuggestions.swift`
- `ChatInputHistoryScrubber.swift`
- `PaneLayout/PaneLayoutPresets.swift`（プリセットメニューのモデル。実UIはDashboardFeature側）
- 追補（未読6ファイルの実読）: `ChatAutoFollow.swift`, `ChatEscapeHandling.swift`, `ChatMessageCellsCommon.swift`, `ChatMessageRenderCache.swift`, `ChatTextSelectionPolicy.swift`, `ViewportVisibility.swift`

View を持たないが UI 挙動に直結する状態/ポリシー/データ層ファイル（実読済み）: `ChatSessionViewModel.swift`, `SessionViewModel.swift`, `ChatApprovalBroker.swift`, `EscapeRevertPolicy.swift`, `ChatHangPolicy.swift`, `SessionCompletionNotifier.swift`, `SessionNotificationPolicy.swift`, `CodexSessionAdapter.swift`, `CodexSubAgentState.swift`, `PaneTree.swift` 他多数。

### 担当d（DesignSystem / TerminalUI・ChatRenderKit / エージェント種別 / Localizable / ControlServer系）

- `Packages/DesignSystem/Sources/DesignSystem/AccentSwitchToggleStyle.swift`
- `Packages/DesignSystem/Sources/DesignSystem/AgentBrandIcon.swift`
- `Packages/DesignSystem/Sources/DesignSystem/AgentKindBadge.swift`
- `Packages/DesignSystem/Sources/DesignSystem/AgentSessionIcon.swift`
- `Packages/DesignSystem/Sources/DesignSystem/AppIconStore.swift`
- `Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift`
- `Packages/DesignSystem/Sources/DesignSystem/CapsuleBadge.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ChatFontSettings.swift`
- `Packages/DesignSystem/Sources/DesignSystem/Interaction.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ResizeGripView.swift`
- `Packages/DesignSystem/Sources/DesignSystem/RunningCountBadge.swift`
- `Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift`
- `Packages/DesignSystem/Sources/DesignSystem/Shimmer/ShimmerBandModel.swift`
- `Packages/DesignSystem/Sources/DesignSystem/Shimmer/ShimmerTextView.swift`
- `Packages/DesignSystem/Sources/DesignSystem/StatusBadge.swift`
- `Packages/DesignSystem/Sources/DesignSystem/StatusCapsuleBadge.swift`
- `Packages/DesignSystem/Sources/DesignSystem/StatusDot.swift`
- `Packages/DesignSystem/Sources/DesignSystem/StatusLabel.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ThemePreviewModel.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb/ThinkingOrbCore.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb/ThinkingOrbModes.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb/ThinkingOrbProfiles.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb/ThinkingOrbState.swift`
- `Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb/ThinkingOrbView.swift`
- `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift`
- `Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift`
- `Packages/DesignSystem/Sources/DesignSystem/UIWording.swift`
- `Packages/DesignSystem/Sources/DesignSystem/UIWording+Permissions.swift`
- `Packages/TerminalUI/Sources/TerminalUI/AnsiScreenEncoder.swift`
- `Packages/TerminalUI/Sources/TerminalUI/IMETerminalView.swift`
- `Packages/TerminalUI/Sources/TerminalUI/MarkedTextOverlayView.swift`
- `Packages/TerminalUI/Sources/TerminalUI/TerminalCoordinator.swift`
- `Packages/TerminalUI/Sources/TerminalUI/TerminalHostingView.swift`
- `Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift`
- `Packages/TerminalUI/Sources/TerminalUI/Debug/TerminalDump.swift`
- `Packages/AgentDomain/Sources/ChatRenderKit/ChatCodeTokenizer.swift`
- `Packages/AgentDomain/Sources/ChatRenderKit/ChatDiffClassifier.swift`
- `Packages/AgentDomain/Sources/ChatRenderKit/ChatFilePatch.swift`
- `Packages/AgentDomain/Sources/ChatRenderKit/ChatToolPresentation.swift`
- `Packages/SessionFeature/Sources/SessionFeature/SessionView.swift`（呼び出し元・未直接Read、Grepで確認）
- `Packages/DashboardFeature/Sources/DashboardFeature/UserTerminal/TerminalPanelView.swift`（呼び出し元・未直接Read）
- `App/SettingsView.swift`（呼び出し元・未直接Read、Grepで確認）
- `App/MobileTokenViewModel.swift`（呼び出し元・未直接Read）
- `App/CompositionRoot.swift`（呼び出し元・未直接Read）
- `App/ControlActionDashboard+DashboardViewModel.swift`（呼び出し元・未直接Read）
