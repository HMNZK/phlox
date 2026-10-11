---
status: active
last-verified: 2026-10-11
---

# 共通の新規チャット開始画面（要件・受け入れ基準・修正範囲）

> **このファイルの役割**: セッションの始め方を「共通の新規チャット画面」1 つにまとめるときに満たすべき条件、
> 受け入れ基準、廃止するもの・変えるもの・影響しないものの一覧。
> **書かないもの**: 実装後の構成（→ 実装後に architecture/ へ）、なぜこの設計か（→ [ADR 0183](../adr/0183-unified-new-chat-start-screen.md)）。
> **デザインの見本**: [ClaudeDesign/new-chat-start-reference.png](ClaudeDesign/new-chat-start-reference.png)（ユーザー提示の参考画像。Claude アプリの開始画面）。

## 1. 解決したい問題

セッションを始める入口が 3 つあり、どれも「先に種類と開き方を選ばせてから起動する」形になっている。

1. **新規セッションの表**（`NewSessionTable` のポップオーバー）。種類 × チャット/ターミナルの表で選ぶ。
2. **起動カード**（`AgentStartCardsView`）。プロジェクトを選んでセッション未選択のときに主画面へ出る。
3. **同じフォルダの確認ダイアログ**（`SpawnGuardSheet`）。同じフォルダで別のセッションが動いていると、起動の前に必ず割り込む。

ユーザーがやりたいことは「プロジェクトの ＋ を押して、すぐ書き始める」ことである。使うハーネス（Claude Code / Codex / Cursor）とモデル、worktree で分けるかどうかは、書きながら入力欄の中で選べればよい。

## 2. 用語

| 用語 | 意味 |
|---|---|
| ハーネス | セッションを動かすエージェント CLI の種類。`AgentRef`（組込 `claudeCode` / `codex` / `cursor` とカスタム） |
| 新規チャット画面 | 本仕様で作る共通の開始画面。挨拶の見出し・中央の入力欄・提案チップからなる |
| 下書き | 新規チャット画面で入力中の状態。**まだセッションもプロセスも存在しない**。送信した時点でセッションを作る。プロジェクトごとに 1 つ持つ |
| 起動中のセッション | 送信直後にサイドバーへ出る行。CLI の起動（worktree 作成を含む）が終わるまでの状態で、初回メッセージを預かっている |
| ハーネス・モデル選択 | 入力欄のチップ。「Codex: gpt-6.1-sol」のようにハーネスとモデルを組で選ぶ |
| 作業場所の選択 | 入力欄のドロップダウン。「既存ディレクトリ」か「新しい worktree」を選ぶ |

## 3. ユーザーが決めた事項（2026-10-11）

| # | 問い | 決定 |
|---|---|---|
| D1 | ターミナルのセッションの始め方 | 新規チャット画面はチャット専用にする。ターミナルは**別のメニュー項目から**起動する（§6.6） |
| D2 | worktree の初期値と、プロジェクト単位の「git worktree で隔離する」設定 | **プロジェクト設定を廃止**する。作業場所の選択は毎回「既存ディレクトリ」から始まる |
| D3 | 同じフォルダで別のセッションが動いているときの通知 | **何も出さない**。選んだとおりに起動する |
| D4 | 参考画像から取り入れる要素 | **挨拶の見出し**と**提案チップ**。音声入力（マイク）は取り入れない |
| D5 | 提案チップの動き | 押すと**定型文を入力欄に入れる**（送信はしない） |
| D6 | D2 に伴う CLI・API・iPhone・子セッションの起動場所 | **常に既存ディレクトリでよい**。worktree の指定を CLI/API に足すのは必要になってから |
| D7 | セッションはできたが初回送信に失敗したとき | **セッションを残す**。そのセッションの入力欄に本文を戻し、そこから再送する（二重にセッションができない） |
| D8 | 送信してから起動が終わるまでの画面 | **すぐセッションへ移る**。送信した瞬間にサイドバーへ「起動中」の行を出して選択する。新規チャット画面のそのプロジェクトの下書きは空になる |
| D9 | 下書きを持つ単位 | **プロジェクトごと**。A と B で別々の下書きを保ち、戻るとそれぞれの書きかけが出る |
| D10 | 「履歴から再開」の範囲 | 本体フォルダに加えて、そのプロジェクトで過去に **worktree で進めた会話も含める** |
| D11 | 「新しい worktree」で送ったときの行の出るタイミング | worktree の作成が終わってから行が出てよい（その間はトースト）。承認済み |
| D12 | 凍結テスト `AcceptanceRestoreAbortNoSpawnTests` の 1 つ目の書き換え | 意図を保って条件だけ置き換えることを承認（設計書 §7.3） |

AI が既定値で決めた事項（異論があれば変える）:

| # | 事項 | 既定 |
|---|---|---|
| E1 | 旧版へ戻したときの互換 | 新版で旧データを読めることだけを保証する。新版で作ったデータを旧版で開いたときの作業場所は保証しない |
| E2 | 対象プロジェクトが決まらないときの「新規ターミナルセッション」 | 押せなくする（プロジェクト行のメニューからは常に対象が決まる） |
| E3 | ツールバーの `WorktreeMenuButton` に同居する「プロジェクト名を変更…」 | 残す。worktree の切替だけを消す |
| E4 | 作業場所・プロジェクトを変えた後の入力済み `@ファイル` | 候補は新しい場所で取り直す。入力済みの文は書き換えない |
| E5 | 起動中のセッションの入力欄 | 初回メッセージは起動完了まで送らない（送信ボタンを押せない）。本文の編集もできない |

## 4. 現状（調査の根拠つき）

パスは `macos/Packages/DashboardFeature/Sources/DashboardFeature/` を `DF/` と略す。

### 4.1 入口（すべて新規セッションの表か起動カードに行く）

