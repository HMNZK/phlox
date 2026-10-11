---
status: active
last-verified: 2026-10-11
---

# 共通の新規チャット開始画面（設計書）

> **このファイルの役割**: [unified-new-chat-start.md](unified-new-chat-start.md)（要件）を満たす実装の設計。
> どの型を足し・変え・消すか、データと処理の流れ、実装の順番。
> **書かないもの**: 何を満たすべきか（→ 要件書）、なぜこの方式か（→ [ADR 0183](../adr/0183-unified-new-chat-start-screen.md)）。実装後の構成は architecture/ へ移す。

パスは `macos/Packages/` からの相対。略称: `DF/` = `DashboardFeature/Sources/DashboardFeature/`、`SF/` = `SessionFeature/Sources/SessionFeature/`、
`DVM` = `DF/Dashboard/DashboardViewModel.swift`、`SSS` = `DF/Dashboard/SessionSpawnService.swift`、`CVM` = `SF/ChatSessionViewModel.swift`、`WIP` = `AgentDomain/Sources/AgentDomain/WorktreeIsolationPlanner.swift`。

## 1. 全体像

```
[入口: ⌘N / ＋ / プロジェクト行 / グリッド空状態]
        │ router.showNewChat(projectID:)
        ▼
[新規チャット画面 NewChatView]──参照──[NewChatDraftStore（プロジェクトごとの下書き）]
        │ 送信: NewChatLaunchRequest を作り、下書きを空にする
        ▼
DashboardViewModel.launchNewChat(request)
  1. spawnNewSessionImpl（worktree 作成 → VM 作成 → 行を出す → CLI 起動）
     └ 行が出た時点で router.selectedSession = id（呼び出し側）
  2. 起動の成否を判定（ChatLaunchError）
     ├ 成功 → vm.sendFirstMessage(text, attachments)
     └ 失敗 → 行を残して vm.markLaunchFailed(…)、本文を vm.draft へ
```

新しい型は 4 つだけ: `NewChatDraftStore` / `NewChatDraft`、`NewChatLaunchRequest`、`NewChatView`、`ChatLaunchError`。ほかは既存の型への引数・分岐の追加と削除。

## 2. 状態とデータ

### 2.1 下書き `NewChatDraftStore`（新規・`DF/NewChat/NewChatDraftStore.swift`）

```swift
@MainActor @Observable public final class NewChatDraftStore {
    private var drafts: [ProjectID?: NewChatDraft] = [:]   // nil = プロジェクト未選択の下書き
    public func draft(for projectID: ProjectID?) -> NewChatDraft   // 無ければ作る
    public func discard(_ projectID: ProjectID)                    // プロジェクト削除時
}

@MainActor @Observable public final class NewChatDraft {
    var text: String = ""
    let attachments = ComposerAttachmentStore()          // 既存（SF/ComposerAttachments.swift:47）
    var usesWorktree = false                             // 作業場所: false = 既存ディレクトリ
    var agentRef: AgentRef                               // ハーネス
    var settings: CodexAppServerSessionSettings          // model・effort・権限・isPlanMode（既存型。PersistedSessionDescriptor.swift:454）
}
```

- 持ち主は `CompositionRoot`（`AppRouter` と同じく 1 つを全ウィンドウで共有。`App/CompositionRoot.swift:472` の隣）。`DashboardView` に環境値で渡す。
- 入力欄の「プロジェクト」チップは `router.selectedProjectID` そのもの。選び直すと `draftStore.draft(for:)` の引数が変わり、そのプロジェクトの下書きに切り替わる（D9）。
- `agentRef`・`settings` の初期値（下書きを作るとき）: `phlox.newChat.lastHarness` と、そのハーネスの `LastUsedChatSettingsStore` の値。無ければ Claude Code と `AgentModelCatalog.defaultModel(for:)`。
- 設定値の型は新しく作らず `CodexAppServerSessionSettings` を使う。起動経路がすでにこの型で設定を運んでいる（`SSS:871-877`、`CursorModelListProvider.swift:6-14`）。Cursor の mode は今の流儀どおり `selectedPermissionProfile` に、Plan は `isPlanMode` に載せる。

### 2.2 起動要求 `NewChatLaunchRequest`（新規・値型）

