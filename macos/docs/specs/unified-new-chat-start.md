---
status: active
last-verified: 2026-10-13
---

# 共通の新規チャット開始画面（要件・受け入れ基準・修正範囲）

> **このファイルの役割**: セッションの始め方を「共通の新規チャット画面」1 つにまとめるときに満たすべき条件、
> 受け入れ基準、廃止するもの・変えるもの・影響しないものの一覧。
> **書かないもの**: 実装後の構成（→ 実装後に architecture/ へ）、なぜこの設計か（→ [ADR 0183](../adr/0183-unified-new-chat-start-screen.md)）。
> **デザインの見本**: [ClaudeDesign/new-chat-start-reference.png](ClaudeDesign/new-chat-start-reference.png)（ユーザー提示の参考画像。Claude アプリの開始画面）、確定したモック `ClaudeDesign/10 New Chat Start.dc.html`（ヘッダーと使用量のバーは `ClaudeDesign/12 Header and Usage Bar.dc.html`）。実装はモックと見比べてから完了とする。
> **状態**: 段 1〜7 は実装済み（コミット 07650a0e..b23855e2）。2026-10-13 に §11 をコードと照合し、食い違い（グリッドの点線の輪・「送信待ち」の表示・使用量バーの表示設定・グリッドの「再起動」・Claude の権限の初期値・「質問あり」の文言）を直した。§1〜§9 の「現状」「廃止する」は実装前の記述のまま残す。

## 1. 解決したい問題

セッションを始める入口が 3 つあり、どれも「先に種類と開き方を選ばせてから起動する」形になっている。

1. **新規セッションの表**（`NewSessionTable` のポップオーバー）。種類 × チャット/ターミナルの表で選ぶ。
2. **起動カード**（`AgentStartCardsView`）。プロジェクトを選んでセッション未選択のときに主画面へ出る。
3. **同じフォルダの確認ダイアログ**（`SpawnGuardSheet`）。同じフォルダで別のセッションが動いていると、起動の前に必ず割り込む。

ユーザーがやりたいことは「プロジェクトの ＋ を押して、すぐ書き始める」ことである。使うハーネス（Claude Code / Codex / Cursor）とモデル、worktree で分けるかどうかは、書きながら入力欄の中で選べればよい。

## 2. 用語

| 用語 | 意味 |
|---|---|
| ハーネス | セッションを動かすエージェント CLI の種類。`AgentRef`（組込 `claudeCode` / `codex` / `cursor`。カスタムは D22 で廃止） |
| 新規チャット画面 | 本仕様で作る共通の開始画面。挨拶の見出し・中央の入力欄・提案チップからなる |
| 下書き | 新規チャット画面で入力中の状態。**まだセッションもプロセスも存在しない**。送信した時点でセッションを作る。アプリに 1 つ持つ（D27） |
| 起動中のセッション | 送信直後にサイドバーへ出る行。CLI の起動（worktree 作成を含む）が終わるまでの状態で、初回メッセージを預かっている |
| ハーネス・モデル選択 | 入力欄のチップ。ハーネスとモデルを組で選ぶ（例: Codex の gpt-6.1-sol）。チップにはハーネスのロゴとモデル名を出す（§5.4） |
| 作業場所の選択 | 入力欄のドロップダウン。「既存ディレクトリ」か「新しい worktree」を選ぶ |

## 3. ユーザーが決めた事項（2026-10-11）

| # | 問い | 決定 |
|---|---|---|
| D1 | ターミナルのセッションの始め方 | 画面から始められるのは**チャットだけ**。ターミナルでエージェントを動かすセッションを始めるメニューは作らない。ターミナルでエージェントを使いたいときは、ユーザーがターミナルに自分でコマンドを打つ（Phlox のセッションとしては登録されない）（§6.6。2026-10-11 改訂） |
| D2 | worktree の初期値と、プロジェクト単位の「git worktree で隔離する」設定 | **プロジェクト設定を廃止**する。作業場所の選択は毎回「既存ディレクトリ」から始まる |
| D3 | 同じフォルダで別のセッションが動いているときの通知 | **何も出さない**。選んだとおりに起動する |
| D4 | 参考画像から取り入れる要素 | **挨拶の見出し**と**提案チップ**。音声入力（マイク）は取り入れない |
| D5 | 提案チップの動き | 押すと**定型文を入力欄に入れる**（送信はしない） |
| D6 | D2 に伴う CLI・API・iPhone・子セッションの起動場所 | **常に既存ディレクトリでよい**。worktree の指定を CLI/API に足すのは必要になってから |
| D7 | セッションはできたが初回送信に失敗したとき | **セッションを残す**。そのセッションの入力欄に本文を戻し、そこから再送する（二重にセッションができない） |
| D8 | 送信してから起動が終わるまでの画面 | **すぐセッションへ移る**。送信した瞬間にサイドバーへ「起動中」の行を出して選択する。新規チャット画面の下書きは空になる |
| D9 | 下書きを持つ単位 | ~~プロジェクトごと~~ → **D27 で改訂**（アプリに 1 つ） |
| D10 | 「履歴から再開」の範囲 | 本体フォルダに加えて、そのプロジェクトで過去に **worktree で進めた会話も含める** |
| D11 | 「新しい worktree」で送ったときの行の出るタイミング | worktree の作成が終わってから行が出てよい（その間はトースト）。承認済み |
| D12 | 凍結テスト `AcceptanceRestoreAbortNoSpawnTests` の 1 つ目の書き換え | 意図を保って条件だけ置き換えることを承認（設計書 §7.3） |
| D13 | 見出しの文言 | 名前を出さない。10 種類の文言から、新規チャット画面を出すたびにランダムに 1 つ選ぶ（§5.2） |
| D14 | ハーネスの略号（Cl・Cx・Cu など）と図形の印 | **アプリ全体で廃止する**（新規チャット画面だけでなく、サイドバー・タブ・グリッド・対応待ち一覧・会話など今ある画面すべて）。状態の図形（承認待ちの◆・実行中の回転・待機の○ など）もすべて消し、状態は文字で示す（§6.7） |
| D15 | 未読の印 | 丸の印をやめ、未読のセッションは文字の濃さ（グレースケール）で見分けられるようにする（§6.7） |
| D16 | ハーネスのロゴ（使用量画面・ハーネス・モデルのチップ） | 今の表示（画像と、無いときの略号・記号）をやめ、各社のロゴの SVG を使う。Claude と Codex は文字色の単色で描き、Cursor は元のロゴのまま（元から黒・白・灰だけで、単色にすると形が潰れるため）（§6.7） |
| D17 | アプリの配色 | （**D29 で改訂**: アクセントは白黒）アクセント色を **#3B469B** にする（コーラルをやめる）。ダークでは文字・フォーカス枠・印だけ同じ色相を明るくした **#959CD0** にする。アクセントを使う場所は主要な操作・選択・フォーカス・リンクに限る（§6.8、ADR 0184） |
| D18 | ハーネスごとの色 | **廃止する**。略号と図形を消すと使い道が無くなるため（§6.8） |
| D19 | タブ・グリッドでの状態の表示 | **出さない**。状態はサイドバーのセッション行だけで示す（§6.7） |
| D20 | 起動に失敗した後の「再起動」 | 起動し直すだけで、**送信はしない**。本文と添付は入力欄に残し、ユーザーが自分で送る（FR-10） |
| D21 | タブが 1 つも無いプロジェクトを選んだとき | **そのプロジェクトを選んだまま**、子タブの場所に新規チャット画面を出す（FR-1a。⌘N などで送信先が決まっているときも同じ）（送信先はそのプロジェクト）。上段のタブ・サイドバーの行は選択中になり、インスペクタにはそのプロジェクトのファイルが出る（2026-10-13 ユーザー指示で、選択を外す形から改訂）。2026-10-13 に「セッションが 1 つも無い」から改訂（D27。新規チャット画面ではプロジェクトの子タブが出ないため、ターミナルやファイルのタブがあればそれを出す） |
| D22 | カスタムエージェント（`agents.json` で足す CLI） | **機能ごと廃止する**（ADR 0185、§8.6） |
| D24 | ヘッダーの「対応待ち」ボタンと対応待ちの一覧 | **一覧ごと廃止する**（⌥⌘J も）。状態はサイドバーの文字で見て、許可などはそのセッションを開いて行う。⌘J（次の対応待ちへ）は残す（§6.9） |
| D25 | 使用量の表示 | ヘッダーから消し、**ウィンドウの一番下に全幅のバー**を置いて、小さめの文字で全ハーネスの全枠を横に並べる（§6.9） |
| D26 | 単体／グリッドの切替 | ヘッダーの**右寄せ**にする（§6.9） |
| D27 | 新規チャットの下書きの単位とタブ（2026-10-13） | **アプリに 1 つ**。入力欄のプロジェクトは送信先で、選び直しても本文は消えない。新規チャット画面はどのプロジェクトのタブにも属さず、子タブ「新規チャット」は作らない。送信したら選んだプロジェクトのタブを選択し、その子タブとしてセッションを作る（ADR 0188） |
| D28 | サイドバーの開閉ボタン（2026-10-13） | ヘッダーの左に**常に**出す（今は隠しているときだけ） |
| D29 | アクセントの色（2026-10-13） | **白黒にする**（ダークは白、ライトは黒。ADR 0189） |
| D30 | プロジェクト行のホバーの ＋（2026-10-13） | 「⋯」と同じ見た目にする（既定のボタンの枠を出さない） |
| D31 | ヘッダーの空き（2026-10-13） | 選択中のタブの名前（セッション名・ファイル名など）を、サイドバーの開閉ボタンの右に**左寄せ**で出す |
| D32 | サイドバーのプロジェクト行の選択（2026-10-13） | 面の色は付けない（面はグリッドの絞り込み中だけ）。セッションを選ばずにプロジェクトを選んでいる行（↑↓で移った先）には、入力欄のチップと同じ 1pt の副文字色の枠を出して現在位置を示す |
| D33 | 上段のプロジェクトのタブの隙間（2026-10-13） | 選択中のタブはタブ帯の高さいっぱいに出し、左端はサイドバーとの境目に付ける（上・左に隙間を空けない）。角は丸めない |
| D23 | 上段のタブの構成 | 上段をプロジェクトのタブ、その下をそのプロジェクトのチャット・ターミナル・ファイルにする。共通ターミナルは廃止する。別の仕様書 `project-tabs.md`（ADR 0187）で決め、新規チャット画面と同時に実装する |