| 入口 | 場所 |
|---|---|
| メニュー「ファイル ▸ 新規セッション…」⌘N | `macos/App/PhloxApp.swift:692-698`（`router.newSessionTablePresented = true`） |
| サイドバー下端「＋ 新規セッション」 | `DF/Dashboard/DashboardView.swift:695-725` |
| サイドバーを隠したときの上端ポップオーバー | `DF/Dashboard/DashboardView.swift:172`、`newSessionTableBinding`（:932） |
| プロジェクト行の「＋」（ホバー時） | `DF/Dashboard/SidebarRows.swift:83-89`（VoiceOver アクション :119） |
| プロジェクト行の右クリック・「⋯」の「新規セッション…」 | `DF/Dashboard/DashboardSidebarView.swift:512-515` |
| グリッドでセッション 0 件のときの空状態 | `DF/Dashboard/DashboardView.swift:634`（`NewSessionPopoverButton`） |
| 単体表示でセッション未選択の主画面（起動カード） | `DF/Dashboard/DashboardDetailView.swift:136-148`（`StartAreaPolicy` の `.agentStartCards`） |

表の本体は `DF/Dashboard/StartScreenViews.swift`（`NewSessionTable` :204、`NewSessionTableRow` :397、`NewSessionPopoverButton` :413、`NewSessionKeys` :444）、行の組み立ては `DF/Dashboard/NewSessionMenuModel.swift`、表の組み立ては `DF/Dashboard/DashboardView.swift:948`（`newSessionTable(projectID:)`）。

### 4.2 起動の流れ（作成と同時に CLI が動く）

- すべての入口は `DashboardView.createSession`（`DF/Dashboard/DashboardView.swift:1120`）を通り、`DashboardViewModel.spawnNewSession(ref:projectID:backend:)`（`DF/Dashboard/DashboardViewModel.swift:1205`）を呼ぶ。
- **作成した時点で CLI を起動する**。Claude は `ClaudeChatClient.start()` が `claude -p --input-format stream-json --session-id …` を起動し、Codex は `startNew` で `initialize` と `threadStart` を行い、Cursor は `cursor-agent create-chat` で会話 ID を取る（`SessionSpawnService.initialResumeID` :906）。
- **ハーネスは作成後に変えられない**。`ChatSessionViewModel.agentRef` と `PersistedSessionDescriptor.agentRef` はどちらも `let`。
- そのため「入力欄でハーネスを選ぶ」には、**送信するまでセッションを作らない下書き状態**が必要になる。macOS にはこの状態が無い。iOS には既にある（`SessionComposeDraft`、`isAwaitingInitialSpawn`（`ios/.../SessionDetailViewModel.swift:780`）、ADR 0008）。

### 4.3 モデルの選び方

- 一覧の出所は `AgentModelCatalog`（`AgentDomain/AgentModelCatalog.swift`）の内蔵リストで、起動時に `LiveAgentModelProvider` が CLI に問い合わせて上書きする。既定モデルは `AgentModelCatalog.defaultModel(for:)`（:137）が唯一の定義。
- 入力欄のチップの集合は `composerControls(for:)`（`SessionFeature/ComposerSettingsControls.swift:26-37`）。Claude と Codex は model・effort・permission、Cursor は model・mode、カスタムは無し。
- CLI への渡し方はハーネスごとに違う。Claude は起動引数 `--model` `--effort` `--permission-mode`（`ClaudeChatClient+Respawn.swift:188-196`）、Codex は開始（`threadStart`、`ChatSessionViewModel.swift:950`）の後に `updateThreadSettings`（同 :1464 ほか）で当てる、Cursor はターンごとの起動引数 `--model` `--mode`（`CursorChatClient.swift:128-133`）。なお Codex の開始要求 `ThreadStartParams` には `model` 項目がある（`CodexAppServerKit/AppServerRequests.swift`）が、今は使っていない。
- 新規作成時は「最後に使った設定」（`phlox.lastUsedChatSettings.<agentID>.model` / `.effort`、`LastUsedChatSettingsStore.swift:14`）を `startNew` で当て直す（`SessionSpawnService.swift:871-876`）。GUI の起動経路にモデルを渡す引数は無い。
- iOS には「ハーネスとモデルの組」を選ぶピッカーが既にある（`ModelPickerEntry(kind, modelID, displayName)`、`ios/.../SessionDetailViewModel.swift:109`、`ModelPickerSheet.swift`）。

### 4.4 worktree と同じフォルダの確認

- 確認ダイアログは `SpawnGuardSheet`（`DF/Dashboard/StartScreenViews.swift:516`）、状態は `SpawnGuard.collision`（:467）、相手の検出は `NewSessionCollisionGate.peers`（:484）と `WorkspaceCollisionPolicy`。出すのは GUI の `createSession` だけ（`DashboardView.swift:1136-1141`）。
- worktree で分けるかは**プロジェクト単位の設定** `Project.worktreeIsolationEnabled`（`AgentDomain/Project.swift:33`、`projects.json`）で決まる。切り替える場所は 3 つ: サイドバーのプロジェクトメニュー（`DashboardSidebarView.swift:518`）、ツールバーの `WorktreeMenuButton`（`DashboardToolbar.swift:379`）、メニューバー（`App/PhloxApp.swift:1051`）。
- 1 回だけ上書きする引数 `isolationOverride` がある（`SessionSpawnService.swift:540-545`）。「worktree なしで起動」を選ぶと `PersistedSessionDescriptor.worktreeIsolationOptOut` に残す。
- **起動と復元はプロジェクト設定を読んで worktree を使うか決める**（読む所: `SessionSpawnService.swift:969` の `project.usesWorktreeIsolation`、`WorktreeIsolationPlanner.swift:72`。上書きは `SessionSpawnService.swift:544` がプロジェクトのコピーに書き込む形。復元 `SessionRestoreCoordinator.swift:157,248` は `worktreeIsolationOptOut` だけを上書きとして渡す）。`worktreeIsolationOptOut` を書くのは `DashboardViewModel.swift:1440` と `SessionPersistenceCoordinator.swift:243`。プロジェクト設定を消すと、隔離して始めたセッションが復元で隔離されなくなる（§6.5 で手当てする）。
- `WorkspaceCollisionPolicy` と `workspaceSessionWorkspaces` は確認ダイアログ以外にも使われている（`Editor/EditorPanelTargetPolicy.swift:30`、`AgentDomain/SessionChangeScope.swift:60`、`DashboardView.swift:925` の `editorPanelWorkspaces`）。
- `NewSessionCollisionGate` には確認ダイアログ用の `peers` のほかに、worktree 失敗ダイアログ用の `worktreeFailureLog`・`existingWorktree` がある（`DashboardView.swift:1163,1166` が使う）。
- worktree の作成・失敗時の中止（ADR 0170）・終了時の後始末（`DashboardViewModel.cleanupOwnedWorkspace` :1926）は、起動ごとの指定で動くので変えずに使える。パスは `<AppSupport>/workspace/<SessionUUID>`、ブランチは `phlox/session/<uuid>`。

