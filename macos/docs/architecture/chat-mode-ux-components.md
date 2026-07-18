---
status: active
last-verified: 2026-07-17
---

# チャットモード UX コンポーネント構成（chat-ux-batch 後の現行）

> **このファイルの役割**: chat-ux-batch（2026-07-06）で導入・再編されたチャットモード UI/データ層の「今こう動いている」。
> **書かないもの**: なぜこの設計か（→ adr/0038〜0040）、セッションライフサイクル（→ claude-chat-session-lifecycle.md）、リバート/Esc（→ chat-revert-escape-and-interrupt.md）。

## ファイル構成（ChatSessionView の分割後）

`Packages/SessionFeature/Sources/SessionFeature/`（R1 task-27 で DashboardFeature/Session/ から SessionFeature パッケージへ抽出済み）:

| ファイル | 責務 |
|---|---|
| `ChatSessionView.swift` | シングルビュー本体・1行ヘッダー（名前/バッジ/状態のみ） |
| `GridChatColumn.swift` | グリッドタイル（GridComposerBar 含む） |
| `ChatComposer.swift` | 入力欄（IMESafeTextView/SubmitAwareTextView・添付チップ・ペースト横取り・`ChatComposerFooter`） |
| `ComposerLayout.swift` | 幅の純関数群（maxWidth/proposedWidth・footer 3段階選択 `controlsLayout`/`gridControlsLayout`） |
| `ComposerSettingsControls.swift` | 設定コントロール群＋minimal 用 `ComposerSettingsOverflowMenu` |
| `ChatTranscriptView.swift` | トランスクリプト（ThinkingIndicator 配線含む） |
| `ChatSessionAccessories.swift` | ストリップ・承認バナー等 |
| `ChatEscapeHandling.swift` | Esc 状態機械の View 配線 |
| `ComposerKeyRouting.swift` | キールーティング純関数（Return/Esc/Ctrl+Z/サジェスト操作） |
| `ComposerSuggestions.swift` | サジェスト（トリガー検出・コントローラ・供給源＋5秒TTLキャッシュ） |
| `ComposerAttachments.swift` | 添付ストア（4MiB/枚・4枚・合計8MiB）・paste 判定純関数 |
| `ReasoningPreview.swift` / `ChatHangPolicy.swift` | 推論プレビュー・ハング判定の純関数 |

`Dashboard/` 側の新規: `SidebarPresentation.swift`（相対時刻・アイコン規則）・`GridSessionSelectionFilter.swift`・`GridSessionPicker.swift`・`SessionInfoPanel.swift`。`Spawn/ClaudeSessionHistory.swift`（履歴ディスカバリ・転写ローダ）。`GitBranchReader.swift` は 2026-07-10 に SessionFeature へ移設（Dashboard 側は typealias）。

## 状態の正本

- **composer 下書き = `ChatSessionViewModel.draft`**（View ローカル @State 禁止。シングル⇄グリッドは同一 VM 参照を binding するため切替で消えない）。
- 添付 = `ChatSessionViewModel.attachmentStore`。送信は `buildChatInputs(text:)` → `ChatInput.text/.image`。
- 履歴 = off-main ロード → observable キャッシュ（ADR 0040）。
- ターン追跡 = `turnStartedAt`/`lastEventAt`（turnStarted で記録・完了/中断/エラーでクリア）→ `hangAssessment(now:)` は読み取り専用。

## 時刻駆動 UI の規約（ADR 0010 準拠）

経過時間・相対時刻・鮮度注記はすべて **TimelineView の `context.date` を関数引数で流す**。body 評価から ViewModel へ時刻や状態を書き込まない。実行中のみ 1 秒周期（idle では TimelineView ごと階層から外れる）。

## キーイベントの流れ