```swift
struct NewChatLaunchRequest {
    let projectID: ProjectID
    let agentRef: AgentRef
    let settings: CodexAppServerSessionSettings
    let usesWorktree: Bool
    let text: String
    let attachments: [ComposerAttachment]     // 送信時点の複製
    let resumeHistoryID: String?              // 「履歴から再開」のとき（本文は空）
}
```

送信時点の入力一式をこの値に固定してから下書きを空にする（FR-7 の 1）。以後の編集は下書き側にしか効かない。

### 2.3 保存するもの

| 保存先 | 変更 |
|---|---|
| `UserDefaults` `phlox.newChat.lastHarness` | 新規。送信したハーネスの `AgentRef.id` |
| `LastUsedChatSettingsStore`（`DF/Environment/LastUsedChatSettingsStore.swift`） | `LastUsedChatSettings` に `permission: String?`・`isPlanMode: Bool?` を足し、キー `phlox.lastUsedChatSettings.<agentID>.permission` / `.planMode` を読み書きする。記録は今の `codexSettingsDidChange`（`SSS:744`）から |
| `projects.json` の `Project` | **任意項目** `worktreePaths: [String]?` を足す（履歴用。§6）。非 Optional にすると旧ファイルの読み込みが失敗し、プロジェクト一覧が空になる（`Project.swift:20-33` のコメント）ので必ず Optional |
| `Project.worktreeIsolationEnabled`・`PersistedSessionDescriptor.worktreeIsolationOptOut` | 定義は残して読み捨てにする（書かない・判断に使わない） |
| `phlox.defaultSessionBackend` | 使わなくなる（キーは消さず放置） |

## 3. 画面遷移

### 3.1 `AppRouter.showNewChat(projectID:)`（新規メソッド・`DF/Router/AppRouter.swift`）

```swift
func showNewChat(projectID: ProjectID?) {
    if let projectID { selectedProjectID = projectID }
    viewMode = .single                 // グリッドでは selectedSession を外しても画面が変わらないため
    selectedSession = nil
    commonTerminalSelected = false     // SessionTabsContainer は共通ターミナルを優先して出すため（:30-55）
    newChatFocusToken &+= 1            // 入力欄へのフォーカス要求（FR-4）
}
```

すべての入口がこれを呼ぶ。`newSessionTablePresented` は消す。

| 入口 | 変更 |
|---|---|
| ⌘N「新規チャット」（`App/PhloxApp.swift:692-699`） | `router?.showNewChat(projectID: nil)`。`.disabled(projects.isEmpty)` を外す（0 件なら `detailMainContent` が先にオンボーディングを出す。`DashboardDetailView.swift:47`） |
| サイドバー下端ボタン（`DashboardView.swift:695-725`） | 同上。ポップオーバー 2 つ（:172・:720）と `newSessionTableBinding` を消す |
| プロジェクト行の ＋（`SidebarRows.swift:83-89`、VoiceOver :119） | `showNewChat(projectID: project.id)`。`newSessionMenu`・`isNewSessionOpen` を消し、普通のボタンにする |
| プロジェクトメニュー「新規チャット」（`DashboardSidebarView.swift:512-515`） | 同上 |
| グリッド空状態（`DashboardView.swift:634`） | `NewSessionPopoverButton` を「新規チャット」ボタンに替え、`showNewChat(projectID: router.gridFilterProjectID)` |

### 3.2 主画面の分岐

- `StartAreaPolicy`（`DF/Dashboard/StartAreaPolicy.swift:5-21`）のケースを `sessionContent` / `newChat` の 2 つにする。`selectProjectPlaceholder` と `SelectProjectPlaceholderView` は消す（FR-2a。未選択でも新規チャット画面を出し、プロジェクト選択が空）。
- `DashboardDetailView.singleSelectEmptyState`（:128-150）は `NewChatView` を出す。`startHeader`（:115-125）と `isolates:`（:122）は消す。

## 4. 新規チャット画面 `NewChatView`（新規・`DF/NewChat/NewChatView.swift`）

### 4.1 構成

```
NewChatView(draft:, project:, …)
├ 見出し（NSFullUserName の最初の語。空なら NSUserName）
├ NewChatComposer
│  ├ IMESafeTextView（既存。VM 非依存。SF/ChatComposer.swift:578-）
│  ├ 添付の列（ComposerAttachmentStore を表示する既存の部品）
│  └ 下段: ＋ / プロジェクト / 作業場所 / ハーネス・モデル / effort・権限・mode チップ / 送信
├ 提案チップ 5 個（文言は要件 §5.5）
└ 履歴から再開…（§6）
```