### 4.5 既定の開き方

- 設定「新規セッションの既定の開き方」（チャット / ターミナル）は `phlox.defaultSessionBackend`（`AgentDomain/DefaultSessionBackendPreference.swift:10`）、設定画面は `App/SettingsView.swift:37,54,158-165`。
- 使う場所は新規セッションの表・起動カード・`DashboardViewModel.swift:534,542`（`spawnNewSessionUsingDefaultProject`、GUI からは呼ばれずテストだけが使う）。

### 4.6 履歴から再開

- 起動直後の空のチャットに「履歴から再開」カード（`ChatHistoryStartView`、`SessionFeature/ChatSessionView.swift:74`、条件 `shouldOfferHistoryStart` `ChatSessionViewModel.swift:461`）が出る。
- 送信までセッションを作らない形にすると「起動直後の空のチャット」が現れなくなり、このカードの出番が無くなる（§6.4 で開始画面へ移す）。

## 5. 画面仕様

### 5.1 配置（見本の画像に合わせる）

```
            [Phlox ロゴ] {名前}さん、さあ始めましょう！

   ┌──────────────────────────────────────────────────────────┐
   │ やりたいことを入力（/ でコマンド）                          │
   │                                                          │
   │ ＋  [Phlox-oss ⌄] [既存ディレクトリ ⌄]   [Codex: gpt-6.1-sol ⌄] [中 ⌄] [権限 ⌄] (↑) │
   └──────────────────────────────────────────────────────────┘

    [コードレビュー] [バグ修正] [テスト追加] [コードの説明] [リファクタ]

                         履歴から再開…
```

- 主画面の中央に置く。見出し・入力欄・チップ・「履歴から再開…」を縦に並べ、全体を上下中央に寄せる。
- 色・角丸・文字は既存のデザインシステム（`DSColor` 等）に合わせる。見本の Claude の配色・ロゴは使わない（ロゴは Phlox のアイコン）。

### 5.2 挨拶の見出し

- 文言は「{名前}さん、さあ始めましょう！」（英語: "Welcome back, {name}"）。
- 名前は `NSFullUserName()` の最初の語。空なら `NSUserName()`。

### 5.3 入力欄

| 要素 | 仕様 |
|---|---|
| 本文 | 既存の `ChatComposer` の入力部をそのまま使う（改行・貼り付け・画像の貼り付け・↩ で送信） |
| ＋ | 既存の添付（`ComposerAttachPlaceholder`）。添付は初回メッセージと一緒に送る。選んだハーネスが画像に非対応（Cursor。`ChatSessionViewModel.swift:791`）のときは、添付を消さずに残し、「Cursor は画像を送れません」と出して送信できなくする |
| `@ファイル` 候補 | 選択中のプロジェクトと作業場所を基準に取る。どちらかを変えたら候補を取り直す。入力済みの文は書き換えない（E4。今は候補の取得場所を固定している `ComposerSuggestions.swift:459,767`） |
| プロジェクト | 登録済みプロジェクトの一覧から選ぶ。初期値は §6.1。選び直すと、そのプロジェクトの下書きに切り替わる（D9） |
| 作業場所 | 「既存ディレクトリ」（初期値）/「新しい worktree」。プロジェクトが git リポジトリでないときは「新しい worktree」を選べない（理由をツールチップで示す） |
| ハーネス・モデル | §5.4 |
| effort・権限・mode | 選んだハーネスの `composerControls(for:)` をそのまま出す（Claude/Codex: effort・権限、Cursor: mode）。値は「最後に使った設定」から始める。候補の出どころは §5.4 |
| 送信 | ↩ またはボタン。本文が空で添付も無いときは押せない |

### 5.4 ハーネス・モデル選択

- チップの表示は「{ハーネスの表示名}: {モデルの表示名}」（例: `Codex: gpt-6.1-sol`、`Claude Code: Opus 5.5`）。
- 押すとメニューを開く。ハーネスごとの区切りの下にモデルを並べる。一覧は `AgentModelCatalog.models(for:)`（CLI 問い合わせで上書き済みのもの）。
- 対象はチャットに対応した組込ハーネス（`supportsStructuredChat == true`）だけ。カスタムエージェントはチャット非対応なので出さない（ターミナルのメニューから起動する。§6.6）。
- CLI が見つからないハーネスは区切りごと「未検出」と出して選べなくする。
- 初期値は「新規チャットで最後に送信したハーネス」（新しい保存キー `phlox.newChat.lastHarness`）と、そのハーネスの「最後に使った設定」。どちらも無ければ Claude Code と `AgentModelCatalog.defaultModel(for:)`。
- 「最後に使った設定」は今 model と effort しか保存していない（`LastUsedChatSettingsStore.swift:3`）。権限と Cursor の mode も保存するように広げる。既存セッションで設定を変えたときも今どおり更新する（「最後に送信したもの」ではなく「最後に使ったもの」）。
- ハーネスを替えたら effort・権限・mode のチップも替わったハーネスのものに入れ替える。
- **effort・権限・Plan の候補の出どころ**: 今の Codex は候補を起動中の Codex に問い合わせている（`ChatSessionViewModel.swift:1674,2610`）。下書きの間は Codex が動いていないので、effort と画像の可否はモデル一覧の取得（`model/list`）の結果から、権限は内蔵の 3 つから出す（設計書 §4.3）。起動後に問い合わせた候補と違えば、起動後の候補を正とする。