`SubmitAwareTextView.keyDown` → `ComposerKeyRouting.action(keyCode:modifierFlags:isComposing:suggestionsVisible:)` 純関数 → `.submit/.insertNewline/.escape/.undo/.redo/.moveSuggestion*/.acceptSuggestion/.dismissSuggestions/.passToSystem`。IME 変換中は常に素通し。Cmd+Return=送信・Shift+Return=改行。**Cmd+Z/Ctrl+Z=undo・Cmd+Shift+Z/Ctrl+Shift+Z=redo は `ComposerKeyRouting`（keyCode 6, `ComposerKeyRouting.swift:51-62`）が明示的にルーティングする**（AppKit 既定の undo manager 委譲ではない）。**Cmd+V=paste も keyCode 9 の明示ルーティング**（task-4, 2026-07-10）: SwiftUI hosted NSTextView ではメニュー/responder chain 経由の `paste(_:)` 到達が保証されないため、`keyDown` から `paste(nil)` を明示発火する。画像横取り本体は検査可能な seam `SubmitAwareTextView.handlePaste(from:)`（false なら `super.paste` でテキスト通常ペースト）。IME 変換中・Cmd+Shift/Opt+V は素通し。サジェスト表示中の Esc は dismiss のみで Esc 状態機械へ伝播しない。

## composer の高さ（ADR 0046）

composer 入力欄パネルは既定でコンパクト表示に戻され、**最小高は 36pt**（`ADR 0046` 参照。running インジケータ撤去済み・ADR 0044 と合わせて入力欄パネル全体は約80pxに圧縮）。

## 並行処理の現状（task-12 実測 2026-07-06）

PTY read（actor＋専用キュー）・transcript 保存（actor）・Hook/ControlServer（actor）はメインスレッド外。VT100 パース（TerminalCoordinator.feed）は MainActor だが、実測（実ストリーミングターン中の 10 秒 sample）で Release Phlox は **CPU ≤0.4%・メインスレッドはほぼ run loop 待機**であり、定常負荷のボトルネックは存在しない。過去の CPU 100% 事例は SwiftUI レイアウトループ（ADR 0010/0030 で根治済み）であり、定常パースではない。

補足（2026-07-17）: 上記実測は**単一セッション基準**。複数チャット同時ストリーミングでは delta イベント毎の UI 無効化が積算しカクつきを生んでいたため、チャットモードの delta 適用は `TranscriptStreamCoalescer` による **50ms 窓のバッチ適用**へ変更した（ADR 0093。合成再現で無効化 8,000→8 回）。delta は即時に transcript へ書かれず、非 delta イベント・turn 境界の直前に barrier flush される（イベント観測順序は従来と同一）。

## トランスクリプトの描画（末尾 N 件・ADR 0051）

`ChatTranscriptView` は非 Lazy VStack（ADR 0030）のまま、`TranscriptWindow`（純粋値型・`Session/TranscriptWindow.swift`）で**末尾 N 件のみ描画**する。N は表示文脈（`TranscriptPresentationContext`）で分かれ、**単一表示 = 50 / グリッドタイル = 40**（ADR 0094 で文脈別既定を導入。単一表示は当初 200 だったが初回描画コスト削減のため 50 へ引き下げ＝ADR 0097。グリッドは全タイル常時描画のため小窓）。`reset()` は自文脈の既定値へ戻る。超過時は先頭の「以前のメッセージを表示（残り k 件）」ボタンで 50 件ずつ段階展開し、展開後は押下前の先頭可視メッセージへアンカー保持（イベント駆動 scrollTo・1回のみ）。隠れ域へのジャンプ（バックグラウンドタスクストリップ）は `reveal(index:totalCount:)` がマージン付きで可視化してから scrollTo する。window はスクロール量・可視領域に一切連動しない（拡張契機はユーザー操作のみ）。遅延 scrollTo は世代トークン（jumpGeneration）でセッション切替・後続操作時に無効化。

**復元中の接続表示**（ADR 0098）: セッション復元は空 transcript の VM を先に UI へ載せてから `await vm.restore()` で全件一括反映するため、その間 transcript が空になる。`ChatRestoreState`（`notRestored`/`restoring`/`restored`/`failed`）の `restoring` を `restore()` 入口で設定し、`ChatSessionView` は `restoreState == .restoring` かつ transcript 空の間だけ `ChatConnectingIndicator`（iOS `DSConnectingIndicator` の移植・Canvas + TimelineView レーダー風・`DSColor.chatAccent`・Reduce Motion 静的フォールバック・`accessibilityHidden(true)`）を中央オーバーレイ表示する。完了/失敗で消え、空データ・失敗で永久表示にならない。`SessionRestoreCoordinator` は View が状態を観測するため変更不要。