AI が既定値で決めた事項（異論があれば変える）:

| # | 事項 | 既定 |
|---|---|---|
| E1 | 旧版へ戻したときの互換 | 新版で旧データを読めることだけを保証する。新版で作ったデータを旧版で開いたときの作業場所は保証しない |
| E2 | （廃止。D1 の改訂で「新規ターミナルセッション」が無くなった） | — |
| E3 | ツールバーの `WorktreeMenuButton` に同居する「プロジェクト名を変更…」 | `WorktreeMenuButton` ごと消す。worktree の切替は作業場所のチップへ、「プロジェクト名を変更…」は上段のプロジェクトのタブの右クリックへ移す（`project-tabs.md` P6） |
| E4 | 作業場所・プロジェクトを変えた後の入力済み `@ファイル` | 候補は新しい場所で取り直す。入力済みの文は書き換えない |
| E5 | 起動中のセッションの表示 | 預かった初回メッセージは会話欄に「送信待ち」の文字を添えて出す（入力欄には置かない）。入力欄は空で「起動しています…」と出し、起動完了まで送れない（ただの無効状態と見分けるため。2026-10-11 デザイン検討で変更）。初回メッセージを送ったら「送信待ち」を外して通常の発言にする。起動に失敗したら会話欄から消し、本文を入力欄に戻す |
| E6 | 入力欄の下段の並び | 左に「＋ / ハーネス・モデル / effort / 権限（Cursor は mode）」、右に「プロジェクト / 作業場所 / 送信」。セッション画面の下段（左に設定、右にブランチ等の場所の情報）と同じ並びにする。狭いときは effort・権限から今のセッション画面と同じ「…」メニューにまとめ、プロジェクト・作業場所は名前を省略してアイコンだけにする。ハーネス・モデルと送信は常に見せる |
| E7 | 送れない理由の出し方 | 入力中は出さない。送ろうとした（↩・送信ボタン）のに送れないときだけ、入力欄の枠の下にエラーの色と印で 1 行の検証メッセージを出し、VoiceOver でも読み上げる。プロジェクトが未選択なら、プロジェクトのチップもエラーの色の枠で示す。理由が変わる・解消すると消え、次に送ろうとするまで出さない（2026-10-13 ユーザー指示で、入力欄の中に常に出す形から改訂）。本文も添付も空のときは何も出さない。文言は原因と直し方: 「プロジェクトを選んでください」「Cursor は画像を送れません。画像を外すか、画像を送れるハーネスを選んでください」「{ハーネス} が見つかりません。インストールするか、別のハーネスを選んでください」 |
| E8 | 下書きの手がかり | （D27 で廃止。下書きが 1 つになったので印は要らない） |

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
- 入力欄のチップの集合は `composerControls(for:)`（`SessionFeature/ComposerSettingsControls.swift:26-37`）。Claude と Codex は model・effort・permission、Cursor は model・mode。
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
            [Phlox ロゴ] 何から始めますか？（§5.2 の 10 種類からランダム）

   ┌──────────────────────────────────────────────────────────┐
   │ やりたいことを入力（/ でコマンド）                          │
   │                                                          │
   │ ＋ [(Codexのロゴ) gpt-6.1-sol ⌄] [高 ⌄] [Full Access ⌄]   [Phlox-oss ⌄] [既存ディレクトリ ⌄] (↑) │
   └──────────────────────────────────────────────────────────┘

    [コードレビュー] [バグ修正] [テスト追加] [コードの説明] [リファクタ]

                         履歴から再開…