### 4.2 入力欄の部品を共用するための切り出し

`ChatComposer` は `ChatSessionViewModel` に強く結合している（`SF/ChatComposer.swift:8-46`）。丸ごと共用はせず、VM に依存しない部品だけを使い、VM に直結している 3 つを値で動く形に変える。セッション画面の見た目と動きは変えない。

| 部品 | 扱い |
|---|---|
| `IMESafeTextView`・`ComposerAttachmentStore`・`ComposerKeyRouting`・`ComposerHeightPolicy`・`composerControls(for:)`・`composerModeOptions` | そのまま使う（VM 非依存） |
| `ComposerAttachPlaceholder`（`ComposerSettingsControls.swift:593`） | `viewModel.draft` を直接読み書きしている（:670-689）。`Binding<String>` と `ComposerAttachmentStore` を受け取る形に変え、セッション側は VM から渡す |
| 設定チップ（`ComposerSettingsControlsView` :95、`ComposerSettingsOverflowMenu` :716） | 見た目の部分を値で動く `ComposerSettingChip(title:options:selection:onSelect:)` に切り出す。セッション側は VM の値と `setSpawnAgentModel` 等を渡す薄い包みにする。新規チャット側は `NewChatDraft.settings` を渡す |
| `ComposerSuggestionController`（`ComposerSuggestions.swift:131`） | 作業フォルダがクロージャに閉じ、`@State` で 1 回だけ作られる（`ChatComposer.swift:20,45`）。新規チャット側は `.id(候補の基準フォルダ)` で作り直す（E4）。基準は「既存ディレクトリ」ならプロジェクトのフォルダ、「新しい worktree」でもプロジェクトのフォルダ（worktree はまだ無い。作られる中身は同じ HEAD） |
| slash 候補 | 静的リスト＋`~/.claude`・`<cwd>/.claude` の走査＋`availableCommandsStore` で、セッション無しでも出る（U1 は解消）。Codex の skill 候補は起動中の CLI が要るので下書きでは出さない |
| esc・⇧Tab・↑（履歴呼び出し） | 下書きでは esc は何もしない。⇧Tab の effort 切替は `NewChatDraft.settings` に対して同じ規則で行う。↑ は無効 |

### 4.3 ハーネス・モデル選択とその候補

- メニューは `AgentModelCatalog.models(for:)` を、チャット対応の組込ハーネスごとに区切って並べる。未検出（`availableAgentDescriptors` に無い）は区切りごと押せない。
- **Codex の候補を下書きで出すため**、`LiveAgentModelProvider.runCodexModelList`（`ControlServer/.../AgentModelProviders.swift:407-410`）が捨てている `supportedReasoningEfforts`・`defaultReasoningEffort`・`inputModalities` を、カタログの項目に持たせる（`AgentModelCatalog` の項目型に任意項目 `reasoningEfforts: [String]?`・`defaultReasoningEffort: String?`・`acceptsImages: Bool?` を足す）。これで effort の候補と画像の可否が下書きでも分かる。
- Codex の権限の候補は `permissionProfile/list` が要り、起動中の app-server が無いと取れない。下書きでは内蔵の 3 つ（`:danger-full-access`・`:workspace`・`:read-only`。`CVM:2660`）を出し、起動後は実際の一覧に替わる。要件 §5.4 の (2)「最後のセッションの候補」は使わない（要件を改訂する）。
- Claude の effort（`CVM:1588`）・権限・Cursor の mode（`composerModeOptions`）は今も静的なので、そのまま出す。
- ハーネスを替えたら `settings` をそのハーネスの「最後に使った設定」に入れ替える。

### 4.4 送信できる条件

`本文が空でない || 添付がある` かつ `プロジェクトが選択済み` かつ `ハーネスが検出済み` かつ `画像の添付が無い || 選んだハーネス・モデルが画像を受け付ける`。最後の条件で送れないときは「{ハーネス} は画像を送れません」を出す。添付は消さない。

## 5. 送信してからの流れ

### 5.1 `DashboardViewModel.launchNewChat(_:)`（新規）