### 5.5 提案チップ

- 固定の 5 個。押すと入力欄に下書き文を入れて入力欄にフォーカスを移す。送信はしない。入力欄に文字があるときは末尾に改行して足す。

| チップ | 入れる文 |
|---|---|
| コードレビュー | 「未コミットの変更をレビューして、問題点を重要度順に挙げてください。」 |
| バグ修正 | 「次の不具合を調べて、根本原因を直してください: 」 |
| テスト追加 | 「次の機能にテストを追加してください: 」 |
| コードの説明 | 「このプロジェクトの構成と主な処理の流れを説明してください。」 |
| リファクタ | 「次のコードを、振る舞いを変えずに読みやすく整理してください: 」 |

## 6. 機能要件

### 6.1 入口

- **FR-1** 次の操作はすべて新規チャット画面を主画面に出す。どれもセッションを作らない。
  - ⌘N（メニュー「ファイル ▸ 新規チャット」。旧「新規セッション…」を改名）
  - サイドバー下端の「＋ 新規チャット」
  - プロジェクト行の「＋」と、右クリック・「⋯」の「新規チャット」
  - 単体表示でセッション未選択のとき（起動カードの置き換え）
  - グリッドでセッション 0 件のときの空状態のボタン
- **FR-1a** 「新規チャット画面を出す」とは、単体表示に切り替えて**セッションの選択を外し**（`router.selectedSession = nil`）、共通ターミナルの前面表示も外す（`router.commonTerminalSelected = false`。`SessionTabsContainer.swift:31`）ことを指す。新しい画面状態のフラグは足さず、今の `StartAreaPolicy`（プロジェクト選択あり・セッション未選択）の分岐をそのまま使う。セッションを選択中・グリッド表示中・共通ターミナル表示中に ⌘N を押した場合も同じ。
- **FR-2** プロジェクトの初期値は、プロジェクト行から開いたときはそのプロジェクト。それ以外は、選択中のプロジェクト → 直前に選択していたセッションのプロジェクト → プロジェクトが 1 つならそれ → 無ければ未選択。今の `newSessionTableProjectID`（`DashboardView.swift:942-946`）と同じ順。
- **FR-2a** プロジェクトが未選択のときも新規チャット画面を出す（今の `SelectProjectPlaceholderView` を置き換える）。入力欄のプロジェクト選択が空で、選ぶまで送信できない。
- **FR-3** プロジェクトが 1 つも無いときは、今の `StartOnboardingView`（フォルダの登録案内）を出す。⌘N はこのときも押せて、同じ案内を出す（今はプロジェクト 0 件で無効。`PhloxApp.swift:699`）。
- **FR-4** 新規チャット画面を出したら入力欄にフォーカスを置く。

### 6.2 下書き

- **FR-5** 下書きは**プロジェクトごとに 1 つ**（D9。プロジェクト未選択の下書きも 1 つ）、メモリにだけ持つ。保存も復元もしない。下書きだけではサイドバーに行を出さない。`AppRouter` は全ウィンドウで共有されている（`PhloxApp.swift:102` の `WindowGroup` がどのウィンドウにも同じ `composition.router` を渡す）ので、下書きも全ウィンドウで共有になる。
- **FR-6** 別のセッションや別のプロジェクトを選んでから戻ったとき、そのプロジェクトの送っていない本文・添付・作業場所・ハーネス・モデル等の選択は残っている。別プロジェクトの ＋ を押したときは、そのプロジェクトの下書き（無ければ空）に切り替わる。
- **FR-6a** プロジェクトを削除したら、そのプロジェクトの下書きを捨てる。新規チャット画面がそのプロジェクトを表示していたら、プロジェクト選択を空にする（送信できない）。

### 6.3 送信

- **FR-7** 送信すると次の順に処理する（D8）。
  1. 送信時点の本文・添付・プロジェクト・作業場所・ハーネス・モデル・effort・権限（mode）を確定し、そのプロジェクトの下書きを空にする。送信直前にプロジェクトがまだ存在するか確かめ、無ければ送らずに下書きを戻す。
  2. セッションの行を「起動中」としてサイドバーに出して選択する。「既存ディレクトリ」ではほぼ即時。「新しい worktree」では worktree の作成（数秒）が終わってから行が出て、その間はトーストを出す（設計書 §5.1）。初回メッセージはこのセッションが預かり、入力欄に表示する（E5: 起動完了までは編集・送信できない）。
  3. 起動する。作業場所が「新しい worktree」なら `isolationOverride: true`、「既存ディレクトリ」なら `false` を渡す。
  4. **起動の成功を確かめてから**、預かった本文と添付を既存の送信経路で初回メッセージとして送る。成功とみなすのは、Claude はプロセスが起動して失敗の通知が無いこと（今の `ClaudeChatClient.start()` :282 は失敗を通知するだけで正常に戻る）、Codex は開始と設定の適用（モデル・effort・権限）が両方成功したこと（今は適用失敗を通知するだけ。`ChatSessionViewModel.swift:943,962`）、Cursor は会話 ID が取れたこと。
