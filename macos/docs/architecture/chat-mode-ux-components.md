---
status: active
last-verified: 2026-07-29
---

# チャットモード UX コンポーネント構成（chat-ux-batch 後の現行）

> **このファイルの役割**: chat-ux-batch（2026-07-06）で導入・再編されたチャットモード UI/データ層の「今こう動いている」。
> **書かないもの**: なぜこの設計か（→ adr/0038〜0040・0120・0138）、セッションライフサイクル（→ claude-chat-session-lifecycle.md）、リバート/Esc（→ chat-revert-escape-and-interrupt.md）。

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
| `ChatInputHistoryScrubber.swift` | 左中央の入力履歴スクラバー（積み重ねた横線。囲い無し）。ホバーで履歴パネル（Liquid Glass 面。macOS 26+ は `.glassEffect`、下位は `.ultraThinMaterial`）を開く。スクラバーの線とパネル行は共有の選択位置で連動し、選択中を白く長く強調。線・行のいずれをクリックしても該当入力へジャンプ。選択位置はスクロール位置にも追従。単一チャット表示（`ChatSessionView`）のみ |
| `InputHistoryPolicy.swift` | 入力履歴の純関数群（`entries(from:)`＝transcript 順に `.userMessage` 抽出、`scrubberTicks(from:cap:)`＝スクラバー表示用に最新側を上限件数で返す）。型 `InputHistoryEntry(id,text)` |

`Dashboard/` 側の新規: `SidebarPresentation.swift`（相対時刻・アイコン規則）・`GridSessionSelectionFilter.swift`・`GridSessionPicker.swift`・`SessionInfoPanel.swift`。`Spawn/ClaudeSessionHistory.swift`（履歴ディスカバリ・転写ローダ）。`GitBranchReader.swift` は 2026-07-10 に SessionFeature へ移設（Dashboard 側は typealias）。

## 状態の正本

- **composer 下書き = `ChatSessionViewModel.draft`**（View ローカル @State 禁止。シングル⇄グリッドは同一 VM 参照を binding するため切替で消えない）。
- 添付 = `ChatSessionViewModel.attachmentStore`。送信は `buildChatInputs(text:)` → `ChatInput.text/.image`。
- 履歴 = off-main ロード → observable キャッシュ（ADR 0040）。
- ターン追跡 = `turnStartedAt`/`lastEventAt`（turnStarted で記録・完了/中断/エラーでクリア）→ `hangAssessment(now:)` は読み取り専用。
- 入力履歴 = `ChatSessionViewModel.inputHistoryEntries`（= `InputHistoryPolicy.entries(from: transcript)`、transcript 順・古い→新しい）。revert 用 `revertCandidates`（新しい順・→ chat-revert-escape-and-interrupt.md）とは別プロパティで意味論を分離。スクラバーのジャンプは新機構を作らず、既存の `requestedTranscriptTarget` → `ChatTranscriptView.jumpToTarget`（windowing の reveal-on-jump 込み）に相乗りする。スクラバーのハイライトはトランスクリプトのスクロール位置に連動する（`ChatSessionView.currentInputPositionID` ← `ChatTranscriptView` が NSScrollView のビューポート中央にあるユーザー入力を算出）。位置測定はスクロール不変な content 座標系（preference）で行い、@Binding 更新は値変化時のみ＝既存の `isThinkingIndicatorInViewport` と同じ経路で ADR 0030 の再入（スクロール連動レイアウトループ）を避ける。

## 時刻駆動 UI の規約（ADR 0010 準拠）

経過時間・相対時刻・鮮度注記はすべて **TimelineView の `context.date` を関数引数で流す**。body 評価から ViewModel へ時刻や状態を書き込まない。実行中のみ 1 秒周期（idle では TimelineView ごと階層から外れる）。

## キーイベントの流れ