セル描画の派生値（Markdown 分割・ハイライト・diff 分類）は `ChatMessageRenderCache`（内容キー・非観測 static NSCache・countLimit 512。ADR 0052）でメモ化され、ストリーミング中の再 body 評価で不変セルの再計算が走らない。FileChange は 200 行超で既定折りたたみ・展開時 500 行上限＋「さらに表示」（展開状態は `FileChangeDisplayPolicy.isExpanded(userOverride:lineCount:)` の純導出で、同一 id の diff 置換にも追随）。

## @ サジェストの走査（ADR 0053）

`ComposerSuggestionController` はファイル候補の走査（キャッシュ miss 時の FS 再帰）を**背景 Task** で行い、`update` は即返る（warm キャッシュ hit は同期即応答の fast-path）。走査中は前回候補を保持し、走査は **in-flight 1本＋最新 pending 1枠**に coalescing（running 中の新クエリは走査を起動せず pending 上書きのみ）。結果採用は世代トークン一致時のみで、古いクエリの結果が新しい結果を上書きしない。slash 候補は従来どおり同期。

## トランスクリプト項目の ID 索引

`ChatSessionViewModel.transcriptItemIDs`（Set<String>）は transcript の全変更経路（append/置換/revert 切詰め/restore 再構築）で増分維持され、常に `Set(transcript.map(\.id))` と一致する。BackgroundTaskStrip のジャンプ可否判定はこれを参照する（body 毎の全再構築を廃止）。

## composer とプレースホルダの整列（task-2, 2026-07-10）

`ComposerPlaceholderMetrics` が NSTextView の textInsets（DSSpacing.s）と `.preferredFont(forTextStyle: .body)` を単一の正本として持ち、ChatComposer / GridChatColumn の両 composer がプレースホルダ・実テキストの位置とフォントをここから参照する（キャレット/プレースホルダずれの再発防止。グリッド側の縦余白欠落が旧真因）。

## テーマ追随（task-3, 2026-07-10）

チャット画面の View 群（ChatSessionView/ChatTranscriptView/セル/アクセサリ）は `@AppStorage(ThemeStore.themeKey)` を購読し、設定のカラースキーマ変更へ再起動なしで追随する。コードハイライトのキャッシュ（`ChatMessageRenderCache`）は **`themeID + NUL + code` をキー**にし、テーマ変更後の stale 色ヒットを原理的に排除する（NSCache countLimit=512）。

## ユーザーメッセージの添付バッジ（task-7, 2026-07-10・ADR 0060）

`ChatItem.userMessage` は第4連想値 `attachments: [ChatUserAttachment]`（filename?/mediaType のメタのみ）を持ち、送信時に `sendText` が充填する。描画は `ChatUserMessagePresentation` / `ChatAttachmentBadgePresentation`（検査可能な表示モデル）→ `UserMessageCell` のバッジ（photo アイコン＋表示名＋×N）。空テキスト＋添付ありはバッジのみ（テキスト行・コピー操作なし）。永続対象判定 `shouldStoreInTranscript` は「空本文でも添付ありなら保存」。旧「（画像 N 枚）」プレースホルダは廃止。

## composer フッターのコンテキストドーナツとブランチ表示（chat-ui-context-fixes, 2026-07-10・ADR 0062/0066）

フッター HStack はモード選択（leading コントロール）の右・Spacer の前に `ComposerContextIndicator`（`SessionFeature/ComposerContextIndicator.swift`）を置く。両コントロールは model 名メニューと同じ `HoverableComposerControl`（NSTrackingArea ホバーハイライト・ComposerSettingsControls.swift。ADR 0029 の .onHover 不発対策）に乗る。