- **FR-8** モデル・effort・権限は**起動時の値として**渡す。ハーネスごとの当て方は今の経路をそのまま使う（Claude は起動引数、Codex は開始後の `updateThreadSettings`、Cursor はターンごとの引数）。そのため `spawnNewSession` にこれらの引数を足す（今は GUI 経路に無く、`startNew` が「最後に使った設定」を当て直すだけ）。Codex の model は `ThreadStartParams.model` で開始時に渡す（U2 で効くと確認済み）。
- **FR-9** 送信したハーネスを `phlox.newChat.lastHarness` に、モデル等を `phlox.lastUsedChatSettings.<agentID>.*`（権限・mode を足したもの）に書く。
- **FR-10** 失敗したときは、本文を失わず、セッションも二重にしない（D7）。
  - **起動の失敗**（CLI の起動失敗・Codex の設定適用失敗）: セッションの行を残して失敗を表示し、預かった本文を入力欄に戻す。ユーザーは「再起動」して再送するか、セッションを閉じる（閉じると今の後始末で worktree も片付く）。
  - **worktree 作成の失敗・Codex の app-server 起動の失敗**（どちらも行が出る前）: 今のダイアログ（worktree は `.worktreeFailed` の「隔離なしで起動 / 既存の worktree を使う / 閉じる」、Codex は `spawnError`）を出し、本文をそのプロジェクトの下書きに戻す。
  - **起動後の初回送信の失敗**（添付の拒否・Cursor のターン失敗など。`ChatSessionViewModel.swift:3615,3653`、`CursorChatClient.swift:177`）: セッションを残し、本文と添付をそのセッションの入力欄に戻す。再送はそのセッションから行う。
- **FR-11** worktree の作成中は今のトースト（`worktreeProgressToast`）を出す。
- **FR-12** 同じフォルダで別のセッションが動いていても確認を出さずに起動する（D3）。

### 6.4 履歴から再開

- **FR-13** 新規チャット画面に「履歴から再開…」を出す。選択中のハーネスが Claude Code か Codex で、そのプロジェクトに履歴があるときだけ出す（今の `shouldOfferHistoryStart` と同じ条件）。
- **FR-13a** 一覧の範囲は、本体フォルダの会話に加えて、そのプロジェクトで過去に worktree で進めた会話を含める（D10）。今の一覧は作業フォルダが一致する会話だけを出す（`ClaudeSessionHistory.swift:72`、`CodexSessionHistory.swift:44`）。worktree の会話は作業フォルダが `<AppSupport>/workspace/<SessionUUID>` なので、worktree を作るたびに「その場所 → プロジェクト」の対応を記録し、一覧はその記録を使って集める（記録の置き場所は U6）。元の worktree が消えていても一覧には出す。
- **FR-14** 押すと履歴一覧（`ChatHistoryStartView` の一覧部分）を出す。選ぶと、そのハーネスでセッションを作ってその会話を再開する。作業場所は新規チャット画面の選択に従う（worktree の会話を選んでも、元の worktree には戻らない）。再開後のモデル・effort・権限は新規チャット画面の選択を当てる。Codex の今の再開経路は履歴 ID しか渡さない（`ChatSessionViewModel.swift:658`、`CodexAppServerClient.swift:539`）ので、作業場所も渡す（渡せばその場所で動くことを U7 で確認済み）。

### 6.5 worktree 設定の廃止（D2）

- **FR-15** プロジェクト単位の「git worktree で隔離する」を 3 か所（サイドバーのプロジェクトメニュー、ツールバーの `WorktreeMenuButton`、メニューバー）から消す。
- **FR-16** worktree で分けたかどうかは、**保存済みの作業フォルダが、そのセッションの worktree の場所（`<AppSupport>/workspace/<SessionUUID>`）と一致するか**で決める。新しい保存項目は足さない。新規は送信時の選択で決める。復元は今の「隔離オフ後の復元」の判定（`SessionSpawnService.swift:969-985`: 保存済みの作業フォルダが worktree の場所と一致し、登録済みの worktree であることを確かめる）を、プロジェクト設定に関係なく常に使う。worktree が消えていたら今の作り直し確認（`WorktreeRecreationDialog`）を出す。`WorktreeIsolationPlanner.swift:72` がプロジェクト設定を読む所と、`SessionSpawnService.swift:544` のプロジェクトのコピーへの書き込みは無くす。
- **FR-17** 旧データの移行: FR-16 の判定は作業フォルダという事実だけを見るので、「この起動だけ worktree」で始めたセッションや、隔離した後でプロジェクト設定をオフにしたセッションも同じく拾える。旧設定の 2 項目（`Project.worktreeIsolationEnabled`・`worktreeIsolationOptOut`）は読まず、書かない（書いている `DashboardViewModel.swift:1098,1440`・`SessionPersistenceCoordinator.swift:243` を止める）。読み込みで壊れないよう、項目の定義（読み捨て）は残す。旧版へ戻したときの作業場所は保証しない（E1）。保存済みの作業フォルダは必須項目で、隔離したセッションでは worktree の場所が保存されている（U8 で確認済み）。
- **FR-17a** worktree で動いているチャットは別プロジェクトへ移動できない今の制限（`DashboardSidebarView.swift:547-548`、`canMoveSession`）を残す。そのため、移動したチャットの worktree の扱いは生じない。
- **FR-18** Control API（`POST /sessions`）・CLI `spawn`・子セッションの起動は、常に既存ディレクトリで起動する（今は隔離オンのプロジェクトでは worktree になる。iOS からの `POST /sessions` も同じ。§9 の挙動変化）。

### 6.6 ターミナルのセッション（D1）

- **FR-19** メニュー「ファイル ▸ 新規ターミナルセッション ▸」に、検出済みの全ハーネス（組込 3 種とカスタム）を並べる。選ぶと対象プロジェクト（FR-2 と同じ順）の既存ディレクトリで、ターミナルのセッションを作って選択する。対象プロジェクトが決まらないとき（0 件、または複数あって未選択）はメニューを押せなくする（E2）。今の `createSession` は先頭のプロジェクトへ進む（`DashboardView.swift:1101,1128`）が、それはやめる。
- **FR-20** プロジェクト行の右クリック・「⋯」にも同じ「新規ターミナルセッション ▸」を置く。対象はそのプロジェクト。
- **FR-21** 設定「新規セッションの既定の開き方」と保存キー `phlox.defaultSessionBackend` を廃止する（チャット/ターミナルを入口で分けたので選ぶ場面が無い）。

## 7. 非機能要件