`SubmitAwareTextView.keyDown` → `ComposerKeyRouting.action(keyCode:modifierFlags:isComposing:suggestionsVisible:)` 純関数 → `.submit/.insertNewline/.escape/.undo/.redo/.moveSuggestion*/.acceptSuggestion/.dismissSuggestions/.passToSystem`。IME 変換中は常に素通し。Cmd+Return=送信・Shift+Return=改行。**Cmd+Z/Ctrl+Z=undo・Cmd+Shift+Z/Ctrl+Shift+Z=redo は `ComposerKeyRouting`（keyCode 6, `ComposerKeyRouting.swift:51-62`）が明示的にルーティングする**（AppKit 既定の undo manager 委譲ではない）。**Cmd+V=paste も keyCode 9 の明示ルーティング**（task-4, 2026-07-10）: SwiftUI hosted NSTextView ではメニュー/responder chain 経由の `paste(_:)` 到達が保証されないため、`keyDown` から `paste(nil)` を明示発火する。画像横取り本体は検査可能な seam `SubmitAwareTextView.handlePaste(from:)`（false なら `super.paste` でテキスト通常ペースト）。IME 変換中・Cmd+Shift/Opt+V は素通し。サジェスト表示中の Esc は dismiss のみで Esc 状態機械へ伝播しない。

## composer の高さ（ADR 0046）

composer 入力欄パネルは既定でコンパクト表示に戻され、**最小高は 36pt**（`ADR 0046` 参照。running インジケータ撤去済み・ADR 0044 と合わせて入力欄パネル全体は約80pxに圧縮）。

## 並行処理の現状（task-12 実測 2026-07-06）

PTY read（actor＋専用キュー）・transcript 保存（actor）・Hook/ControlServer（actor）はメインスレッド外。VT100 パース（TerminalCoordinator.feed）は MainActor だが、実測（実ストリーミングターン中の 10 秒 sample）で Release Phlox は **CPU ≤0.4%・メインスレッドはほぼ run loop 待機**であり、定常負荷のボトルネックは存在しない。過去の CPU 100% 事例は SwiftUI レイアウトループ（ADR 0010/0030 で根治済み）であり、定常パースではない。

補足（2026-07-17）: 上記実測は**単一セッション基準**。複数チャット同時ストリーミングでは delta イベント毎の UI 無効化が積算しカクつきを生んでいたため、チャットモードの delta 適用は `TranscriptStreamCoalescer` による **50ms 窓のバッチ適用**へ変更した（ADR 0093。合成再現で無効化 8,000→8 回）。delta は即時に transcript へ書かれず、非 delta イベント・turn 境界の直前に barrier flush される（イベント観測順序は従来と同一）。

## トランスクリプトの描画（末尾 N ブロック・ADR 0051 / 0127）

`ChatTranscriptView` は非 Lazy VStack（ADR 0030）のまま、`TranscriptWindow`（純粋値型・`Session/TranscriptWindow.swift`）で**末尾 N ブロックのみ描画**する。**N が数えるのはトップレベルに描画されるブロック数**であって item 数ではない（ADR 0127）——連続するツール実行のまとまりは中に何件入っていても1枠。`ChatTranscriptGrouping.visibleSlice(from:blockLimit:)` が全 item をブロックへ畳んで末尾 `blockLimit` ブロックを返し、隠れ件数は `hiddenBlockCount`（ブロック単位）で返る。N は表示文脈（`TranscriptPresentationContext`）で分かれ、**単一表示 = 50 / グリッドタイル = 16**（ADR 0094 で文脈別既定を導入。単一表示は当初 200 だったが初回描画コスト削減のため 50 へ引き下げ＝ADR 0097。グリッドは全タイル常時描画のため小窓で、40 → 16 は ADR 0116）。`reset()` は自文脈の既定値へ戻る。超過時は先頭の「以前のメッセージを表示（残り k 件）」ボタンで 50 ブロックずつ段階展開し、展開後は押下前の先頭可視メッセージへアンカー保持（イベント駆動 scrollTo・1回のみ）。隠れ域へのジャンプ（バックグラウンドタスクストリップ）は `ChatTranscriptGrouping.blockIndex(ofItemWithID:in:)` で item→ブロック index へ翻訳してから `reveal(index:totalCount:)` がマージン付きで可視化し、scrollTo する。window はスクロール量・可視領域に一切連動しない（拡張契機はユーザー操作のみ）。遅延 scrollTo は世代トークン（jumpGeneration）でセッション切替・後続操作時に無効化。