```swift
func launchNewChat(_ r: NewChatLaunchRequest) async throws -> SessionID {
    let id = try await spawnNewSession(ref: r.agentRef, projectID: r.projectID, backend: .appServer,
                                       isolationOverride: r.usesWorktree,
                                       initialSettings: r.settings,          // 新しい引数（§5.2）
                                       keepsRowOnLaunchFailure: true,        // 新しい引数（§5.3）
                                       resumeHistoryID: r.resumeHistoryID)   // 新しい引数（§6）
    record(lastHarness: r.agentRef)
    guard r.resumeHistoryID == nil, let vm = chatSession(id), vm.launchFailure == nil else { return id }
    await vm.sendFirstMessage(r.text, attachments: r.attachments)          // 新しいメソッド（§5.4）
    return id
}
```

呼び出し側（`NewChatView` の送信処理。今の `DashboardView.createSession` の役割を引き継ぐ）:

1. `NewChatLaunchRequest` を作り、`router.selectedProjectID` の下書きを空にする。
2. `DashboardViewModel.$reportsWorktreeCreation.withValue(true) { … }` の中で `launchNewChat` を呼ぶ（worktree 作成中のトースト。今の `DashboardView.swift:1150` と同じ）。
3. 行が出たら選択する。今は `spawnNewSession` が戻ってから選択している（`DashboardView.swift:1160`）。行は `registerSessionForWrite`（`DVM:1387`）で出るので、そこから `onRowAppended(id)` を呼び、呼び出し側が `router.selectedSession = id` にする。
4. 例外（VM ができる前の失敗）は、本文を下書きに戻してダイアログを出す（§5.3 の表）。

**行が出る時点**: 行は worktree の作成が終わってから出る（`registerSessionForWrite` が worktree 作成の後にあるため）。「既存ディレクトリ」ではほぼ即時、「新しい worktree」では作成の数秒はトーストだけが出る。要件 FR-7 の 2「すぐに」はこの意味に改訂する。行を worktree 作成より前に出すには、`spawnNewSessionImpl` が外から決めた `SessionID` を受け取る仕組みと、仮の行を本物に差し替える仕組みが要り、VM の寿命が 2 つになるので採らない。

### 5.2 設定を起動時に当てる

| ハーネス | 今 | 変更 |
|---|---|---|
| 共通 | `startAppServerSession` が `lastUsedChatSettings` から `persistedSettings` を作る（`SSS:871-877`） | `initialSettings: CodexAppServerSessionSettings?` を `spawnNewSession`（`DVM:1205`）→ `spawnNewSessionImpl`（:1228）→ `startAppServerSession` 呼び出し（:1369）→ `SSS:838` へ通し、非 nil ならそれを使う |
| Claude | 権限は bypass 設定から `"bypassPermissions"` か `"auto"` に固定され、保存した権限は無視される（`SSS:717-719`、`CVM:1746`） | `initialSettings.selectedPermissionProfile` があれば `spawnAgentPermissionOverride` に入れる。model・effort は今の `applySpawnAgentSettings` → 起動引数の経路（`CVM:1783`） |
| Codex | `threadStart` に model を渡さず、開始後の `reapplyPersistedSettings`（`CVM:2685`）で当てる。失敗は通知だけ（:962） | model は `ThreadStartParams.model` で開始時に渡す（U2 で効くと確認済み）。`thread/start` は effort を受け取らない（引数に無い）ので、effort・権限は今の `updateThreadSettings` の経路で当て、**`initialSettings` があるときは適用失敗を `ChatLaunchError.settingsNotApplied` として投げる** |
| Cursor | ターンごとの `--model` `--mode` | 変えない（`initialSettings` が `persistedSettings` に入れば効く） |

### 5.3 起動の成否と失敗の扱い

`ChatLaunchError`（新規 enum）: `.processFailed(String)`・`.settingsNotApplied(String)`。