```

- 主画面の中央に置く。見出し・入力欄・チップ・「履歴から再開…」を縦に並べ、全体を上下中央に寄せる。
- 色・角丸・文字は既存のデザインシステム（`DSColor` 等）に合わせる。見本の Claude の配色・ロゴは使わない。見出しの左にロゴは出さない（2026-10-12 ユーザー指示）。
- 見出しはドット書体 DotGothic16 の 32pt にする（2026-10-13 ユーザー指示。DotGothic16 は 16px の格子で作られているので、30pt ではなく倍の 32pt で描く）。書体はアプリに同梱し、ライセンスは `THIRD_PARTY_NOTICES.md` に載せる。
- 入力欄の枠は、フォーカスの有無にかかわらず通常の 1pt の枠（`fieldBorder`）にする。フォーカス中の白黒の太い枠は出さない（2026-10-13 ユーザー指示）。入力中であることはカーソルで分かる。
- 入力欄は本文に合わせて縦に伸び、セッションの入力欄と同じ上限（`ComposerHeightBounds.single.max`）を超えたら中でスクロールする（2026-10-13 ユーザー指摘で、高さの固定をやめた）。作業場所などのチップを切り替えても入力欄は作り直さない。
- 下段のチップのフォーカス枠は 1pt の副文字色（`textSecondary`）にする。白黒のアクセントでは `focusRing` の 2pt が強すぎるため（2026-10-13 ユーザー指示）。

### 5.2 挨拶の見出し

- 名前は出さない（D13）。次の 10 種類から、新規チャット画面を出すたびにランダムに 1 つ選ぶ。入力中やウィンドウの大きさを変えたときは替えない。

| # | 日本語 | 英語 |
|---|---|---|
| 1 | 何から始めますか？ | What would you like to work on? |
| 2 | 今日は何を進めますか？ | What are we building today? |
| 3 | さあ、始めましょう | Let's get started |
| 4 | 次は何を作りますか？ | What's next? |
| 5 | どこから手をつけますか？ | Where should we begin? |
| 6 | アイデアを形にしましょう | Let's turn ideas into code |
| 7 | 今日の課題を教えてください | Tell me what you're working on |
| 8 | どんな変更を加えますか？ | What would you like to change? |
| 9 | 続きを進めましょう | Let's keep going |
| 10 | 何をお手伝いしましょうか？ | How can I help? |

### 5.3 入力欄

| 要素 | 仕様 |
|---|---|
| 本文 | 既存の `ChatComposer` の入力部をそのまま使う（改行・貼り付け・画像の貼り付け・↩ で送信） |
| ＋ | 既存の添付（`ComposerAttachPlaceholder`）。添付は初回メッセージと一緒に送る。選んだハーネスが画像に非対応（Cursor。`ChatSessionViewModel.swift:791`）のときは、添付を消さずに残し、E7 の文言を出して送信できなくする |
| `@ファイル` 候補 | 選択中のプロジェクトと作業場所を基準に取る。どちらかを変えたら候補を取り直す。入力済みの文は書き換えない（E4。今は候補の取得場所を固定している `ComposerSuggestions.swift:459,767`） |
| プロジェクト | 送信先。登録済みプロジェクトの一覧から選ぶ。初期値は §6.1。選び直しても本文・添付・設定は変わらず、上段のタブの選択も変えない（D27） |
| 下段の並び | E6 |
| 送れない理由 | E7 |
| 作業場所 | 「既存ディレクトリ」（初期値）/「新しい worktree」。プロジェクトが git リポジトリでないときは「新しい worktree」を選べない（理由「git リポジトリではないため worktree を作れません」をメニューの項目の下に説明文で示す。ツールチップはキーボードと VoiceOver で読みにくいため） |
| ハーネス・モデル | §5.4 |
| effort・権限・mode | 選んだハーネスの `composerControls(for:)` をそのまま出す（Claude/Codex: effort・権限、Cursor: mode）。値は「最後に使った設定」から始める。候補の出どころは §5.4 |
| 送信 | ↩ またはボタン。本文が空で添付も無いときは押せない |

### 5.4 ハーネス・モデル選択

- チップの表示は「{ハーネスのロゴ} {モデルの表示名}」（例: Codex のロゴ＋`gpt-6.1-sol`）。ハーネス名の文字は出さない（2026-10-11 ユーザー指示）。ロゴは使用量画面と同じ各社の SVG（FR-26、`AgentBrandIcon`）で、略号・色の四角などの代わりの印は使わない（D14）。ロゴの意味が見た目だけにならないよう、読み上げは「ハーネスとモデル、Codex: gpt-6.1-sol」とハーネス名を含め、ホバーでも「Codex: gpt-6.1-sol」を出す。
- 押すとメニューを開く。上に絞り込み欄、ハーネスごとの区切り（見出しはハーネス名の文字）の下にモデルを並べ、選択中にチェック、既定のモデルに「既定」のタグ。一覧は `AgentModelCatalog.models(for:)`（CLI 問い合わせで上書き済みのもの）。
- 対象はチャットに対応した組込ハーネス（`supportsStructuredChat == true`。3 つとも）。
- CLI が見つからないハーネスは区切りごと「未検出」と出して選べなくする。
- 初期値は「新規チャットで最後に送信したハーネス」（新しい保存キー `phlox.newChat.lastHarness`）と、そのハーネスの「最後に使った設定」。どちらも無ければ Claude Code と `AgentModelCatalog.defaultModel(for:)`。保存した権限が無いときの Claude の権限は、設定のフルアクセス（`BypassSettings`）がオンなら Bypass Permissions、オフなら auto。
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
  - 単体表示でサイドバーのプロジェクトを選んだとき（セッションが 1 つも無いプロジェクトでも同じ。D21。グリッド表示では今どおり絞り込むだけ）。プロジェクトの ＋ は確認やメニューを挟まず、押した時点で切り替える
- **FR-1a** 「新規チャット画面を出す」とは、単体表示に切り替えてセッションの選択を外し、下書きの送信先を §6.1 FR-2 の値にすることを指す（D27）。子タブ「新規チャット」は作らない。**送信先が決まっていれば、そのプロジェクトを選んだまま**、そのプロジェクトの子タブの場所に新規チャット画面を重ねて出す（2026-10-13 ユーザー指示。上段のタブ・サイドバーの行は選択中、子タブはどれも選択しない、インスペクタにはそのプロジェクトのファイル、⌘T・⌘P も使える）。タブが 1 つも無いプロジェクトを選んだときも同じ（D21）。子タブ・別のプロジェクト・セッションを選んだら新規チャット画面を離れる。送信先が決まらない（未選択でプロジェクトが複数）ときだけ、どのプロジェクトも選ばない新規チャット画面を出す（ADR 0188。⌘T・⌘P は押せず、インスペクタのファイル欄は空）。⌘W は選択中（どのプロジェクトも選ばない画面では送信先）のプロジェクトで前に出していたタブへ戻り、戻り先が無ければウィンドウを閉じる。前/次のプロジェクト（⇧⌘[ / ⇧⌘]）は選択中のプロジェクトから数え、どのプロジェクトも選ばない新規チャット画面では送信先から数える。
- **FR-2** プロジェクトの初期値は、プロジェクト行から開いたときはそのプロジェクト。それ以外は、選択中のプロジェクト → 直前に選択していたセッションのプロジェクト → プロジェクトが 1 つならそれ → 無ければ未選択。今の `newSessionTableProjectID`（`DashboardView.swift:942-946`）と同じ順。
- **FR-2a** プロジェクトが未選択のときも新規チャット画面を出す（今の `SelectProjectPlaceholderView` を置き換える）。入力欄のプロジェクト選択が空で、選ぶまで送信できない。
- **FR-3** プロジェクトが 1 つも無いときも、主画面には新規チャット画面を出す（2026-10-13 ユーザー指示で、フォルダの登録案内 `StartOnboardingView` を廃止）。サイドバーは今どおり「プロジェクトがありません」とフォルダの追加ボタンを出す。入力欄のプロジェクトのチップは、プロジェクトの一覧の最後に「フォルダを選ぶ…」を出す（0 件ならこれだけ）。フォルダを選ぶと送信先になるが、**プロジェクトは送信したときに初めて作る**（2026-10-13 ユーザー指示。選んだだけではサイドバーに出ない）。すでにプロジェクトになっているフォルダを選んだら、そのプロジェクトを送信先にする。
- **FR-4** 新規チャット画面を出したら入力欄にフォーカスを置く。

### 6.2 下書き

- **FR-5** 下書きは**アプリに 1 つ**（D27）で、メモリにだけ持つ。保存も復元もしない。下書きだけではサイドバーに行を出さない。`AppRouter` は全ウィンドウで共有されている（`PhloxApp.swift:102` の `WindowGroup` がどのウィンドウにも同じ `composition.router` を渡す）ので、下書きも全ウィンドウで共有になる。
- **FR-6** 別のセッションや別のプロジェクトを選んでから戻ったとき、送っていない本文・添付・作業場所・ハーネス・モデル等の選択は残っている。入力欄でプロジェクトを選び直したときや、別プロジェクトの ＋ を押したときは、送信先だけが替わり、本文・添付・設定は残る。
- **FR-6a** 送信先のプロジェクトを削除したら、送信先を空にする（送信できない）。本文・添付は残す。

### 6.3 送信

- **FR-7** 送信すると次の順に処理する（D8）。
  1. 送信時点の本文・添付・プロジェクト・作業場所・ハーネス・モデル・effort・権限（mode）を確定し、下書きを空にする。送信直前にプロジェクトがまだ存在するか確かめ、無ければ送らずに下書きを戻す。
  2. セッションの行を「起動中」としてサイドバーに出して選択する。「既存ディレクトリ」ではほぼ即時。「新しい worktree」では worktree の作成（数秒）が終わってから行が出て、その間はトーストを出す（設計書 §5.1）。初回メッセージはこのセッションが預かり、会話欄に「送信待ち」として表示する（E5）。
  3. 起動する。作業場所が「新しい worktree」なら `isolationOverride: true`、「既存ディレクトリ」なら `false` を渡す。
  4. **起動の成功を確かめてから**、預かった本文と添付を既存の送信経路で初回メッセージとして送る。成功とみなすのは、Claude はプロセスが起動して失敗の通知が無いこと（今の `ClaudeChatClient.start()` :282 は失敗を通知するだけで正常に戻る）、Codex は開始と設定の適用（モデル・effort・権限）が両方成功したこと（今は適用失敗を通知するだけ。`ChatSessionViewModel.swift:943,962`）、Cursor は会話 ID が取れたこと。
- **FR-8** モデル・effort・権限は**起動時の値として**渡す。ハーネスごとの当て方は今の経路をそのまま使う（Claude は起動引数、Codex は開始後の `updateThreadSettings`、Cursor はターンごとの引数）。そのため `spawnNewSession` にこれらの引数を足す（今は GUI 経路に無く、`startNew` が「最後に使った設定」を当て直すだけ）。Codex の model は `ThreadStartParams.model` で開始時に渡す（U2 で効くと確認済み）。
- **FR-9** 送信したハーネスを `phlox.newChat.lastHarness` に、モデル等を `phlox.lastUsedChatSettings.<agentID>.*`（権限・mode を足したもの）に書く。
- **FR-10** 失敗したときは、本文を失わず、セッションも二重にしない（D7）。
  - **起動の失敗**（CLI の起動失敗・Codex の設定適用失敗）: セッションの行を残して失敗を表示し、預かった本文を入力欄に戻す。ユーザーは「再起動」するか、セッションを閉じる（閉じると今の後始末で worktree も片付く）。
  - **再起動**（D20）: 失敗した行を閉じ、同じハーネス・モデル・effort・権限（mode）・作業場所で新しいセッションを起動して選択する。そのとき入力欄にある本文と添付（ユーザーが直した後のもの）を新しいセッションの入力欄へ移す。**送信はしない**。送るのはユーザー。
  - **worktree 作成の失敗・Codex の app-server 起動の失敗**（どちらも行が出る前）: 今のダイアログ（worktree は `.worktreeFailed` の「隔離なしで起動 / 既存の worktree を使う / 閉じる」、Codex は `spawnError`）を出し、本文をそのプロジェクトの下書きに戻す。
  - **起動後の初回送信の失敗**（設計書 §5.4）: セッションを残し、本文と添付をそのセッションの入力欄に戻す。
    - 送る前に断られたとき（添付の合計サイズ超過・画像に非対応など）は、そのセッションからそのまま再送できる。
    - 最初のターンが応答を 1 つも返さずにエラーで終わったとき・プロセスが終了したとき（Cursor のターン失敗・未ログインなど）は、**起動の失敗として扱う**。送れない状態になり、上の「再起動」か「閉じる」を選ぶ。再起動すると、直した本文と添付が新しいセッションの入力欄に入る（2026-10-13 ユーザー決定: 実装を正とする）。
- **FR-11** worktree の作成中は今のトースト（`worktreeProgressToast`）を出す。
- **FR-12** 同じフォルダで別のセッションが動いていても確認を出さずに起動する（D3）。

### 6.4 履歴から再開

- **FR-13** 新規チャット画面に「履歴から再開…」を出す。選択中のハーネスが Claude Code か Codex で、そのプロジェクトに履歴があるときだけ出す（今の `shouldOfferHistoryStart` と同じ条件）。出さないときも場所の高さは保ち、画面がずれないようにする。一覧の行には「今の作業場所で再開します」と分かる文言を出す（worktree で進めた会話でも元の worktree には戻らないため）。
- **FR-13a** 一覧の範囲は、本体フォルダの会話に加えて、そのプロジェクトで過去に worktree で進めた会話を含める（D10）。今の一覧は作業フォルダが一致する会話だけを出す（`ClaudeSessionHistory.swift:72`、`CodexSessionHistory.swift:44`）。worktree の会話は作業フォルダが `<AppSupport>/workspace/<SessionUUID>` なので、worktree を作るたびに「その場所 → プロジェクト」の対応を記録し、一覧はその記録を使って集める（記録の置き場所は U6）。元の worktree が消えていても一覧には出す。
- **FR-13b** 一覧は「読み込み中」「履歴がありません」「履歴を読み込めませんでした」＋「再試行」を区別して出す。
- **FR-14** 押すと履歴一覧（`ChatHistoryStartView` の一覧部分）を出す。選ぶと、そのハーネスでセッションを作ってその会話を再開する。作業場所は新規チャット画面の選択に従う（worktree の会話を選んでも、元の worktree には戻らない）。再開後のモデル・effort・権限は新規チャット画面の選択を当てる。Codex の今の再開経路は履歴 ID しか渡さない（`ChatSessionViewModel.swift:658`、`CodexAppServerClient.swift:539`）ので、作業場所も渡す（渡せばその場所で動くことを U7 で確認済み）。

### 6.5 worktree 設定の廃止（D2）

- **FR-15** プロジェクト単位の「git worktree で隔離する」を 3 か所（サイドバーのプロジェクトメニュー、ツールバーの `WorktreeMenuButton`、メニューバー）から消す。
- **FR-16** worktree で分けたかどうかは、**保存済みの作業フォルダが、そのセッションの worktree の場所（`<AppSupport>/workspace/<SessionUUID>`）と一致するか**で決める。新しい保存項目は足さない。新規は送信時の選択で決める。復元は今の「隔離オフ後の復元」の判定（`SessionSpawnService.swift:969-985`: 保存済みの作業フォルダが worktree の場所と一致し、登録済みの worktree であることを確かめる）を、プロジェクト設定に関係なく常に使う。worktree が消えていたら今の作り直し確認（`WorktreeRecreationDialog`）を出す。`WorktreeIsolationPlanner.swift:72` がプロジェクト設定を読む所と、`SessionSpawnService.swift:544` のプロジェクトのコピーへの書き込みは無くす。
- **FR-17** 旧データの移行: FR-16 の判定は作業フォルダという事実だけを見るので、「この起動だけ worktree」で始めたセッションや、隔離した後でプロジェクト設定をオフにしたセッションも同じく拾える。旧設定の 2 項目（`Project.worktreeIsolationEnabled`・`worktreeIsolationOptOut`）は読まず、書かない（書いている `DashboardViewModel.swift:1098,1440`・`SessionPersistenceCoordinator.swift:243` を止める）。読み込みで壊れないよう、項目の定義（読み捨て）は残す。旧版へ戻したときの作業場所は保証しない（E1）。保存済みの作業フォルダは必須項目で、隔離したセッションでは worktree の場所が保存されている（U8 で確認済み）。
- **FR-17a** worktree で動いているチャットは別プロジェクトへ移動できない今の制限（`DashboardSidebarView.swift:547-548`、`canMoveSession`）を残す。そのため、移動したチャットの worktree の扱いは生じない。
- **FR-18** Control API（`POST /sessions`）・CLI `spawn`・子セッションの起動は、常に既存ディレクトリで起動する（今は隔離オンのプロジェクトでは worktree になる。iOS からの `POST /sessions` も同じ。§9 の挙動変化）。

### 6.6 ターミナルのセッション（D1・D22）

- **FR-19** 画面（メニューバー・プロジェクト行の右クリックと「⋯」・新規チャット画面）には、ターミナルでエージェントを動かすセッションを始める項目を置かない。今それを始めている GUI の経路（新規セッションの表の「ターミナル」、起動カードのターミナル、`DashboardView.createSession` の `.pty` 分岐）はすべて消す。
- **FR-20** 残すもの: 保存済みのターミナルのセッションの復元（`SessionRestoreCoordinator.swift:154`）、Control API `POST /sessions` と CLI `phlox spawn` の `backend: pty`（組込ハーネスのみ。他のエージェントからの委譲で使う）、ユーザーが自分でコマンドを打つ普通のターミナル。
- **FR-21** 設定「新規セッションの既定の開き方」と保存キー `phlox.defaultSessionBackend` を廃止する（チャット/ターミナルを入口で分けたので選ぶ場面が無い）。

### 6.7 略号・図形の廃止（D14〜D16。アプリ全体）

- **FR-22** ハーネスの略号（`tabInitials` の Cl・Cx・Cu、カスタムは表示名の先頭 2 文字）を、どの画面にも出さない。今出している場所: セッションのタブ、子タブの会話タブ・新しいタブの選択、グリッドの見出し、対応待ち一覧、会話のアバター、閉じる確認の文言（「Cx · 実行中」）、使用量のバー（独自の Cl/Cx/Cu 表記）。どのハーネスかは、ホバーカード・インスペクタ・ハーネス・モデルのチップなど文字で示す所で分かればよい。
- **FR-23** 状態や種類を表す図形（`StateGlyph` の◆・回転・○・✓・!・六角形など、`AgentInitialTile`、ハーネスの色の四角や点、グリッドの実行中の輪）を出さない。今出している場所: サイドバーのプロジェクト行と折りたたみ時の要約、対応待ち一覧の行頭、ツールバーの「対応待ち」、グリッドの本文、新規チャットのハーネス・モデルのチップ。
- **FR-24** 状態は文字で示す。サイドバーのセッション行の右端に「実行中」「承認待ち」「質問あり」「エラー」「無応答」「完了」のいずれかを出す。待機中は何も出さない（2026-10-13 ユーザー指示で経過時間をやめた）。注意が必要な状態（承認待ち・質問あり・エラー・無応答）は今の注意の色を文字に使う。プロジェクト行・折りたたみ時の要約は、図形の代わりに「承認待ち 1」のような文字と件数にする。タブ・子タブ・グリッドの見出しには状態を出さない（D19）。
- **FR-25** 未読の丸（サイドバー 2 か所・グリッドの見出し・対応待ち一覧）をやめ、未読のセッションは題名を主文字色・やや太く、既読は副文字色にして見分ける（D15）。
- **FR-26** 使用量画面とハーネス・モデルのチップのロゴは、各社のロゴの SVG（ベクター）を使う。Claude と Codex は文字色の単色で描く（今の Codex と同じテンプレート描画。`AgentBrandIcon.swift:43`）。Cursor は元のロゴのまま描く。画像が無いときの略号・記号の代わりの表示はやめる（D16）。ロゴの利用条件（各社のブランドガイドライン）を実装前に確かめる。
- **FR-27** 図形・略号を消しても、読み上げの文言は今と同じに保つ（今の読み上げは文字ベースで、図形には依存していない）。

### 6.9 ヘッダーと使用量のバー（D24〜D26。アプリ全体）

- **FR-32** ヘッダー（`DashboardToolbar.swift:41-60`）から「対応待ち」ボタン（`AttentionButton` :51）と使用量のチップ（:52-54、`UsageTopBarView`）を消す。対応待ちの一覧（`AttentionListPopover`）と、メニュー「対応待ちの一覧」⌥⌘J（`App/PhloxApp.swift:962-977` のうち一覧の項目）、`AppRouter.attentionListPresented` を消す。「次の対応待ちへ」⌘J・サイドバーの対応待ちの欄・Dock のバッジ・サイドバーを隠したときの件数のバッジは残す。
- **FR-33** 単体／グリッドの切替（`ViewModeToggle` :49。今は 2 つの `Spacer` で中央）を右寄せにし、インスペクタの切替の左に置く。識別子 `view-mode-single`・`view-mode-grid` とショートカット ⌃⌘1・⌃⌘2 は変えない。左側のプロジェクト名と worktree のボタンも消え、ヘッダーの高さを必要最小に縮める（`project-tabs.md` P6・PE12）。
- **FR-34** ウィンドウの一番下に、サイドバーの下も含む全幅の使用量のバーを置く（`DashboardView.swift:353-487` の `navigationShell` の外側の末尾。単体・グリッドとも）。高さは 1 行、文字はメタの大きさ（11pt）・副文字色。
- **FR-35** バーにはハーネスごとに、ロゴ（D16 の色）と全部の枠の**残り**を横に並べる: Claude「5時間 72%・週次 40%」、Codex「5時間 99%・週次 85%」、Cursor「Auto 80%・API 95%」（枠の名前は今の `UsageBucket.label`）。幅に余裕があればリセットまでの時間（例「5時間 72%（2時間後）」）も出す。今の `UsageDisplay`（`remainingTimeText`・`sidebarResetDisplay`。`UsageDisplay.swift:156`）の整形を使う。
- **FR-36** 残りが少ない枠（今の基準 20% 未満。`UsageDisplay.swift:29`）は注意の色の文字にし、「残りわずか」を読み上げに含める。今の ▲ の印は使わない（D14）。取得できないハーネスは「取得できません」の文字（今の「—」はやめる）。表示するハーネスは今の「未取得の CLI も表示」の設定に従う。
- **FR-37** 狭いときは、リセットまでの時間 → 枠の名前の順に省き、数値は省かない。最小幅（720pt）でも全ハーネスの数値が 1 行に収まること。
- **FR-38** バーは押しても何も開かない（2026-10-13 にインスペクタの使用量タブを廃止。ADR 0192。それまでは押すとインスペクタの使用量を開いた）。インスペクタを開いていてもバーは出す（今のヘッダーのチップはインスペクタ表示中は消えていた。ADR 0112）。設定「ヘッダーに使用量を表示」（`phlox.usage.showInHeader`、`SettingsView.swift:477`）は「画面下部に使用量を表示」に改名し、キーはそのまま使う。
- **FR-39** バーは 1 つのまとまりとして読み上げ、値にすべての枠の残りを入れる（例「使用量。Claude 5時間 残り 72%、週次 残り 40%。…」）。インスペクタを重ねて表示するときの下端（`DashboardView.swift:416`）はバーの高さ分上げる。
- **FR-40** サイドバーの開閉ボタンをヘッダーの左に常に出す（D28）。隠しているときだけ対応待ちの件数の印を付ける（今どおり）。
- **FR-41** ヘッダーの開閉ボタンの右に、選択中のタブの名前を左寄せで出す（D31）。文字は子タブの列と同じもの（セッション名、ファイル名、「ターミナル」、「変更 N」など）。新規チャット画面では「新規チャット」。グリッド表示では出さない。長いときは末尾を省略する。

### 6.8 配色（D17・D18。アプリ全体）

役割ごとの色（D29。2026-10-13 に藍色から白黒へ改訂。ADR 0189）:

| トークン | 役割 | ライト | ダーク | 理由 |
|---|---|---|---|---|
| `accent`・`accentInk`・`focusRing` | 印・枠・アクセントの文字・フォーカス枠 | 主文字色（黒） | 主文字色（白） | 背景との比が最も高く、どのテーマでも 3:1・4.5:1 を満たす |
| `accentFill` | 主ボタン・送信ボタンの面 | 主文字色（黒） | 主文字色（白） | 同上 |
| `accentOnFill`（新規） | `accentFill` の上の文字・記号 | 背景色（白） | 背景色（黒） | 面と反転した色で 4.5:1 以上 |
| `selectionFill` | 選択中の行の面 | 無彩色の面 | 同左 | 色を足さない |
| `textSelection` | 文字選択 | 主文字色に今の不透明度 | 同左 | 同上 |

外部テーマ（Tokyo Night など）も、そのテーマの主文字色と背景色を使う。

- **FR-28** UI のアクセントは各テーマの主文字色（白黒）にする（D29。今のコーラル `AppTheme.claudeCoral` の役割を替える）。
- **FR-29** アクセントを使うのは、主要な操作（主ボタン・送信）・選択・フォーカス・リンクに限る。今アクセントを使っている箇所（2026-10-11 時点で `accent` 51・`accentFill` 23・`accentInk` 23・`chatAccent` 16 など）を実装時に役割で分け、どれにも当たらない装飾は中立の色（文字色・区切り線の色）に替える。
- **FR-30** ハーネスごとの色を廃止する（D18）。`AppTheme.agentColors`・`DSColor.agentColor(for:)`・`agentInitialFill`・`AgentDescriptor.colorRGB` を消す。ロゴの無いハーネスの代わりの印（`AgentBrandIcon` の `fallbackIcon`）はカスタムの廃止（D22）で不要になるので消す。
- **FR-31** 注意の色（承認待ち・質問あり・エラー・無応答）と差分の色は変えない。アプリアイコンは変えない。

## 7. 非機能要件

- **NFR-1** 下書きの間は、会話用の CLI プロセス（チャットのセッション）を起動しない。アプリが定期的に行うモデル一覧の取得（`CompositionRoot.swift:49,58`、`AgentModelProviders.swift:141`）は対象外で、今のまま動いてよい。
- **NFR-2** 主要な部品に `accessibilityIdentifier` を付ける（`newChat.composer`、`newChat.projectPicker`、`newChat.workspacePicker`、`newChat.harnessModelPicker`、`newChat.sendButton`、`newChat.suggestion.<n>`、`newChat.historyResume`）。
- **NFR-3** 文言は日本語と英語の両方を `macos/App/Localizable.xcstrings` に手で足す（`extractionState: manual`）。
- **NFR-4** キーボードだけで操作できる（⌘N → 入力 → ↩。チップとメニューは Tab で移れ、Space・↩ で開き、矢印で選び、Esc で閉じる）。
- **NFR-5** WCAG 2.2 AA を基準にする。文字と背景は 4.5:1 以上、部品とフォーカス枠は 3:1 以上（§6.8）。意味を色だけで伝えない。VoiceOver で各チップの役割と今の値が読める（例「ハーネスとモデル、Codex: gpt-6.1-sol」）。入力欄にはラベル「メッセージ」を付ける。起動中・起動完了・起動失敗に変わったら読み上げる（WCAG 4.1.3。既存の `AccessibilityNotification.Announcement` を使う。`ComposerSettingsControls.swift:1149`）。
- **NFR-6** ホバー・押下中・無効の見た目は既存のボタンスタイル（`DesignSystem/Interaction.swift:203,239,276` の `HoverableIconButtonStyle`・`HoverableSoftButtonStyle`・`HoverableSurfaceButtonStyle`）を使い、新しい値を足さない。フォーカスは `focusRing`（入力欄の枠と下段のチップは例外。§5.1）。
- **NFR-7** ウィンドウの最小幅（720pt。`App/PhloxApp.swift:120`）でサイドバーを出していても、入力欄の下段が切れたり重なったりせず、すべてのチップを操作できる（E6 のまとめ方で収める）。

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
| ツールバーの `WorktreeMenuButton` | ボタンごと消す。「プロジェクト名を変更…」は上段のタブの右クリックへ移す（E3、`project-tabs.md` P6。`DashboardToolbar.swift:379`） |
| プロジェクトの削除 | 送信先がそのプロジェクトなら送信先を空にする（FR-6a） |
| `StartAreaPolicy`・`DashboardDetailView` | セッション未選択の主画面を新規チャット画面にする |
| ⌘N・サイドバー・プロジェクト行・グリッド空状態 | 新規チャット画面を出す（FR-1） |
| メニュー | 「新規チャット」だけ（FR-19） |
| `.worktreeFailed` ダイアログ | 残す。呼び出し元を送信処理に付け替える |

### 8.3 新しく作る

- 新規チャット画面の View（見出し・入力欄・チップ・履歴から再開）と、下書きの状態（アプリに 1 つ。全ウィンドウで共有）。
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

### 8.5 略号・図形の廃止（§6.7）の範囲

パスは `macos/Packages/` からの相対。

| 対象 | 場所 |
|---|---|
| 消す部品 | `DesignSystem/StateGlyph.swift`（`StateGlyph`・`Triangle`・`Hexagon`・`AgentInitialTile`）、`AgentDescriptor.tabInitials`（`DesignSystem/Tokens.swift:385-396`）、`agentInitialFill`、使われていない `AgentSessionIcon.swift`・`SessionSidebarRowIconLayout`・`StatusBadge.iconName` |
| 略号を消す画面 | `SessionTabBar.swift:240`、`SessionTabsContainer.swift:255,298,433,459`、`GridTileParts.swift:153`、`AttentionListPopover.swift:271`、`ChatTranscriptView.swift:641-655`（会話のアバター。消すと字下げ `TranscriptAgentColumn.indent` も変わる）、`DashboardView.swift:91`、`UsageTopBarView.swift:70,141` |
| 図形を消す画面 | `SidebarRows.swift:227,552-600`、`AttentionListPopover.swift:27,270`、`GridTileParts.swift:382,427` |
| 未読の丸 | `SidebarRows.swift:568`、`DashboardSidebarView.swift:237`、`GridTileParts.swift:144`、`AttentionListPopover.swift:156` |
| 状態の文字を足す | サイドバーのセッション行（`SidebarRows.swift:209-247`） |
| ロゴ | `DesignSystem/AgentBrandIcon.swift`（SVG に替え、略号・記号の代わりの表示を消す）。使う所は `UsageBottomBarView.swift` |
| ハーネスの色（FR-30） | `AppTheme.agentColors`（`AppTheme.swift:81,229,247,269,295,455`）・`DSColor.agentColor(for:)`（`Tokens.swift:373-381`）・`agentInitialFill`・`AgentDescriptor.colorRGB`（`AgentDescriptor.swift:103` ほか、組込の 3 色 :174,192,209）と、それを渡している所（`SessionTreeSidebarSection.swift:16`、`SessionSpawnService.swift:832`、`ControllableSession.swift:162`、`ChatSessionView.swift:179`、`ChatTranscriptView.swift:388`）。iOS は同じ `AgentDomain` を使うので、iOS のテスト（`PhloxCoreTests.swift:320,336`）の作り方も直す（iOS アプリの動きは変わらない） |
| アクセント（§6.8） | `DesignPalette.swift:48,55,69`、`AppTheme.swift:95,221,250,400,415,430`、`Tokens.swift:296,298,301`、`ThemePreviewModel.swift:44`、設定画面の見本の直書き（`App/SettingsView.swift:748`）、コメントの値（`AccentSwitchToggleStyle.swift:4`） |
| ヘッダーと使用量（§6.9） | 消す: `AttentionListPopover.swift` 一式、`DashboardToolbar` の `AttentionButton`・`usageChip`（:162-185）、`UsageTopBarView.swift`、`UsageDisplay.topBarChips`、⌥⌘J の項目、`AppRouter.attentionListPresented`。足す: 使用量のバー（`DashboardView.navigationShell` の末尾）。変える: `ViewModeToggle` の位置、設定の文言。上の行の `AttentionListPopover`・`UsageTopBarView` の行番号は、ファイルごと消すので個別に直さなくてよい |
| テスト | `HeaderUsageWhiteboxTests`・`AcceptanceUsageRemainingSummaryTests`・`HeaderUsageVisibilityAcceptanceTests`・`UsageDisplayTests` の `topBarChips` 部分をバーの整形に書き換える。`DesignSnapshotRenderTests.swift:750`（ダッシュボード全体）を撮り直す。`AcceptanceSidebarTextContrastTests`（テーマの色の指紋に `agentColors` を含む）、`TokensTests.swift:86-88`、`SessionRowIconTests`、`DialogRedesignTests.swift:44-47`（「Cx · 実行中」）、`StatusBadgeTests.swift:53` |
| 資料 | `ui-feature-inventory.md:762`、`architecture/design-system.md:156` |

### 8.6 カスタムエージェントの廃止（D22・ADR 0185）

| 対象 | 扱い |
|---|---|
| 本番コード | `AgentDomain/CustomAgentDefinition.swift` を消す。`AgentRef` は `.builtin` だけにし（型は残す。`AgentKind` に畳むのは別作業）、未知の値の読み込みは失敗にする。`AgentCatalog` の合成・`customAgentBinaryPaths`・`AgentBinaryTable.custom`・`AgentSpawnError.customBinaryNotFound`・「（カスタム）」表示・設定画面の定義ファイルの行・Control API の custom 分岐（未知の kind は 400）を消す |
| 保存済みのデータ | カスタムのセッションは読み込みで捨てる（今の `JSONSessionStore` の `DiscardableSession` が個別に捨て、`sessions.json.corrupt-<日時>` を残す）。捨てたときはログに残す。捨てた件数が 1 以上なら起動後に 1 回だけ「カスタムエージェントのセッション N 件を読み込めませんでした（機能を廃止したため）」を出す |
| テスト | 削除: `CustomAgentJSONTests`・`CustomAgentRobustnessAcceptanceTests`・`CustomAgentLaunchPlannerTests`、iOS の `PhloxCoreTests` のカスタム部分。追加: カスタムの保存形式 2 種を読み込んでも落ちず、そのセッションだけ捨てるテスト |
| 偽エージェントで動く E2E・UI テスト | 今は課金なしで動かすためにカスタム（`fake-agent`）を使っている（`E2EControlServerTests`、`macos/UITests/*`、`SimulatorTabUITests`）。組込ハーネスの実行ファイルの場所を差し替えて `fake-agent.sh` を動かす形に移す（`E2EFakeAgentSmokeTests` は既にカスタムに依存しない） |
| 資料 | `specs/custom-agents-json.md` を `superseded`（→ ADR 0185）にし、索引から外す。他の資料の言及は実装時に直す |

## 9. 挙動の変化（利用者に見えるもの）

1. ＋ や ⌘N を押してもセッションはすぐできない。最初のメッセージを送った時点でできる。セッションを開いているときに ⌘N を押すと、そのセッションの選択が外れて新規チャット画面になる。送っていない下書きは、アプリを終了すると消える。
2. 同じフォルダで動いているセッションがあっても何も聞かれない。
3. 隔離オンにしていたプロジェクトでも、新規チャットは「既存ディレクトリ」から始まる。Control API・CLI・子セッションは常に既存ディレクトリで起動する。
4. 画面からターミナルのセッションは始められない。ターミナルでエージェントを使いたいときは、ターミナルに自分でコマンドを打つ（Phlox のセッションにはならない）。カスタムエージェントは使えなくなる。
5. 「既定の開き方」の設定が無くなる。
6. 送信するとすぐにサイドバーへ「起動中」の行ができ、起動が終わってから最初のメッセージが届く。失敗してもセッションは残り、本文はそのセッションの入力欄に戻る。
7. Claude の使用量表示は、動いているチャットが無く、保存済みの値も無いときは、最初のメッセージを送るまで出ない（`ClaudeChatUsageSource.swift:23`。今は起動カードからセッションを作った時点で問い合わせ先ができていた）。
8. アクセント色がコーラルから白黒（ダークは白、ライトは黒）に変わる（D29。一度は藍色 #3B469B にしたが改訂）。キーボードのフォーカス枠がはっきり見えるようになる。
9. ハーネスの略号・色・状態の図形・未読の丸が無くなる。状態はサイドバーのセッション行の右端の文字で見る。タブとグリッドには状態が出ない。
10. 起動に失敗して「再起動」しても、自動では送られない。

## 10. 先に直す資料（実装の前・2026-10-12 に実装と同時の項目も反映済み）

| 資料 | 対応 |
|---|---|
| ADR 0183 | 作成済み（2026-10-11） |
| ADR 0071（既定の開き方）・0082（起動カードとメニュー） | `superseded` にして 0183 へリンク済み。0086（単体表示の開始画面）は導線の決定が残るので active のまま、開始画面が置き換わる旨を追記済み |
| `architecture/dashboard-empty-state-agent-cards.md` | `superseded` にして ADR 0183・本ファイルへリンク済み（2026-10-12） |
| `specs/ui-feature-inventory.md` 第 10 章（:375-383）ほか :77・:564・:731 | 新規チャット画面の記述に書き直し済み（2026-10-12。第 9・10 章・§2・メニュー・§16.1・設定表ほか。それ以外の章は 2026-09-29 のまま） |
| `specs/e2e-test-design.md:73` の `session.newButton` | 実在する `tabs.item.add`・`newChat.composer`・`newChat.sendButton` に直し済み（2026-10-12） |
| `delivery/0037-ui-redesign-worklog.md` | 変えない（作業記録なので当時のまま）。新しい作業記録から参照する |
| `specs/README.md` | 本ファイルを索引に足す |
| ADR 0184（配色） | 作成済み（2026-10-11）。ADR 0042 に置き換えの追記済み |
| `architecture/design-system.md` | アクセントの値・テーマ数・ハーネスの色の廃止を反映済み（2026-10-12。§2.1〜2.5・§4・§7 は 2026-07-08 のまま未再検証） |

## 11. 受け入れ基準

客観的な判定は `.claude/verify.sh` が通ること（git 管理外なのでメインの checkout にある。worktree で作業するときはそこから実行する）。加えて次をテストで確かめる。

| # | 基準 | 確かめ方 |
|---|---|---|
| AC-1 | ⌘N・サイドバーの ＋・プロジェクト行の ＋・グリッド空状態のボタンを押すと、`router.selectedSession == nil`・`router.commonTerminalSelected == false`・単体表示・期待したプロジェクトが選択になり、セッション数が増えない。共通ターミナルを前面にした状態から押しても同じ | DashboardFeature の単体テスト（入口ごと） |
| AC-2 | 送信すると、選んだハーネス・モデル・effort・権限（mode）・作業場所でセッションが 1 つでき、初回メッセージが届く | fake の CLI を使う単体テスト（Claude: 起動引数の `--model` `--effort` `--permission-mode`、Codex: 開始または設定更新の model・effort・権限、Cursor: ターン引数の `--model` `--mode`） |
| AC-2a | 送信した瞬間に「起動中」の行が選択され、下書きが空になる。起動完了前は初回メッセージを送らない | 単体テスト（起動を止めた fake） |
| AC-3 | 「新しい worktree」で送ると worktree ができ、「既存ディレクトリ」ではできない | `WorktreeIsolationSpawnTests` に足す |
| AC-4 | 同じフォルダで動作中のセッションがあるとき、送信 1 回でセッションが 1 つ増える（途中で止まらない） | 単体テスト |
| AC-5 | 失敗の 3 種（Claude の起動失敗・Codex の設定適用失敗・起動後の初回送信失敗）で、セッションが 1 つだけ残り、本文と添付がそのセッションの入力欄に戻り、初回メッセージは送られていない（起動前の失敗）／重複して送られない（再送時） | fake を使う単体テスト（種類ごと） |
| AC-5d | worktree 作成の失敗で「閉じる」を選ぶと、セッションの行が消え、本文が下書きに戻る | 単体テスト |
| AC-5e | プロジェクト未選択で書いた本文が、入力欄でプロジェクトを選んでも残る。A を送信先にして書いた本文が、B の ＋ を押しても残り、送信先だけ B になる。新規チャット画面の間は子タブ「新規チャット」ができない | 単体テスト |
| AC-5f | 送信先のプロジェクトを削除すると送信先が空になって送信できず、本文は残る | 単体テスト |
| AC-5g | Cursor を選んで画像を添付していると送信できず、添付は残っている | 単体テスト |
| AC-5a | 下書きの間は会話用の CLI プロセスを起動しない（NFR-1。モデル一覧の取得は数えない） | fake の起動器で会話プロセスの起動回数 0 を確かめる単体テスト |
| AC-5b | Control API・子セッションの起動は、旧設定がオンのプロジェクトでも worktree を作らない（FR-18） | `WorktreeIsolationSpawnTests` に足す |
| AC-5c | 「履歴から再開」の一覧に、本体フォルダの会話と、そのプロジェクトの過去の worktree の会話（worktree が消えたものも）が出る。選ぶと、選んだハーネス・作業場所・モデルで再開する | 単体テスト（一覧と再開の引数） |
| AC-6 | 次の 3 つのセッションが、プロジェクト設定に関係なく復元で同じ worktree を使い、終了で後始末される: (a) 新版で worktree を選んで始めたもの、(b) 旧版で「この起動だけ worktree」で始めたもの、(c) 旧版で隔離オンで始め、後で設定をオフにしたもの。保存済みの作業フォルダが本体フォルダのセッションは worktree を使わない | `SessionRestoreCoordinator` のテスト、`AcceptanceRestoreAbortNoSpawnTests` を作業フォルダ基準に合わせる |
| AC-7 | ハーネス・モデル・effort・権限・mode の初期値が「最後に使った設定」になる。未検出のハーネスは選べない | 単体テスト |
| AC-8 | 提案チップで定型文が入り、送信はされない | 単体テスト |
| AC-9 | メニューバー・プロジェクト行のメニューに「新規ターミナルセッション」が無い。Control API の `backend: pty` では今どおりターミナルのセッションができる | 単体テスト（メニューの組み立て）＋既存の Control API のテスト |
| AC-9a | プロジェクトや作業場所を変えると `@ファイル` 候補が新しい場所のものになる | 単体テスト |
| AC-10 | 見た目が見本と揃っている | `DesignSnapshotRenderTests` に新規チャット画面を足して撮る（日本語・英語、ライト・ダーク）。合否は目視で、§5.1 の並び（見出し → 入力欄 → チップ → 履歴から再開、入力欄の下段の左右の並び）と一致すること。**機械判定ではない**ので、ユーザーに画像を見せて承認を得る |
| AC-11 | 主要な操作をキーボードだけで通せる | XCUITest 1 本（⌘N → 入力 → Tab でハーネス・モデルのチップへ → 開いて矢印で選ぶ → 作業場所も同様に選ぶ → ↩ → セッションができる）。fake-agent CLI を使う（`e2e-test-design.md`） |
| AC-12 | 略号（Cl・Cx・Cu）と状態・種類の図形が、どの画面にも描かれない | `DesignSnapshotRenderTests` で主要画面を撮って目視、加えて `StateGlyph`・`AgentInitialTile`・`tabInitials` が本番コードから無いことをビルドで確かめる |
| AC-13 | サイドバーのセッション行の右端に状態の文字が出る（待機中は何も出さない）。未読は題名の濃さで見分けられる | 単体テスト（状態 → 文字・色の対応） |
| AC-14 | 見出しは 10 種類から選ばれ、画面を出すたびに替わり、入力中は替わらない | 単体テスト（乱数を注入） |
| AC-15 | 起動に失敗した後、入力欄の本文を直して「再起動」すると、新しいセッションの入力欄に直した本文と添付が入り、何も送られていない | fake を使う単体テスト |
| AC-16 | 全テーマ・ライト／ダークで、`accentInk` が使う背景に対して 4.5:1 以上、`accent`・`focusRing` が 3:1 以上、`accentFill` の上の `accentOnFill` が 4.5:1 以上。文字色の既存の検査はそのまま（既定 2 テーマの 3 段目の文字色は 4.5:1 未満を 2026-09-24 にユーザーが許容済み。`DesignPaletteTests.swift:61`） | `DesignPaletteTests` に足す |
| AC-17 | 各チップと入力欄に役割と値の読み上げ文言があり、起動の状態が変わると読み上げを出す | 単体テスト（読み上げ文言の組み立て）＋ XCUITest で `accessibilityLabel`・`accessibilityValue` を確かめる |
| AC-18 | 履歴の一覧が読み込み中・空・失敗（再試行あり）を区別して出す | 単体テスト（読み込みを失敗させた fake） |
| AC-19 | ウィンドウ幅 720pt・サイドバー表示で、入力欄の下段が切れず重ならない。送信ボタンにフォーカスがあるとき、枠が面と見分けられる（枠と面がどちらもアクセント色のため） | `DesignSnapshotRenderTests` で 720pt と、フォーカスのある送信ボタン（ライト・ダーク）を撮って目視（ユーザー承認） |
| AC-21 | ヘッダーに対応待ちのボタンと使用量が無く、単体／グリッドの切替が右寄せ。⌥⌘J のメニューが無く、⌘J は動く | 単体テスト（メニューの組み立て）＋ `ViewModeAccessibilityTests` |
| AC-22 | 下部のバーに全ハーネスの全枠の残りが出る。少ない枠は注意の色、取得できないものは「取得できません」。720pt でも数値が省かれない | 単体テスト（整形と省き方）＋ `DesignSnapshotRenderTests`（1440pt・720pt、目視） |
| AC-20 | ハーネスごとの色とコーラルが本番コードに無い | ビルドで確かめる（`agentColors`・`colorRGB`・`agentInitialFill`・`claudeCoral` が無い）＋ `rg -i 'D97757|E08865|B4552F|F0A383|A94A28|0xD9, 0x77, 0x57|0xE0, 0x88, 0x65|0xB4, 0x55, 0x2F|0xF0, 0xA3, 0x83|0xA9, 0x4A, 0x28' macos/Packages macos/App --glob '!**/Tests/**'` が 0 件 |

### 書き換え・削除するテスト

- 削除: `StartScreenRedesignTests` の表・確認ダイアログ部分、`AcceptanceNewSessionMenuModelTests`、`AgentStartCardsTests`・`AgentStartCardModesTests`・`AcceptanceAgentStartCardsTests`・`AgentStartCardsRenderPNGTests`、`AcceptanceDefaultSessionBackendTests`・`DefaultSessionBackendPreferenceWhiteboxTests`、`WorktreeIsolationSpawnTests`・`DialogRedesignTests` の**確認ダイアログを扱うテストケースだけ**（ファイルは残し、AC-3・AC-5b をここに足す）。
- 書き換え（配色・ハーネスの色）: `AcceptanceSidebarTextContrastTests` の色の指紋から `agentColors` を外す。カスタムの廃止に伴うテストは §8.6。
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
- （旧 U4「下書きをウィンドウごとに置く」は誤りだったので取り下げた。`AppRouter` は全ウィンドウで共有されており、下書きも 1 つを全ウィンドウで共有する。FR-5）
- **仮定 A1**: セッションのタイトルは今どおり初回メッセージから付く。
- **仮定 A2**: （D1 の改訂で画面からターミナルのセッションを始めないので不要）。

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