- **NFR-1** 下書きの間は、会話用の CLI プロセス（チャットのセッション）を起動しない。アプリが定期的に行うモデル一覧の取得（`CompositionRoot.swift:49,58`、`AgentModelProviders.swift:141`）は対象外で、今のまま動いてよい。
- **NFR-2** 主要な部品に `accessibilityIdentifier` を付ける（`newChat.composer`、`newChat.projectPicker`、`newChat.workspacePicker`、`newChat.harnessModelPicker`、`newChat.sendButton`、`newChat.suggestion.<n>`、`newChat.historyResume`）。
- **NFR-3** 文言は日本語と英語の両方を `macos/App/Localizable.xcstrings` に手で足す（`extractionState: manual`）。
- **NFR-4** キーボードだけで操作できる（⌘N → 入力 → ↩。チップとメニューは Tab で移れる）。VoiceOver で各チップの役割が読める。

## 8. 修正範囲

### 8.1 廃止する

| 対象 | 場所 |
|---|---|
| 新規セッションの表 | `NewSessionTable`・`NewSessionTableRow`・`NewSessionPopoverButton`・`NewSessionKeys`（`StartScreenViews.swift`）、`NewSessionMenuModel.swift`、`AppRouter.newSessionTablePresented`、`DashboardView` の `newSessionTable(projectID:)`・`newSessionTableBinding`・`newSessionTableProjectID`・サイドバー非表示時の上端ポップオーバー |
| 同じフォルダの確認ダイアログ | `SpawnGuard.collision`・`SpawnGuardSheet` の確認部分・`NewSessionCollisionGate.peers`（`StartScreenViews.swift`）、`createSession` の確認分岐（`DashboardView.swift:1136-1141`）。`worktreeFailureLog`・`existingWorktree` は worktree 失敗ダイアログが使うので残す。`WorkspaceCollisionPolicy`・`workspaceSessionWorkspaces` はエディタパネルと変更範囲が使うので残す |
| 起動カード | `AgentStartCardsView`・`AgentStartProjectHeader`・`AgentStartCards.swift` 一式・`AgentStartCardSelection`・`DashboardDetailView` の `.agentStartCards` 分岐と `isolates:`（:122） |
| 未選択のプレースホルダ | `SelectProjectPlaceholderView`（FR-2a で新規チャット画面に置き換え） |
| 既定の開き方 | `DefaultSessionBackendPreference`・設定画面の分節ボタン・`spawnNewSessionUsingDefaultProject` |
| 呼ばれていない起動関数 | `spawnNewClaudeCodeSession`（`DashboardViewModel.swift:1522`。テスト以外から呼ばれていない。起動経路を触るついでに消す） |
| プロジェクトの worktree 設定 | 3 か所の切替 UI、`DashboardViewModel.swift:1098` の書き込み |
| 使わなくなる文言 | 確認ダイアログの 4 キー（`Localizable.xcstrings` :4578・:7759・:4831・:5095）、既に未使用の「同じ作業ディレクトリで複数のエージェントが…」（:4842）、表のフッター・起動カードの文言 |

### 8.2 変える

| 対象 | 変更 |
|---|---|
| `DashboardViewModel.spawnNewSession` | モデル・effort・権限（mode）と初回メッセージを受け取る。行を「起動中」で先に出し、起動の成功を確かめてから初回メッセージを送る（FR-7・10） |
| `ClaudeChatClient`・Codex の開始処理 | 起動・設定適用の失敗を呼び出し元が判定できる形で返す（今は通知だけ。FR-7 の 4） |
| `SessionSpawnService`・`WorktreeIsolationPlanner`・`SessionRestoreCoordinator`・`SessionPersistenceCoordinator` | 隔離の判断をプロジェクト設定ではなく保存済みの作業フォルダから取る（FR-16・17）。Control API・CLI・子セッションの経路は「隔離しない」を渡す（FR-18） |
| ⌘N の有効条件 | プロジェクト 0 件でも押せるようにする（FR-3） |
| `PersistedSessionDescriptor`・`Project` | `worktreeIsolationOptOut`・`worktreeIsolationEnabled` を読み捨ての互換項目にする（書かない・判断に使わない） |
| `LastUsedChatSettingsStore` | 権限と Cursor の mode も保存する（§5.4） |
| `ComposerSuggestions` | `@ファイル` 候補の基準をプロジェクト・作業場所の変更に追従させる（§5.3） |
| `ClaudeSessionHistory`・`CodexSessionHistory` | プロジェクトの過去の worktree の会話も集める（FR-13a） |
| Codex の履歴再開 | 作業場所とモデル等を渡す（FR-14） |
| ツールバーの `WorktreeMenuButton` | worktree の切替だけを消し、「プロジェクト名を変更…」は残す（E3。`DashboardToolbar.swift:444`） |
| プロジェクトの削除 | そのプロジェクトの下書きを捨てる（FR-6a） |
| `StartAreaPolicy`・`DashboardDetailView` | セッション未選択の主画面を新規チャット画面にする |
| ⌘N・サイドバー・プロジェクト行・グリッド空状態 | 新規チャット画面を出す（FR-1） |
| メニュー | 「新規チャット」「新規ターミナルセッション ▸」（FR-19） |
| `.worktreeFailed` ダイアログ | 残す。呼び出し元を送信処理に付け替える |

### 8.3 新しく作る

- 新規チャット画面の View（見出し・入力欄・チップ・履歴から再開）と、下書きの状態（プロジェクトごと。全ウィンドウで共有）。
- 起動中のセッションが初回メッセージを預かる状態と、その表示。
- worktree の場所とプロジェクトの対応の記録（FR-13a）。
- ハーネス・モデル選択のメニュー（iOS の `ModelPickerEntry` と同じ「ハーネスとモデルの組」の形）。
- プロジェクト選択・作業場所選択のドロップダウン。
- 入力欄の部品は `ChatComposer` から切り出して、セッション画面と新規チャット画面で共用する。

### 8.4 影響しない（確認済み）