| 失敗 | 今 | 変更 |
|---|---|---|
| worktree 作成の失敗（VM ができる前） | `.worktreeFailed` ダイアログ | そのまま。「閉じる」で本文を下書きに戻す（行はまだ無い） |
| Codex の app-server 起動の失敗（`AppEnvironment.swift:250-251`。VM ができる前） | `spawnError` ダイアログ | そのまま。本文を下書きに戻す |
| Claude の起動失敗 | `ClaudeChatClient.start()`（:282-292）は `.error` イベントを出して正常に戻る。直後に `startNew` が無条件に `status = .idle` を書く（`CVM:943-945`）ので、`.error` を上書きする疑いがある | プロトコルの要件 `StructuredAgentClient.start()`（`StructuredChatKit/StructuredChatTypes.swift:220`、今は `async` で投げない）を `async throws` に変え、`ClaudeChatClient.start()` は起動できなかったら投げる。投げない実装（Codex・Cursor・テスト用の偽物）はそのまま要件を満たすので、変えるのは呼び出し側の `try` だけ。`startNew` は投げられたら `ChatLaunchError.processFailed` にする |
| Codex の initialize・threadStart の失敗 | 投げる → 行を消す（`SSS:886-891`） | `keepsRowOnLaunchFailure` のときは行を消さない（下） |
| Codex の設定適用の失敗 | 通知だけ | §5.2 のとおり投げる |
| 起動後の初回送信の失敗 | §5.4 | §5.4 |

`keepsRowOnLaunchFailure == true` のとき、`startAppServerSession` の catch（`SSS:886-891`）は `unregisterFailedSession`・`cleanupOwnedWorkspace` を呼ばず、`vm.markLaunchFailed(error, restoringDraft: text)` を呼んで正常に戻る。`markLaunchFailed` は復元失敗の先例（`makeRestoreErrorChatSession` `SSS:803`、`markRestoreFailed` `CVM:1065`）と同じく `status = .error` とエラー行を出し、`draft` に本文、`attachmentStore` に添付を戻し、`launchFailure` に原因を持つ。行には「再起動」と「閉じる」を出す。

- **再起動**: 失敗した行を閉じ（`removeSession`）、同じ `NewChatLaunchRequest` から本文を除いたもので新しいセッションを起動し、本文と添付を新しい行の入力欄に入れる（自動では送らない）。同じ VM で `startNew` をやり直す形は採らない。VM の `client` は `let`（`CVM:225`）で、Codex は app-server のプロセスを client を作るとき（`AppEnvironment.swift:250-251`）に起動するため、プロセスが落ちた後は同じ client で起動し直せない（U10）。ハーネスで分けずに 1 つのやり方にする。
- **閉じる**: 今の `removeSession`（`DVM:1618`）。永続化前の行でも使える。worktree は今の後始末で片付く。
- 失敗した行は永続化しない（今も起動成功後にだけ永続化。`DVM:1441`）。アプリを終了すると消え、作った worktree は残る（今と同じ既知の穴）。

GUI 以外（Control API・子セッション）は `keepsRowOnLaunchFailure == false` で今のまま。

### 5.4 初回メッセージ `CVM.sendFirstMessage(_:attachments:)`（新規）

- 預かった添付を `attachmentStore` に入れてから、今の `sendText(_:submit:)`（`CVM:3573`）を呼ぶ。タイトル付け（`adoptTitleFromOriginalUserText` :3655）は今のまま。
- `sendText` の黙って戻る経路（合計サイズ超過 :3605-3609、`imagesUnsupported` :3615-3619、Codex skill の再選択 :3593-3600）を、型つきの例外 `SendRejected` を投げる形に変える。どれも今は本文を `draft` に戻してから戻るので、本文は失われない。呼び出し側は `try` しているので影響は小さい。
- 非同期のエラー（Cursor のターン失敗 `CursorChatClient.swift:171-193`、Claude の `preApprovalDenial` :338）は、ハーネスを問わず次の規則にする: **会話の最初のターンが、応答を 1 つも返さずに `.error` で終わったら、送った本文を `draft` に戻す**（`CVM:2252` のイベント処理で判定）。
- Claude の `turnStart` は `transport == nil` なら起動し直す（`ClaudeChatClient.swift:318-325`）。初回送信はこれに頼らず、§5.3 で起動の成功を確かめてから送る。

## 6. 履歴から再開