**復元中の接続表示**（ADR 0098）: セッション復元は空 transcript の VM を先に UI へ載せてから `await vm.restore()` で全件一括反映するため、その間 transcript が空になる。`ChatRestoreState`（`notRestored`/`restoring`/`restored`/`failed`）の `restoring` を `restore()` 入口で設定し、`ChatSessionView` は `restoreState == .restoring` かつ transcript 空の間だけ `ChatConnectingIndicator`（iOS `DSConnectingIndicator` の移植・Canvas + TimelineView レーダー風・`DSColor.chatAccent`・Reduce Motion 静的フォールバック・`accessibilityHidden(true)`）を中央オーバーレイ表示する。完了/失敗で消え、空データ・失敗で永久表示にならない。`SessionRestoreCoordinator` は View が状態を観測するため変更不要。

セル描画の派生値（Markdown 分割・ハイライト・diff 分類）は `ChatMessageRenderCache`（内容キー・非観測 static NSCache・countLimit 512。ADR 0052）でメモ化され、ストリーミング中の再 body 評価で不変セルの再計算が走らない。FileChange は 200 行超で既定折りたたみ・展開時 500 行上限＋「さらに表示」（展開状態は `FileChangeDisplayPolicy.isExpanded(userOverride:lineCount:)` の純導出で、同一 id の diff 置換にも追随）。

## @ サジェストの走査（ADR 0053）

`ComposerSuggestionController` はファイル候補の走査（キャッシュ miss 時の FS 再帰）を**背景 Task** で行い、`update` は即返る（warm キャッシュ hit は同期即応答の fast-path）。走査中は前回候補を保持し、走査は **in-flight 1本＋最新 pending 1枠**に coalescing（running 中の新クエリは走査を起動せず pending 上書きのみ）。結果採用は世代トークン一致時のみで、古いクエリの結果が新しい結果を上書きしない。slash 候補は従来どおり同期。

**発火位置（ADR 0104）**: `/`（slash）も `@`（file）も**カーソル直前の空白区切りトークンの先頭**で発火する（位置不問・両者対称）。トークン途中の `/`・`@`（`src/main`・`a@b.com` 等）は発火しない。ハイライト（`ComposerHighlight.spans`）も同じトークン先頭規則で、`applyComposerHighlights` が全 span を着色する（色の割り当ては `ComposerHighlightKind` の**網羅 switch**。ケース追加はコンパイルエラーになる）。

## 入力欄の ultra 系キーワード強調（composer-ultra-keywords, 2026-07-29・ADR 0138）

`ComposerHighlight.spans(in:includingKeywords:)` が、claude CLI がキーワード型機能として検出する4語（`ultrathink` / `ultraplan` / `ultrareview` / `ultracode`）の範囲を `.keyword` span として返す。既存の `spans(in:)` は不変で、キーワードを返さない。

検出規則は CLI v2.1.220 の実装を写した2系統（正本は ADR 0138）:

- **規則X（`ultrathink`）**: ASCII 語境界（`[A-Za-z0-9_]` で判定・JS の `\b` 相当）＋大小無視のみ。除外なし。
- **規則Y（他3語）**: 規則X に加え、①入力が `/` 始まりなら検出しない ②`` ` " < { [ ( ' `` の保護区間内は除外（`'` は直前が語構成文字なら開始せず・閉じの直後が語構成文字なら閉じない、`<` は次が `[a-zA-Z/]` のときだけ開始、`[[` は開始位置を更新）③直前が `/ \ -`・直後が `/ \ - ?`・直後が `.` ＋語構成文字は除外。