- Control API `POST /sessions` と CLI `spawn` の受け付け項目、モバイル API の形、iOS アプリのコード（iOS は自前の下書き画面を持つ）。ただし起動場所は FR-18 のとおり変わる。
- 子タブの「このセッションにタブを追加」（`NewTabChooser`）。セッション作成とは別物。
- 既存セッションのチャット画面の入力欄（部品を共用するだけで見た目と動きは変えない）。
- worktree の作成・中止（ADR 0170）・後始末。

## 9. 挙動の変化（利用者に見えるもの）

1. ＋ や ⌘N を押してもセッションはすぐできない。最初のメッセージを送った時点でできる。セッションを開いているときに ⌘N を押すと、そのセッションの選択が外れて新規チャット画面になる。送っていない下書きは、アプリを終了すると消える。
2. 同じフォルダで動いているセッションがあっても何も聞かれない。
3. 隔離オンにしていたプロジェクトでも、新規チャットは「既存ディレクトリ」から始まる。Control API・CLI・子セッションは常に既存ディレクトリで起動する。
4. ターミナルで始めたいときはメニュー（ファイル、またはプロジェクトの右クリック）から選ぶ。⌘N や ＋ からは始められない。
5. 「既定の開き方」の設定が無くなる。
6. 送信するとすぐにサイドバーへ「起動中」の行ができ、起動が終わってから最初のメッセージが届く。失敗してもセッションは残り、本文はそのセッションの入力欄に戻る。
7. Claude の使用量表示は、動いているチャットが無く、保存済みの値も無いときは、最初のメッセージを送るまで出ない（`ClaudeChatUsageSource.swift:23`。今は起動カードからセッションを作った時点で問い合わせ先ができていた）。

## 10. 先に直す資料（実装の前）

| 資料 | 対応 |
|---|---|
| ADR 0183 | 作成済み（2026-10-11） |
| ADR 0071（既定の開き方）・0082（起動カードとメニュー） | `superseded` にして 0183 へリンク済み。0086（単体表示の開始画面）は導線の決定が残るので active のまま、開始画面が置き換わる旨を追記済み |
| `architecture/dashboard-empty-state-agent-cards.md` | 実装と同時に `superseded`（今の構成の説明なので、実装までは残す） |
| `specs/ui-feature-inventory.md` 第 10 章（:375-383）ほか :77・:564・:731 | 新規チャット画面の記述に書き直す（今も旧仕様のまま古い） |
| `specs/e2e-test-design.md:73` の `session.newButton` | 新しい識別子に直す |
| `delivery/0037-ui-redesign-worklog.md` | 変えない（作業記録なので当時のまま）。新しい作業記録から参照する |
| `specs/README.md` | 本ファイルを索引に足す |

## 11. 受け入れ基準

客観的な判定は `.claude/verify.sh` が通ること（git 管理外なのでメインの checkout にある。worktree で作業するときはそこから実行する）。加えて次をテストで確かめる。

| # | 基準 | 確かめ方 |
|---|---|---|
| AC-1 | ⌘N・サイドバーの ＋・プロジェクト行の ＋・グリッド空状態のボタンを押すと、`router.selectedSession == nil`・`router.commonTerminalSelected == false`・単体表示・期待したプロジェクトが選択になり、セッション数が増えない。共通ターミナルを前面にした状態から押しても同じ | DashboardFeature の単体テスト（入口ごと） |
| AC-2 | 送信すると、選んだハーネス・モデル・effort・権限（mode）・作業場所でセッションが 1 つでき、初回メッセージが届く | fake の CLI を使う単体テスト（Claude: 起動引数の `--model` `--effort` `--permission-mode`、Codex: 開始または設定更新の model・effort・権限、Cursor: ターン引数の `--model` `--mode`） |
| AC-2a | 送信した瞬間に「起動中」の行が選択され、そのプロジェクトの下書きが空になる。起動完了前は初回メッセージを送らない | 単体テスト（起動を止めた fake） |
| AC-3 | 「新しい worktree」で送ると worktree ができ、「既存ディレクトリ」ではできない | `WorktreeIsolationSpawnTests` に足す |
| AC-4 | 同じフォルダで動作中のセッションがあるとき、送信 1 回でセッションが 1 つ増える（途中で止まらない） | 単体テスト |
| AC-5 | 失敗の 3 種（Claude の起動失敗・Codex の設定適用失敗・起動後の初回送信失敗）で、セッションが 1 つだけ残り、本文と添付がそのセッションの入力欄に戻り、初回メッセージは送られていない（起動前の失敗）／重複して送られない（再送時） | fake を使う単体テスト（種類ごと） |
| AC-5d | worktree 作成の失敗で「閉じる」を選ぶと、セッションの行が消え、本文がそのプロジェクトの下書きに戻る | 単体テスト |
| AC-5e | プロジェクト A と B の下書きが別々に残る。A の下書きがある状態で B の ＋ を押すと B の下書きが出て、A に戻ると A の書きかけが出る | 単体テスト |
| AC-5f | 下書きがあるプロジェクトを削除すると下書きが消え、送信できない | 単体テスト |
| AC-5g | Cursor を選んで画像を添付していると送信できず、添付は残っている | 単体テスト |
| AC-5a | 下書きの間は会話用の CLI プロセスを起動しない（NFR-1。モデル一覧の取得は数えない） | fake の起動器で会話プロセスの起動回数 0 を確かめる単体テスト |
| AC-5b | Control API・子セッションの起動は、旧設定がオンのプロジェクトでも worktree を作らない（FR-18） | `WorktreeIsolationSpawnTests` に足す |
| AC-5c | 「履歴から再開」の一覧に、本体フォルダの会話と、そのプロジェクトの過去の worktree の会話（worktree が消えたものも）が出る。選ぶと、選んだハーネス・作業場所・モデルで再開する | 単体テスト（一覧と再開の引数） |
| AC-6 | 次の 3 つのセッションが、プロジェクト設定に関係なく復元で同じ worktree を使い、終了で後始末される: (a) 新版で worktree を選んで始めたもの、(b) 旧版で「この起動だけ worktree」で始めたもの、(c) 旧版で隔離オンで始め、後で設定をオフにしたもの。保存済みの作業フォルダが本体フォルダのセッションは worktree を使わない | `SessionRestoreCoordinator` のテスト、`AcceptanceRestoreAbortNoSpawnTests` を作業フォルダ基準に合わせる |
| AC-7 | ハーネス・モデル・effort・権限・mode の初期値が「最後に使った設定」になる。未検出のハーネスは選べない | 単体テスト |
| AC-8 | 提案チップで定型文が入り、送信はされない | 単体テスト |
| AC-9 | 「新規ターミナルセッション ▸ Codex」とカスタムハーネスでターミナルのセッションができる。対象プロジェクトが決まらないとき（0 件・複数で未選択）はメニューを押せない | 単体テスト |
| AC-9a | プロジェクトや作業場所を変えると `@ファイル` 候補が新しい場所のものになる | 単体テスト |
| AC-10 | 見た目が見本と揃っている | `DesignSnapshotRenderTests` に新規チャット画面を足して撮る（日本語・英語、ライト・ダーク）。合否は目視で、§5.1 の並び（見出し → 入力欄 → チップ → 履歴から再開、入力欄の下段の左右の並び）と一致すること。**機械判定ではない**ので、ユーザーに画像を見せて承認を得る |
| AC-11 | 主要な操作の通し確認 | XCUITest 1 本（⌘N → 入力 → ↩ → セッションができる）。fake-agent CLI を使う（`e2e-test-design.md`） |