- 一覧の読み込み: `ClaudeSessionHistoryDiscovery` / `CodexSessionHistoryDiscovery` は VM に依存しない値型（U3 は解消）。`AppEnvironment` の provider 生成（`AppEnvironment.swift:191-231`、作業フォルダ 1 つが前提）に、作業フォルダの配列を取る版を足し、結果をまとめて更新日時の新しい順に並べる（最大 20 件）。
- 対象の作業フォルダ: `[project.directoryPath] + (project.worktreePaths ?? [])`（D10）。`worktreePaths` には、worktree を作るたびに（`SSS:598` の `finishSessionLaunch` で登録するとき）その場所を足して `persistProjects()` する。worktree を消しても残す。Claude は `~/.claude/projects/`、Codex は state の SQLite か rollout に会話が残るので、worktree が消えていても一覧に出せる。
- 表示条件: 選択中のハーネスが Claude か Codex で、一覧が空でないとき。一覧の UI は `ChatHistoryStartView` の一覧部分を切り出して使う。
- 再開: `NewChatLaunchRequest.resumeHistoryID` を付けて `launchNewChat`。起動後に今の `startFromHistory`（`CVM:~675`）相当を呼ぶ。
  - Codex: 今の履歴再開は `ThreadResumeParams(threadId:)` だけを送る（`CodexAppServerClient.swift:539-540`）。`ThreadResumeParams` は `cwd`・`model` を持つ（`AppServerRequests.swift:63-75`）ので、`StructuredAgentClient.resume(sessionRef:)`（`StructuredChatTypes.swift:222`）に作業フォルダと設定を渡す引数を足す。`cwd` を渡すと、その場所で会話の続きが動く（U7 で確認済み。元のフォルダが消えていても動く）。
  - Claude: 今の `--resume` のままでよい。別のフォルダから再開しても会話の中身は引き継がれ、再開したフォルダで動く（U9 で確認済み。元のフォルダが消えていても動く）。続きの記録は元のフォルダ用の場所（`~/.claude/projects/<元のフォルダ>/`）に書かれ続けるので、一覧は §6 の作業フォルダの集合で引けば出る。

## 7. worktree の判断の作り直し

### 7.1 規則

```
新規:  worktree を使う ⇔ isolationOverride == true          （nil と false は使わない）
復元:  worktree を使う ⇔ 保存済みの作業フォルダ == そのセッションの worktree の場所
```

- `isolationOverride` が `nil` のとき使わないので、Control API・CLI・子セッション（`DVM:1510`、`SSS:919`）は呼び出しを変えなくても既存ディレクトリで動く（FR-18）。
- 保存済みの作業フォルダは常にある（`PersistedSessionDescriptor.workingDirectory` は必須項目。隔離したセッションでは worktree の場所が保存される。`DVM:1415-1440`、`SSS:598`）。U8 は「欠けたデータは無い」で解消。

### 7.2 変更点

| 場所 | 変更 |
|---|---|
| `WIP:72` | `project.usesWorktreeIsolation` を見る `guard` を消す。`plan` は「worktree を使う」と決まってから呼ばれる |
| `SSS:543-545` | プロジェクトのコピーへの書き込みを消し、`isolationOverride` を真偽値として `prepareWorktreeIsolation` に渡す |
| `SSS:969-995`（フラグがオフのときの復元の分岐） | 消す。保存済みの作業フォルダが worktree の場所と一致したら、今の隔離オンの経路（`inspect` → `plan(.restore)` → `applyWorktreeIsolationOutcome`）を通す。worktree が消えていれば `.recreate` で `WorktreeRecreationDialog` が出る。今の分岐は消えていると黙って本体のフォルダで起動するので、FR-16 と逆になる |
| `SessionRestoreCoordinator.swift:157,248` | `isolationOverride` を渡すのをやめる（判断は作業フォルダで行う） |
| `DVM:1098`（`setWorktreeIsolationEnabled`）、`DVM:1440`、`SessionPersistenceCoordinator.swift:243` | 書き込みを消す |
| `NewSessionCollisionGate.peers`（`StartScreenViews.swift:484`） | 消す（確認ダイアログの廃止） |
| UI の切替 4 か所 | `DashboardSidebarView.swift:518-521`、`DashboardToolbar.swift:134-159`（「プロジェクト名を変更…」:444 は残す）、`App/PhloxApp.swift:1051-1080`、`DashboardDetailView.swift:122` |

worktree のチャットを別プロジェクトへ動かせない制限（`canMoveSession` `DVM:1562`）は、復元で `ownedWorkspaceDirectories` に登録し直されることが前提で、新しい規則でも保たれる。

### 7.3 実装の前提（ユーザーの承認が要る）