オフセットは UTF16 単位。`.slashCommand` / `.fileReference` span と重なる `.keyword` は落とす（1文字1色のため）。

描画は `IMESafeTextView.SubmitAwareTextView.highlightsKeywords`（既定 `false`）が ON/OFF を持ち、`ChatComposer` / `GridChatColumn` が `agentRef == .builtin(.claudeCode)` を渡す（`SubAgentDrawerView` は既定のまま）。色は `DSColor.composerKeyword`（light `#B45309` / dark `#FCD34D`）。

## init 到着前のスラッシュ補完（composer-ultra-keywords, 2026-07-29・ADR 0138）

`system/init` の一覧は最初の送信後にしか届かないため、それまでの候補を2つの供給源で埋める。

- **静的フォールバック 22 件**（`ComposerSuggestionSources.builtinSlashCommands`）。ADR 0120 の 10 件に、2026-07-28 実測で存在を確認した 12 件（`/agents` `/code-review` `/deep-research` `/effort` `/fast` `/loop` `/recap` `/run` `/schedule` `/security-review` `/simplify` `/ultrareview`）を追加。
- **`AvailableCommandsStore`**（`SessionFeature`）が、init で受領した一覧を `phlox.availableCommands.<AgentRef.id>.<正規化済み作業ディレクトリ>` キーで `UserDefaults` に保存する。正規化は nil/空 → `""`、チルダ展開、`standardizedFileURL`、末尾スラッシュ除去の順。空配列と 301 件以上は保存せず既存値も消さない。再記録は全量置換（後勝ち）。

`ChatSessionViewModel` は生成時に1回だけストアを読み `seedSlashCommands` に保持し、`.availableCommandsUpdated` 受信時に `availableSlashCommands` の更新とストアへの `record` を行う。`ComposerSuggestionController` 経由で `ComposerSuggestionSources.slashCandidates(availableCommands:seedCommands:...)` へ渡る。

候補の決まり方: `availableCommands` が非 nil なら seed を無視して従来どおり。nil かつ seed が非空なら **静的リスト → seed → `.claude/commands` → `.claude/skills`** の順に積んで重複除去（seed 由来の subtitle が先勝ちで負けないための順序）。seed が nil / 空配列なら従来の静的フォールバック経路。5秒TTLキャッシュのキーにも seed を含める。

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

ThinkingIndicatorCell の表示条件は `status == .running` ではなく **`ChatSessionViewModel.showsProcessingIndicator`**（running またはバックグラウンドタスク/実行中サブエージェントが残存）。ターン進行中の Codex `threadStatusChanged(idle)` は無視され（復元時に thread status から推定した running ターンのみ例外的に idle で終端＋完了通知。ADR 0119）、interrupt/error 時は実行中サブエージェントが `.failed` へ終端される（`ChatSubAgentModel.failRunningSubAgents()`）。Codex app-server の `willRetry: true` エラー通知は非終端 `.warning` に正規化され（ターン継続＝停止ボタン維持）、プロセス EOF 時は Kit が終端 error を合成して running 固着を防ぐ（ADR 0095。凍結 `AcceptanceStopButtonPersistenceTests`）。

## Thinking インジケータのシマーアニメーション（thinking-remove-ellipsis, 2026-07-20・ADR 0067 / CA 駆動化 2026-07-24・ADR 0117）