- **①コンテキスト使用率のドーナツ**（14×14・線幅2。`ComposerContextGauge.fraction` が `TurnUsage.contextUsedTokens ?? (input+cacheRead+cacheCreation)` / `contextWindowTokens` を 0...1 にクランプ。80% 以上で `statusAwaitingApproval` 色。データ欠落時は非表示）。**ホバーで即時ポップアップ**（`.help` の OS 遅延に依存しない）: `ComposerContextPopoverText.lines` が「Context window: / n% used (m% left) / 27k / 353k tokens used」の3行を生成（k 丸めは `tokenText`）。
- **②チェックアウト中ブランチ**（`GitBranchReader.currentBranch`＝`.git/HEAD` 直読み・`TimelineView(.periodic(by: 30))` の date 駆動・非 git は非表示）。**クリックでローカルブランチ一覧**（`GitBranchSwitcher.localBranches`＝`git for-each-ref --sort=-committerdate`・現在ブランチにチェック）を開き、選択で `GitBranchSwitcher.checkout`（force/stash なし・失敗は alert で露出）。git 実行は `Task.detached`（メインスレッド外）、切替成功後はラベル即時更新。
- データ供給は `.turnUsage` → `ChatSessionViewModel.lastTurnUsage`（Claude=result/modelUsage、Codex=tokenUsageUpdated 再利用。ADR 0062）。**セッション単位のサイドカー snapshot（`<uuid>.usage.json`・ADR 0066）で永続化**され、`restore` 直後から表示される。`GitBranchReader` は DashboardFeature から **SessionFeature へ移設**（public 化。DashboardFeature 側は `typealias` で互換維持）。

### グリッドビューへの展開（composer-agent-ux, 2026-07-10）

`ComposerContextIndicator` は `layout: ComposerIndicatorLayout`（`.regular`＝シングル既定 / `.compact`＝グリッド）を持ち、`GridComposerBar` のフッター（leading コントロールの右・Spacer の前、`accessibilityIdentifier("GridComposer.contextIndicator")`）に `.compact` で入る。usage / workspacePath のソースはシングル（`ChatComposer`）と同一（`lastTurnUsage` / `workspacePath`）。`.compact` はドーナツ 12×12。**ブランチ名の固定幅クランプは撤廃**（2026-07-17。`ComposerIndicatorMetrics.branchNameMaxWidth` は両 layout で `nil`）: 領域があれば全文表示し、省略（`.middle`）は親 HStack の実領域不足時のみ発生する。中間幅で Spacer と 50/50 分割されて不要に省略されないよう、インジケータ root に `.layoutPriority(1)`・内側の `branchLabel` に `.layoutPriority(-1)` を置き、幅不足時はラベルが先に圧縮されて送信・停止ボタン（剛性幅）を押し出さない。**列幅が極端に狭いときはブランチ名が絞り出されてアイコンのみになる**（picker 操作は可能な graceful degradation）。メトリクスは `ComposerIndicatorMetrics`（純関数）で、`GridComposerParityTests`・凍結 `AcceptanceBranchNameFullWidthTests`・白箱 `ComposerBranchLabelWhiteboxTests`（footer 実配線ハーネス）が検証する。

## composer はフローティング配置（chat-ui-context-fixes, 2026-07-10・ADR 0065）

`ChatSessionView.mainColumn` / `GridChatColumn` の composer は `ChatTranscriptView` への `.overlay(alignment: .bottom)` で浮かせ、ScrollView はカラム全高（画面下端）を占める。スクロールバーのトラック・つまみは画面右下端まで届く。最下部の逃し余白は**スクロールコンテンツ末尾のスペーサー**（`chat-bottom` アンカー兼用・高さ= `onGeometryChange` による composer 実測高の一方向反映）で確保する。`safeAreaInset(bottom)` と `contentMargins(for: .scrollContent)` は macOS ではスクローラごとインセットされるため使わない（ADR 0065）。composer の全幅不透明背景は撤去済みで、スクロール途中はコンテンツがパネル周囲余白の背後を通過して見える（承認済みの見た目）。幅制約（`ComposerLayout.maxWidth`）は従来どおり。