凍結された受け入れテスト `AcceptanceRestoreAbortNoSpawnTests` の 1 つ目（「共有ディレクトリでエージェントを起動しない」）は、「プロジェクト設定オン・保存済みの作業フォルダは本体のフォルダ・worktree の場所に未登録のフォルダ」で中止を期待している。新しい規則では作業フォルダが本体なので worktree を使わず、本体のフォルダで起動する。テストの意図（「隔離するはずのセッションを共有フォルダで起動しない」）は、「保存済みの作業フォルダが worktree の場所・その場所が未登録のフォルダで埋まっている」に置き換えれば保てる。**凍結テストの書き換えはユーザーが承認済み（2026-10-11）。** 2 つ目は `worktreeIsolationEnabled:` 引数を消すだけで成り立つ。

ほかにプロジェクト設定を使うテスト（`WorktreeIsolationSpawnTests` 21 か所、`AcceptanceWorktreeIsolationTests` 20 か所、`WorktreeIsolationPlannerWhiteboxTests`、`StartScreenRedesignTests`、`UITests/IsolatedLaunchOptionsTests`）は、設定オンを `isolationOverride: true`（新規）か「作業フォルダが worktree の場所」（復元）に置き換える。検証している中身は変えない。

### 7.4 対象外の既知の穴

ターミナルのセッションを `changeWorkspace`・`moveSession` で別フォルダへ移すと、作業フォルダが worktree でなくなり、復元で worktree が使われず残る（`DVM:1611`）。今もある穴で、本件では直さない。

## 8. ターミナルのセッション

- `AppRouter` に依頼 `terminalLaunchRequest: (AgentRef, ProjectID)?` を足す（`tabRequest`・`sidebarRequest` と同じ流儀）。`DashboardView` が `.onChange` で受けて `spawnNewSession(ref:projectID:backend: .pty)` を呼び、成功したら選択、失敗は今の `spawnError` ダイアログで出す。ダイアログはウィンドウごとの `DashboardView` にあるので、メニューからは依頼だけを出す。
- メニュー「ファイル ▸ 新規ターミナルセッション ▸」（`App/PhloxApp.swift` の `FileCommands`）: `dashboard.availableAgentDescriptors`（`DVM:472`、public。カスタムを含む検出済み）で項目を作る。対象は `router.selectedProjectID ?? (projects.count == 1 ? projects[0].id : nil)`。nil なら押せない（E2）。今の `defaultProjectIDForNewSession()`（`DashboardView.swift:1094-1104`。先頭のプロジェクトへ進む）は使わない。
- プロジェクト行の右クリック・「⋯」（`DashboardSidebarView.swift:510-526`）にも同じサブメニュー。対象はそのプロジェクト。

## 9. 消すもの

| 対象 | 場所 |
|---|---|
| 新規セッションの表 | `NewSessionTable`・`NewSessionTableRow`・`NewSessionPopoverButton`・`NewSessionKeys`（`StartScreenViews.swift:204-460`）、`NewSessionMenuModel.swift`、`AppRouter.newSessionTablePresented`、`DashboardView` の `newSessionTable(projectID:)`・`newSessionTableBinding`・`newSessionTableProjectID`・ポップオーバー 2 つ |
| 確認ダイアログ | `SpawnGuard.collision`・`SpawnGuardSheet` の確認部分・`NewSessionCollisionGate.peers`・`createSession` の確認分岐。`worktreeFailureLog`・`existingWorktree` は残す |
| 起動カード | `AgentStartCards.swift` 一式・`AgentStartProjectHeader`・`AgentStartCardSelection`・`agentStartEntries`（他に使う所が無ければ） |
| プレースホルダ | `SelectProjectPlaceholderView`・`StartAreaPolicy.selectProjectPlaceholder` |
| 既定の開き方 | `DefaultSessionBackendPreference`・設定画面の分節ボタン（`App/SettingsView.swift:37,54,158-165`）・`spawnNewSessionUsingDefaultProject`（`DVM:525`） |
| 使われていない起動関数 | `spawnNewClaudeCodeSession`（`DVM:1522`） |
| `DashboardView` の状態 | `isCreating`・`creatingRef`・`spawnGuard` の衝突ケース（`createSession` は新規チャットの送信処理と §8 の依頼処理に分かれる） |
| 文言 | 確認ダイアログの 4 キー・未使用の 1 キー（要件 §8.1）、表・起動カード・既定の開き方の文言 |

## 10. 文言（`App/Localizable.xcstrings` に日本語キー＋英訳を手で足す）