`ThinkingIndicatorCell` は**点描の orb ＋ シマーする状態語**で実行中を表す（**跳ねドットは廃止**）。orb は thinking-orbs（MIT）を Swift/CoreGraphics へ移植した共有実装 `ThinkingOrbView`（DesignSystem・macOS/iOS 共用）で、`AgentActivityState` の 6 状態（thinking / searching / running / editing / writing / waiting）ごとに別モード（orbits / globe / rubik / morph / ribbon / wave）を描く。状態は `ChatSessionViewModel.activityState`＝`ChatRecap.deriveActivityState(transcript:status:)`（純関数。最後のユーザー入力以降で最後に現れた項目種別が勝つ。読み取り系ツール名の集合と待機判定は `AgentDomain.AgentActivityClassifier`）から導出し、右に `state.orbLabel`（"Searching..." 等）を `ShimmerTextView`（DesignSystem・macOS は Core Animation 駆動、帯の形状は `ShimmerBandModel`）で並べる（周期 2.0s・下限明度 0.55・基準色は本文色。ADR 0143）。**描画は display link 駆動の下層ビュー内で完結し、SwiftUI の表示木を毎フレーム再評価しない**（ADR 0117 の方針を継承。旧 `TimelineView` 30fps 駆動が複数セッション・グリッドで AttributeGraph／アクセシビリティ木を毎フレーム再構築させメインスレッドを占有していた経緯も同 ADR）。**非表示中（セル非存在・transcript 最下部が viewport 外・シーン非アクティブ）は display link を止める**（viewport シグナルは `ChatAutoFollow` の isAtBottom を `ChatTranscriptView` → `ThinkingIndicatorCell(isInTranscriptViewport:)` へ配線）。`accessibilityReduceMotion` 時は代表フレーム 1 枚を静止表示。iOS も同じ orb（`DSThinkingIndicator`）を使う。承認・回答待ち（`waiting`）は処理中でなくても出すため、表示ゲートは `CompactingIndicatorPresentation.shouldShowThinkingIndicator(..., isAwaitingUser:)` で分岐する。置き換えの決定理由は ADR 0142、跳ねドット廃止の経緯は ADR 0067。

## ツールコールのグループ集約表示（ADR 0096 → 0127 / 0128）

連続するコマンド実行 item は**1件でも**1セルに集約して描画する（ADR 0127。当初は2件以上だった＝ADR 0096）。描画直前に純関数 `ChatTranscriptGrouping.blocks(from:)`（`ChatTranscriptGrouping.swift`）が item 列を `ChatTranscriptBlock`（`.single` / `.commandGroup(id:items:)`）へ畳み、`ChatTranscriptView` はブロック単位で ForEach する。グループ id は**先頭 item の id**（append で id 不変＝セル再利用）。**窓境界は必ずブロック境界に来るため部分ブロックは生じない**（ADR 0127 で旧・境界分割処理は削除）。ジャンプは `scrollTargetID(containing:in:)` が item→ブロック id を解決。

セルは `CommandGroupCell`（`ChatMessageCells+CommandGroup.swift`）。窓がブロック単位になり1グループが数千件を抱えうるため、**ヘッダと行データを型で分けてある**（ADR 0128）:

- `CommandGroupHeader`（`title` / `timestamp` / `isRunning` / `shouldRender`）— 行データを保持しない。**閉状態はこれだけを使う**。
- `CommandGroupRowWindow.slice(items:lastTranscriptID:isTurnRunning:limit:) -> CommandGroupRowsSlice` — `if isExpanded` の内側でだけ呼ぶ。展開時の行は末尾 `defaultLimit = 50` 件で、残りは `hiddenRowCount` として「残り N 件を表示」（`expandStep = 50`）で段階展開する。
- `shouldRender = isRunning || items.count == 1 || 出力が空でない item が1件以上ある`。**唯一の行には空出力フィルタを適用しない**（単独・空出力のツール実行がカードごと消えるのを防ぐ）。

凍結テスト: `AcceptanceToolCallGroupingTests` / `AcceptanceBlockWindowTests` / `AcceptanceCommandGroupRowWindowTests`。