### 書き換え・削除するテスト

- 削除: `StartScreenRedesignTests` の表・確認ダイアログ部分、`AcceptanceNewSessionMenuModelTests`、`AgentStartCardsTests`・`AgentStartCardModesTests`・`AcceptanceAgentStartCardsTests`・`AgentStartCardsRenderPNGTests`、`AcceptanceDefaultSessionBackendTests`・`DefaultSessionBackendPreferenceWhiteboxTests`、`WorktreeIsolationSpawnTests`・`DialogRedesignTests` の**確認ダイアログを扱うテストケースだけ**（ファイルは残し、AC-3・AC-5b をここに足す）。
- 書き換え: `AcceptanceSingleModeProjectSelectTests`・`StartAreaSelectionWhiteboxTests`（起動カード → 新規チャット画面）、worktree の復元を扱うテスト（プロジェクト設定 → セッションの項目）。
- UI テストの `projects.json` の `"worktreeIsolationEnabled": false`（`macos/UITests/*`、`macos/PhloxUITests/SimulatorTabUITests.swift`）は読み込みの互換を残すので変えなくてよい。

## 12. 仮定 / 未知

- 設計の調査で U1（slash 候補は下書きでも出せる。Codex の skill 候補だけ出せない）・U3（履歴の読み込みは VM 無しで動く）・U5（`model/list` に effort・画像の可否がある。権限は無い）・U8（作業フォルダは常に保存されている）を解消し、U2・U7・U9 は実 CLI で確認した（すべて期待どおり動く）。詳細は [設計書](unified-new-chat-start-design.md) §12。
- **実装の前提**: 凍結された受け入れテスト `AcceptanceRestoreAbortNoSpawnTests` の 1 つ目を、意図を保ったまま条件だけ書き換える（設計書 §7.3。ユーザー承認済み 2026-10-11）。
- **U1**（解消）: 入力欄の「/」のコマンド候補が、セッションが無い下書きの間にも出せるか。
- **U2**（確認済み）: Codex は `ThreadStartParams.model` で渡したモデルが最初のターンから効く。
- **U3**（解消）: 履歴の読み込み部品は VM に依存しないので、セッションが無くても一覧を読める。
- **U5**（解消）: Codex の effort と画像の可否は `model/list` から取れる。権限は取れないので内蔵の 3 つを出す。
- **U6**（解消）: worktree の場所は `projects.json` の `Project` に任意項目 `worktreePaths` として記録する（設計書 §2.3）。
- **U7**（確認済み）: Codex の履歴再開で作業場所を渡すと、その場所で動く。元のフォルダが消えていても再開できる。
- **U9**（確認済み）: Claude は別のフォルダから `--resume` でき、そのフォルダで動く。元のフォルダが消えていても再開できる。
- **U8**（解消）: 隔離していたセッションは、すべて作業フォルダ（worktree の場所）を保存している。
- （旧 U4「下書きをウィンドウごとに置く」は誤りだったので取り下げた。`AppRouter` は全ウィンドウで共有されており、下書きもプロジェクトごとに全ウィンドウで共有する。FR-5）
- **仮定 A1**: セッションのタイトルは今どおり初回メッセージから付く。
- **仮定 A2**: ターミナルのセッションは worktree を選べなくてよい（D1・D2 の結果。必要になれば別に足す）。

## 13. スコープ外

- 音声入力（D4）。
- Control API・CLI・モバイル API に worktree や下書きの項目を足すこと。
- iOS アプリの変更。
- 起動後にハーネスを替えること。
- 提案チップの中身をユーザーが編集できるようにすること。

## 14. 既知のリスク

- **R1 下書きの間に CLI が無い**: 起動の失敗（未ログイン・CLI の不具合）が送信の後まで分からない。FR-10 で本文をセッションの入力欄に戻して打ち直しを防ぐ。
- **R2 worktree 設定の移行漏れ**: 移行を誤ると、隔離していたセッションが復元で本体のフォルダに移り、変更がぶつかる。AC-6 を先に書いてから実装する。
- **R3 確認ダイアログの廃止**: 同じフォルダで 2 つが同時に書き換えて変更がぶつかる場面を、知らせずに許すことになる（D3 で受け入れ済み）。
- **R4 Control API・CLI・子セッションの起動場所が変わる**: 隔離オンのプロジェクトで CLI から起動していた利用者は、worktree ではなく本体のフォルダで動くようになる（D6 で受け入れ済み）。