見出し「%@さん、さあ始めましょう！」/ "Welcome back, %@"、「やりたいことを入力（/ でコマンド）」、「既存ディレクトリ」、「新しい worktree」、「git リポジトリではないため worktree を作れません」、「新規チャット」、「新規ターミナルセッション」、「履歴から再開…」、「%@ は画像を送れません」、「起動できませんでした」、「再起動」、提案チップ 5 個と定型文 5 つ。メニュー（`.commands`）はアプリ内の言語切替がその場で効かない既知の制約がある（`docs/specs/localization.md`）。

## 11. 実装の順番

| 段 | 内容 | 閉じる受け入れ基準 |
|---|---|---|
| 0 | 済み: ADR 0183・§7.3 の凍結テストの書き換えの承認・§12 の確認 | — |
| 1 | worktree の判断の作り直し（§7）と、それに伴うテストの置き換え | AC-3・AC-5b・AC-6 |
| 2 | 起動の配管: `initialSettings`、`ChatLaunchError`、`keepsRowOnLaunchFailure`・`markLaunchFailed`・再起動（新しいセッションで起動し直す）、`StructuredAgentClient.start()` を投げる形に、`sendFirstMessage`・`SendRejected`・初回ターンの失敗で本文を戻す規則、`LastUsedChatSettings` の拡張、Codex のモデル候補の拡張 | AC-2・AC-5・AC-5a・AC-7 |
| 3 | `NewChatDraftStore`・`NewChatView`・入力欄の部品の切り出し・提案チップ | AC-2a・AC-5d〜5g・AC-8・AC-9a |
| 4 | 入口・`showNewChat`・メニュー・ターミナルのサブメニュー・§9 の削除・設定画面 | AC-1・AC-4・AC-9 |
| 5 | 履歴から再開（§6） | AC-5c |
| 6 | 画面外の描画（`DesignSnapshotRenderTests`）での見比べ、XCUITest 1 本、資料（要件 §10） | AC-10・AC-11 |

各段の終わりに `.claude/verify.sh`（メインの checkout にある）を通す。コードレビューは全段が終わってから 1 回まとめて行う（`AGENTS.md`「開発の進め方」）。

## 12. 確認した結果（2026-10-11）

実 CLI での確認は使い捨てのフォルダ 2 つ（git リポジトリ A・B）で行った。版は codex-cli 0.162.0、Claude Code 2.1.296。

| # | 内容 | 結果 | 根拠 |
|---|---|---|---|
| U1 | 下書きの間に「/」の候補を出せるか | 出せる（Codex の skill 候補だけ出せない） | コード（§4.2） |
| U2 | Codex の `thread/start` に `model` を渡すと効くか | **効く**。`thread/start` の応答の `model` が指定値（`gpt-6-luna`。既定は `gpt-6.1-sol`）になり、最初のターンの記録（rollout の `turn_context.model`）も `gpt-6-luna` だった。effort は `thread/start` の引数に無い | 実 CLI |
| U3 | 履歴の一覧を VM 無しで読めるか | 読める | コード（§6） |
| U5 | 下書きの間に Codex の effort・画像の可否を取れるか | 取れる。`model/list` が各モデルの `supportedReasoningEfforts`（例 `low`〜`ultra`）と `inputModalities`（`text`・`image`）を返した。権限の一覧は返さない | 実 CLI・コード（§4.3） |
| U7 | Codex の履歴再開で `cwd` を渡すと、その場所で動くか | **動く**。A で作った会話を、B で起動した app-server から `thread/resume`（`cwd: B`）すると、応答の `cwd` が B、`pwd` の実行結果も B で、記録は同じ会話の続きに追記された。A を消した後も再開でき、最初のターンの内容を答えた | 実 CLI |
| U8 | 隔離したセッションは作業フォルダを必ず保存しているか | している | コード（§7.1） |
| U9 | Claude で、別のフォルダから `--resume` できるか | **できる**。A で作った会話（`--session-id`）を B から `--resume` すると、A で覚えさせた語を答え、`pwd` は B だった。A を消した後も再開できた | 実 CLI |
| U10 | 起動に失敗した VM で `startNew` をやり直せるか | Codex はできない（`client` が `let`、プロセスは client を作るときに起動）。Claude は `transport == nil` なら `start()` が起動し直すのでできる。→ 再起動は新しいセッションで行う（§5.3） | コード |

確認に使ったフォルダと会話は検証用で、Phlox のデータには触れていない。