## composer footer の幅適応3段階レイアウト（composer-overflow, 2026-07-11・ADR 0078）

footer は `ComposerFooterLayout`（standard / compact / minimal）を幅から純関数で選ぶ。単一表示は `ComposerLayout.controlsLayout(proposedWidth:)`（600pt 未満→compact・490pt 未満→minimal）、グリッドは `gridControlsLayout(proposedWidth:)`（**standard を返さない**: 490pt 以上→compact・未満→minimal）。minimal は設定（model/effort/permission/mode/branch）を `ComposerSettingsOverflowMenu`（ellipsis.circle）へ集約する。幅は親（ChatSessionView / GridChatColumn）の GeometryReader から `proposedWidth(mainColumnWidth:)` を通して一方向に注入され、body 中の state 書き戻しはない（ADR 0010 準拠）。footer 部品（`ChatComposerFooter`・`ComposerSendButton`）は単一表示とグリッドで共有。回帰は `ComposerOverflowLayoutTests` / `AcceptanceGridComposerOverflowTests`（ImageRenderer で footer/bar 本体を直接描画し実幅≤提案幅を検証）が固定する。ヘッダーは1行のみ（設定ボタン右のセッション名と重複していたヘッダー下のセッション名行は 2026-07-11 に削除）。

## 処理中インジケータの表示条件（chat-ui-context-fixes, 2026-07-10・ADR 0064）

ThinkingIndicatorCell の表示条件は `status == .running` ではなく **`ChatSessionViewModel.showsProcessingIndicator`**（running またはバックグラウンドタスク/実行中サブエージェントが残存）。ターン進行中の Codex `threadStatusChanged(idle)` は無視され、interrupt/error 時は実行中サブエージェントが `.failed` へ終端される（`ChatSubAgentModel.failRunningSubAgents()`）。Codex app-server の `willRetry: true` エラー通知は非終端 `.warning` に正規化され（ターン継続＝停止ボタン維持）、プロセス EOF 時は Kit が終端 error を合成して running 固着を防ぐ（ADR 0095。凍結 `AcceptanceStopButtonPersistenceTests`）。

## Thinking ドットの波アニメーション（composer-agent-ux, 2026-07-10・ADR 0067）

`StaticThinkingDots` は3点の二値点滅から**サイン波の波打つドット**（順に浮き上がり・呼吸・滑らかな透過変調）へ変更。状態は純関数 `ThinkingAnimationModel.dotState(index:dotCount:date:)`（`ThinkingAnimation.swift`）が date のみから導出し、駆動は `TimelineView(ThinkingAnimationModel.timelineSchedule(isVisible:))`（30fps 上限）。**非表示中（セル非存在・transcript 最下部が viewport 外・シーン非アクティブ）はエントリを発行しない**（viewport シグナルは `ChatAutoFollow` の isAtBottom を `ChatTranscriptView` → `ThinkingIndicatorCell(isInTranscriptViewport:)` へ配線）。`accessibilityReduceMotion` 時は静的表示。設計判断と残余（hangAssessment 用 1Hz クロックは対象外）は ADR 0067。

## ツールコールのグループ集約表示（desktop-ui-polish, 2026-07-17・ADR 0096）

連続するコマンド実行 item は1セルに集約して描画する。描画直前に純関数 `ChatTranscriptGrouping.blocks(from:)`（`ChatTranscriptGrouping.swift`）が item 列を `ChatTranscriptBlock`（`.single` / `.commandGroup(id:items:)`）へ畳み、`ChatTranscriptView` はブロック単位で ForEach する。グループ id は**先頭 item の id**（append で id 不変＝セル再利用）、末尾ウィンドウ境界での部分ブロックも外側 id を保つ。ジャンプは `scrollTargetID(containing:in:)` が item→ブロック id を解決。セルは `CommandGroupCell`（`ChatMessageCells+CommandGroup.swift`・`CommandGroupPresentation.shouldRender = isRunning || !rows.isEmpty`）。identity 設計の理由は ADR 0096、凍結 `AcceptanceToolCallGroupingTests`。