## transcript の切り詰め廃止（agent-grid-jank run, 2026-07-24・ADR 0118）

`DisclosureCard` のタイトルは `lineLimit(1)`/`truncationMode(.middle)` を廃止し全文を折り返す。MarkdownUI の paragraph/heading1〜6 には `.fixedSize(horizontal: false, vertical: true)` を付与し、折り返し行の縦高さを確保する（`.table` ブロックより前に限定＝ADR 0045 のレイアウト非収束を回避）。「…」クリック展開時に後続要素へ文字が重なる病理の根治。凍結 `AcceptanceMarkdownNoTruncationTests`（NSHostingView fittingSize による高さ計測＋lineLimit/truncationMode のソーススキャン禁止）。

## タスクリストカード（agent-grid-jank run, 2026-07-24）

Claude Code の Tasks 機能（TodoWrite/TaskCreate/TaskUpdate）を transcript 内の1枚カードで表示する。正規化は `NormalizedChatEvent.taskListUpdated(tasks: [AgentTaskItem])`（TodoWrite=全量スナップショット、TaskCreate/TaskUpdate=`toolUseResult.task.id` による差分。`ClaudeChatClient+TaskList.swift`）。transcript 側は `ChatItem.taskList`（同一カードの置換更新）を `TaskListCell`（`ChatMessageCells+TaskList.swift`・DisclosureCard ベース・accessibilityIdentifier `ChatMessage.taskList`）で描画。型は `StructuredChatKit/AgentTaskList.swift`（`AgentTaskItem`/`AgentTaskStatus`）。凍結 `AcceptanceClaudeTaskListEventTests`・`AcceptanceTaskListCardTests`。

## スラッシュコマンドのサジェスト＝セッションの提供一覧が正本（ADR 0120, 2026-07-26）

候補の正本は **Claude Code が `system`/`init` で申告する `slash_commands`**。`ClaudeChatClient+EventParsing.swift` が `NormalizedChatEvent.availableCommandsUpdated(commands:)`（先頭 `/` 無し・受信順・全量スナップショット）へ正規化し、`ChatSessionViewModel.availableSlashCommands: [String]?` が**置換**保持する（他イベントでクリアしない）。View 側は `ChatComposer` / `GridChatColumn` の双方が `ComposerSuggestionController.availableSlashCommands` へ生成時＋値変化時に反映する。

`ComposerSuggestionSources.slashCandidates(availableCommands:homeDirectory:workingDirectory:)` の挙動:

| `availableCommands` | 候補 |
|---|---|
| `nil`（init 未受領。初回送信前は必ずこれ） | 静的 `builtinSlashCommands` 10 件＋`.claude/commands` / `.claude/skills` 走査 |
| 非 `nil` | その名前だけ（走査由来を混ぜ戻さない）。`__` 接頭辞は除外・重複は一意化・順序保持 |

一覧由来の subtitle は ①静的リストの同名 ②`.claude/skills/<名前>/SKILL.md` の `description` ③`.claude/commands/<名前>.md` ④なし の順で補う。5 秒 TTL キャッシュ（ADR 0053）のキーには一覧を含める。静的 `builtinSlashCommands` はフォールバック専用に 10 件（`/compact` `/clear` `/model` `/init` `/config` `/mcp` `/context` `/usage` `/doctor` `/review`）へ縮小した——実測でセッションに存在しなかった 13 件（`/help` `/plugin` `/permissions` `/status` `/cost` `/memory` `/output-style` `/export` `/statusline` `/todos` `/rewind` `/resume` `/hooks`）は削除済み。凍結 `AcceptanceAvailableCommandsEventTests`・`AcceptanceInitSlashCommandsTests`・`AcceptanceBuiltinSlashCommandsTests`・`AcceptanceComposerAvailableCommandsTests`。**Codex / Cursor は一覧の供給源が無くフォールバックのまま**。
