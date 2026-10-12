---
status: active
last-verified: 2026-10-12
---

# 共通の新規チャット開始画面（設計書）

> **このファイルの役割**: [unified-new-chat-start.md](unified-new-chat-start.md)（要件）を満たす実装の設計。
> どの型を足し・変え・消すか、データと処理の流れ、実装の順番。
> **書かないもの**: 何を満たすべきか（→ 要件書）、なぜこの方式か（→ [ADR 0183](../adr/0183-unified-new-chat-start-screen.md)）。実装後の構成は architecture/ へ移す。
>
> **実装との突き合わせ（2026-10-12）**: 段 1〜7 の実装（コミット 07650a0e..b23855e2）のコードと、型名・ファイル名・流れを突き合わせて直した。直したのは名前と流れで、設計の判断は変えていない。実装と食い違う点は §5.3 の末尾と §9 の末尾に書いた。

パスは `macos/Packages/` からの相対。略称: `DF/` = `DashboardFeature/Sources/DashboardFeature/`、`SF/` = `SessionFeature/Sources/SessionFeature/`、
`DVM` = `DF/Dashboard/DashboardViewModel.swift`、`SSS` = `DF/Dashboard/SessionSpawnService.swift`、`CVM` = `SF/ChatSessionViewModel.swift`、`WIP` = `AgentDomain/Sources/AgentDomain/WorktreeIsolationPlanner.swift`。

## 1. 全体像

```
[入口: ⌘N / ＋ / プロジェクト行 / グリッド空状態]   （NewChatEntryActions が呼ぶ）
        │ router.showNewChat(projectID:)
        ▼
[新規チャット画面 NewChatView（下段の「新規チャット」タブ）]──参照──[NewChatDraftStore（プロジェクトごとの下書き）]
        │ 送信: NewChatDraft.makeLaunchRequest が NewChatLaunchRequest を作り、下書きを空にする
        ▼
DashboardViewModel.launchNewChat(request, onRowAppended:)
  1. spawnNewSession(backend: .appServer, isolationOverride:, initialSettings:, keepsRowOnLaunchFailure: true, onRowAppended:)
     （worktree 作成 → VM 作成 → 行を出す → CLI 起動）
     └ 行が出た時点で、初回メッセージを会話欄に仮表示（vm.prepareFirstMessage）し、
       呼び出し側が router.completeNewChat(sessionID:projectID:) で新規チャットのタブを外してその行を選ぶ
  2. 起動の成否を vm.launchFailure で判定（ChatLaunchError）
     ├ 成功 → vm.sendFirstMessage(text, attachments)
     └ 失敗 → 行を残し、本文を入力欄へ戻す（vm.markLaunchFailed / vm.restoreLaunchDraft）。
              request は failedNewChatRequests に持つ（再起動用）
```

新しい型は `NewChatDraftStore` / `NewChatDraft`、`NewChatLaunchRequest`、`NewChatView`、`ChatLaunchError`（と `SendRejected`）、`NewChatEntryActions`（入口の共通アクション）、`NewChatHistoryPopover`（履歴の一覧）。ほかは既存の型への引数・分岐の追加と削除。

## 2. 状態とデータ

### 2.1 下書き `NewChatDraftStore`（`DF/NewChat/NewChatDraftStore.swift`）

```swift
@MainActor @Observable public final class NewChatDraftStore {
    private var drafts: [ProjectID?: NewChatDraft] = [:]   // nil = プロジェクト未選択の下書き
    public func draft(for projectID: ProjectID?) -> NewChatDraft   // 無ければ作る
    public func discard(_ projectID: ProjectID)                    // プロジェクト削除時
    public func hasDraft(for projectID: ProjectID) -> Bool         // プロジェクトのメニューの「下書きあり」の印
}

@MainActor @Observable public final class NewChatDraft {
    var text: String = ""
    let attachments = ComposerAttachmentStore()          // 既存（SF/ComposerAttachments.swift:47）
    var usesWorktree = false                             // 作業場所: false = 既存ディレクトリ
    var agentRef: AgentRef                               // ハーネス
    var settings: CodexAppServerSessionSettings          // model・effort・権限・isPlanMode（既存型。AgentDomain/PersistedSessionDescriptor.swift）
    // 操作: selectHarness(_:)（ハーネスを替えて設定を入れ替える）・appendSuggestion(_:)・sendUnavailableReason(…)・canSend(…)・
    //       makeLaunchRequest(projectID:workingDirectoryOverride:)（送信時点の値で NewChatLaunchRequest を作り、本文と添付を空にする）・restoreLaunchDraft(from:)
}
```

- 持ち主は `CompositionRoot.newChatDraftStore`（`AppRouter` と同じく 1 つを全ウィンドウで共有）。`PhloxApp` が `DashboardView` に引数で渡す。
- 入力欄の「プロジェクト」チップは `router.selectedProjectID` そのもの。選び直すと `draftStore.draft(for:)` の引数が変わり、そのプロジェクトの下書きに切り替わる（D9）。
- `agentRef`・`settings` の初期値（下書きを作るとき）: `phlox.newChat.lastHarness` と、そのハーネスの `LastUsedChatSettingsStore` の値。無ければ Claude Code と `AgentModelCatalog.defaultModel(for:)`。
- 設定値の型は新しく作らず `CodexAppServerSessionSettings` を使う。起動経路がすでにこの型で設定を運んでいる（`SSS:871-877`、`CursorModelListProvider.swift:6-14`）。Cursor の mode は今の流儀どおり `selectedPermissionProfile` に、Plan は `isPlanMode` に載せる。

### 2.2 起動要求 `NewChatLaunchRequest`（値型。`DF/NewChat/NewChatLaunchRequest.swift`）

```swift
struct NewChatLaunchRequest {
    let projectID: ProjectID
    let agentRef: AgentRef
    let settings: CodexAppServerSessionSettings
    let usesWorktree: Bool
    let text: String
    let attachments: [ComposerAttachment]     // 送信時点の複製
    let workingDirectoryOverride: String?     // worktree 作成失敗の「既存の worktree を使う」で渡す作業フォルダ（通常は nil）
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

### 3.1 `AppRouter.showNewChat(projectID:)`（`DF/Router/AppRouter.swift`）

```swift
public func showNewChat(projectID: ProjectID?) {
    viewMode = .single                 // グリッドでは selectedSession を外しても画面が変わらないため
    if let projectID { selectedProjectID = projectID }
    selectedSession = nil
    if let selectedProjectID { tabs.updateLayout(for: selectedProjectID) { $0.open(.newChat) } }  // 下段の「新規チャット」タブを開いて選ぶ
    newChatFocusToken &+= 1            // 入力欄へのフォーカス要求（FR-4）
}
```

すべての入口がこれを呼ぶ。入口の UI 操作は `NewChatEntryActions`（`DF/Dashboard/NewChatEntryActions.swift`。`fileMenu`・`sidebarFooter`・`projectPlus`・`projectMenu`・`gridEmptyState`）に集め、プロジェクトが未指定のときの既定は `DashboardViewModel.defaultProjectIDForNewChat` が決める。`newSessionTablePresented` は消した。下段の「＋」のメニュー（`NewTabChooser`）の「新規チャット」と、`NewChatView` のプロジェクト選択も `showNewChat` を呼ぶ。

| 入口 | 呼び出し |
|---|---|
| ⌘N「新規チャット」（`App/PhloxApp.swift` のファイルメニュー） | `NewChatEntryActions.fileMenu()`。`.disabled(projects.isEmpty)` は無い（0 件なら `StartAreaPolicy` が先にオンボーディングを出す） |
| サイドバー下端「＋ 新規チャット」（`DashboardView.swift`） | `sidebarFooter()` |
| プロジェクト行の ＋（`SidebarRows.swift`） | `projectPlus(project.id)`。普通のボタン |
| プロジェクトメニュー「新規チャット」（`DashboardSidebarView.swift`） | `projectMenu(project.id)` |
| グリッド空状態（`DashboardView.swift`） | 「新規チャット」ボタン → `gridEmptyState(projectID: router.gridFilterProjectID)` |

### 3.2 主画面の分岐

- `StartAreaPolicy`（`DF/Dashboard/StartAreaPolicy.swift`）のケースは `projectOnboarding` / `sessionContent` / `newChat` の 3 つ（プロジェクトが 0 件ならオンボーディング、セッションを選んでいれば会話、それ以外は新規チャット）。`selectProjectPlaceholder` と `SelectProjectPlaceholderView` は消した（FR-2a。未選択でも新規チャット画面を出し、プロジェクト選択が空）。
- `DashboardDetailView` の単体表示は、下段で選んでいるタブが `.newChat` のとき `NewChatView` を出す。`startHeader` と `isolates:` は消した。

## 4. 新規チャット画面 `NewChatView`（新規・`DF/NewChat/NewChatView.swift`）

### 4.1 構成

```
NewChatView（入力欄は `NewChatView` の中にあり、`NewChatComposer` という型は無い）
├ 見出し（要件 §5.2 の 10 種類。乱数は注入できる形にする。画面を出すたびに選び直し、入力中は替えない）
├ 入力欄
│  ├ IMESafeTextView（既存。VM 非依存。SF/ChatComposer.swift）
│  ├ 添付の列（ComposerAttachmentStore を表示する既存の部品）
│  ├ 送れない理由の 1 行（要件 E7）
│  └ 下段: 左「＋ / ハーネス・モデル / effort・権限・mode」、右「プロジェクト / 作業場所 / 送信」（要件 E6）
├ 提案チップ 5 個（文言は要件 §5.5）
└ 履歴から再開…（§6。`NewChatHistoryPopover`）
```

### 4.2 入力欄の部品を共用するための切り出し

`ChatComposer` は `ChatSessionViewModel` に強く結合している（`SF/ChatComposer.swift:8-46`）。丸ごと共用はせず、VM に依存しない部品だけを使い、VM に直結している 3 つを値で動く形に変える。セッション画面の見た目と動きは変えない。

| 部品 | 扱い |
|---|---|
| `IMESafeTextView`・`ComposerAttachmentStore`・`ComposerKeyRouting`・`ComposerHeightPolicy`・`composerControls(for:)`・`composerModeOptions` | そのまま使う（VM 非依存） |
| `ComposerAttachPlaceholder`（`SF/ComposerSettingsControls.swift`） | `Binding<String>` と `ComposerAttachmentStore`・`agentRef`・`imageAttachmentsSupported`・`accessibilityIdentifier` を受け取る形に変えた。セッション側は VM から渡す |
| 設定チップ（`ComposerSettingsControlsView`、`ComposerSettingsOverflowMenu`） | 見た目の部分を値で動く `ComposerSettingChip(title:options:selection:accessibilityIdentifier:onSelect:)`（`SF/ComposerDraftInput.swift`）に切り出した。セッション側は VM の値と `setSpawnAgentModel` 等を渡す薄い包みにする。新規チャット側は `NewChatDraft.settings` を渡す |
| `ComposerSuggestionController`（`SF/ComposerSuggestions.swift`） | 作業フォルダがクロージャに閉じ、`@State` で 1 回だけ作られる（`ChatComposer.swift`）。新規チャット側は `.id(候補の基準フォルダ)` で作り直す（E4）。基準は「既存ディレクトリ」ならプロジェクトのフォルダ、「新しい worktree」でもプロジェクトのフォルダ（worktree はまだ無い。作られる中身は同じ HEAD） |
| slash 候補 | 静的リスト＋`~/.claude`・`<cwd>/.claude` の走査＋`availableCommandsStore` で、セッション無しでも出る（U1 は解消）。Codex の skill 候補は起動中の CLI が要るので下書きでは出さない |
| esc・⇧Tab・↑（履歴呼び出し） | 下書きでは esc は何もしない。⇧Tab の effort 切替は `NewChatDraft.settings` に対して同じ規則で行う。↑ は無効 |

### 4.3 ハーネス・モデル選択とその候補

- メニューは `AgentModelCatalog.models(for:)` を、チャット対応の組込ハーネスごとに区切って並べる。未検出（`availableAgentDescriptors` に無い）は区切りごと押せない。
- **Codex の候補を下書きで出すため**、`LiveAgentModelProvider.runCodexModelList`（`ControlServer/.../AgentModelProviders.swift:407-410`）が捨てている `supportedReasoningEfforts`・`defaultReasoningEffort`・`inputModalities` を、カタログの項目に持たせる（`AgentDomain/AgentModelCatalog.swift` の `ControlModelOption` に任意項目 `reasoningEfforts: [String]?`・`defaultReasoningEffort: String?`・`acceptsImages: Bool?` を足した。`AgentModelProviders.swift` の `runCodexModelList` が詰める）。これで effort の候補と画像の可否が下書きでも分かる。メニューの区切りは `NewChatModelMenuSection`（`DF/NewChat/NewChatDraftStore.swift`）が作る。
- Codex の権限の候補は `permissionProfile/list` が要り、起動中の app-server が無いと取れない。下書きでは内蔵の 3 つ（`:danger-full-access`・`:workspace`・`:read-only`。`CVM:2660`）を出し、起動後は実際の一覧に替わる。要件 §5.4 の (2)「最後のセッションの候補」は使わない（要件を改訂する）。
- Claude の effort（`CVM:1588`）・権限・Cursor の mode（`composerModeOptions`）は今も静的なので、そのまま出す。
- ハーネスを替えたら `settings` をそのハーネスの「最後に使った設定」に入れ替える。

### 4.4 送信できる条件

`本文が空でない || 添付がある` かつ `プロジェクトが選択済み` かつ `ハーネスが検出済み` かつ `画像の添付が無い || 選んだハーネス・モデルが画像を受け付ける`。送れないときは要件 E7 の文言（原因と直し方）を 1 行で出す。添付は消さない。

## 5. 送信してからの流れ

### 4.5 アクセシビリティと操作の状態（要件 NFR-4〜7）

- チップは `ComposerSettingChip`（§4.2）にまとめ、`accessibilityLabel`（役割）と `accessibilityValue`（今の値）を付ける。入力欄は `accessibilityLabel("メッセージ")`。
- ホバー・押下中・無効は既存の `HoverableSurfaceButtonStyle`（`DesignSystem/Interaction.swift:276`）を使う。フォーカス枠は `focusRing`（要件 §6.8 で不透明にする）。
- 起動中・起動完了・起動失敗に変わったら `AccessibilityNotification.Announcement` を出す（既存の使い方は `ComposerSettingsControls.swift:1149`）。出すのは `launchNewChat` の呼び出し側の 1 か所。
- 幅が足りないときは、今のセッション画面の下段と同じ判定（`ComposerSettingsOverflowMenu`）で effort・権限を「…」にまとめる。

### 5.1 `DashboardViewModel.launchNewChat(_:onRowAppended:)`

```swift
public func launchNewChat(_ request: NewChatLaunchRequest,
                          onRowAppended: (@MainActor (SessionID) -> Void)? = nil) async throws -> SessionID
```

流れ（実装）:

1. 履歴再開（`resumeHistoryID`）なら、`newChatHistoryEntries` で一覧を引いて該当の項目を取る（無ければ `AgentSpawnError.historyNotFound`）。
2. `spawnNewSession(ref:projectID:backend: .appServer, workingDirectoryOverride:, isolationOverride: request.usesWorktree, initialSettings: request.settings, resumeHistoryEntry:, keepsRowOnLaunchFailure: true, onRowAppended:)`。下に渡るのは履歴の ID ではなく、引いた項目（`resumeHistoryEntry`）。
3. 行が出た時点（`onRowAppended`）で、新規なら `prepareFirstMessage` が本文と添付を会話に先に見せ、そのあと呼び出し側の `onRowAppended` が選択を切り替える。
4. `lastUsedChatSettingsStore.recordLastHarness` で最後のハーネスを記録する。
5. 起動に失敗していれば（`launchFailure != nil`）、要求を `failedNewChatRequests[id]` に保存し、新規なら本文と添付を `restoreLaunchDraft` で入力欄へ戻す。失敗していなければ、新規のとき `sendFirstMessage` で送る。

呼び出し側（`NewChatView` の送信処理。今の `DashboardView.createSession` の役割を引き継ぐ）:

1. `NewChatLaunchRequest` を作り、`router.selectedProjectID` の下書きを空にする。
2. `DashboardViewModel.$reportsWorktreeCreation.withValue(true) { … }` の中で `launchNewChat` を呼ぶ（worktree 作成中のトースト）。
3. 行が出たら `router.completeNewChat(sessionID:projectID:)` が「新規チャット」タブを外し、`.chat(新しい ID)` を選ぶ。
4. 例外（VM ができる前の失敗）は、本文を下書きに戻してダイアログを出す（§5.3 の表）。起動の成否は `AccessibilityNotification.Announcement`（`NewChatLaunchAnnouncement`）で読み上げる。

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

- **再起動**（要件 D20）: 失敗した VM の今の `draft` と `attachmentStore`（ユーザーが直した後のもの）を取り出してから行を閉じ（`removeSession`）、同じ `NewChatLaunchRequest` から本文・添付を除いたもので新しいセッションを起動し、取り出した本文と添付を新しい行の入力欄に入れる。**送信はしない**。同じ VM で `startNew` をやり直す形は採らない。VM の `client` は `let`（`CVM:225`）で、Codex は app-server のプロセスを client を作るとき（`AppEnvironment.swift:250-251`）に起動するため、プロセスが落ちた後は同じ client で起動し直せない（U10）。ハーネスで分けずに 1 つのやり方にする。
- **閉じる**: 今の `removeSession`（`DVM:1618`）。永続化前の行でも使える。worktree は今の後始末で片付く。
- 失敗した行は永続化しない（今も起動成功後にだけ永続化。`DVM:1441`）。アプリを終了すると消え、作った worktree は残る（今と同じ既知の穴）。

GUI 以外（Control API・子セッション）は `keepsRowOnLaunchFailure == false` で今のまま。

- 実装: 再起動は `DashboardViewModel.restartNewChat(_:onRowAppended:)`（失敗した要求は `failedNewChatRequests` に持つ）。失敗した行の「再起動」「閉じる」は `DashboardDetailView` から会話のエラー行に渡す。同じ失敗行の再起動は 1 回だけ受け付け、実行中はボタンを無効にする。本文・添付の移管は 1 回だけ（起動完了後に入れ直さない）。
- 作業場所は元の要求の選択肢を引き継ぐ。「新しい worktree」なら新しい worktree を作り直し、古い worktree は行を閉じるときの今の後始末（強制しない `git worktree remove`。未コミットの変更があれば残す）で片付く。
- 本文・添付を入力欄へ戻すとき（起動前の失敗・初回ターンの失敗・再起動）、入力欄が空ならそのまま戻し、空でなければ戻す本文を今の本文の前に空行 1 つで連結し、添付は前に足す（重複は除く）。どちらの入力も消さない。

### 5.4 初回メッセージ `CVM.sendFirstMessage(_:attachments:)`（新規）

- 預かった添付を `attachmentStore` に入れてから、今の `sendText(_:submit:)`（`CVM:3573`）を呼ぶ。タイトル付け（`adoptTitleFromOriginalUserText` :3655）は今のまま。
- `sendText` の黙って戻る経路（合計サイズ超過 :3605-3609、`imagesUnsupported` :3615-3619、Codex skill の再選択 :3593-3600）を、型つきの例外 `SendRejected` を投げる形に変える。どれも今は本文を `draft` に戻してから戻るので、本文は失われない。呼び出し側は `try` しているので影響は小さい。
- 非同期のエラー（Cursor のターン失敗 `CursorChatClient.swift:171-193`、Claude の `preApprovalDenial` :338）は、ハーネスを問わず次の規則にする: **会話の最初のターンが、応答を 1 つも返さずに `.error` で終わったら、送った本文を `draft` に戻す**（`CVM:2252` のイベント処理で判定）。
- Claude の `turnStart` は `transport == nil` なら起動し直す（`ClaudeChatClient.swift:318-325`）。初回送信はこれに頼らず、§5.3 で起動の成功を確かめてから送る。

## 6. 履歴から再開

- 一覧の読み込み: `ClaudeSessionHistoryDiscovery` / `CodexSessionHistoryDiscovery` は VM に依存しない値型（U3 は解消）。`AppEnvironment` の provider 生成（`AppEnvironment.swift:191-231`、作業フォルダ 1 つが前提）に、作業フォルダの配列を取る版を足し、結果をまとめて更新日時の新しい順に並べる（最大 20 件）。
- 対象の作業フォルダ: `[project.directoryPath] + (project.worktreePaths ?? [])`（D10）。`worktreePaths` には、worktree を作るたびに（`SSS:598` の `finishSessionLaunch` で登録するとき）その場所を足して `persistProjects()` する。worktree を消しても残す。Claude は `~/.claude/projects/`、Codex は state の SQLite か rollout に会話が残るので、worktree が消えていても一覧に出せる。
- 表示条件: 選択中のハーネスが Claude か Codex で、一覧が空でないとき。一覧を開いた後は「読み込み中」「履歴がありません」「履歴を読み込めませんでした」＋「再試行」を区別する（要件 FR-13b）。一覧の UI は `NewChatHistoryPopover`（`DF/NewChat/NewChatHistoryPopover.swift`。状態は idle・loading・entries・empty・failed）で、行の部品だけ `ChatHistoryStartView.swift` の `HistoryStartRow` を使い回す。
- 再開: `NewChatLaunchRequest.resumeHistoryID` を付けて `launchNewChat`（§5.1 の 1・2）。引いた項目を `spawnNewSession` の `resumeHistoryEntry` で渡し、起動側が履歴再開を行う。
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
| `NewSessionCollisionGate.peers`（`StartScreenViews.swift`。消した） | 消す（確認ダイアログの廃止） |
| UI の切替 4 か所 | `DashboardSidebarView.swift:518-521`、`DashboardToolbar.swift:134-159`（「プロジェクト名を変更…」:444 は残す）、`App/PhloxApp.swift:1051-1080`、`DashboardDetailView.swift:122` |

worktree のチャットを別プロジェクトへ動かせない制限（`canMoveSession` `DVM:1562`）は、復元で `ownedWorkspaceDirectories` に登録し直されることが前提で、新しい規則でも保たれる。

### 7.3 実装の前提（ユーザーの承認が要る）

凍結された受け入れテスト `AcceptanceRestoreAbortNoSpawnTests` の 1 つ目（「共有ディレクトリでエージェントを起動しない」）は、「プロジェクト設定オン・保存済みの作業フォルダは本体のフォルダ・worktree の場所に未登録のフォルダ」で中止を期待している。新しい規則では作業フォルダが本体なので worktree を使わず、本体のフォルダで起動する。テストの意図（「隔離するはずのセッションを共有フォルダで起動しない」）は、「保存済みの作業フォルダが worktree の場所・その場所が未登録のフォルダで埋まっている」に置き換えれば保てる。**凍結テストの書き換えはユーザーが承認済み（2026-10-11）。** 2 つ目は `worktreeIsolationEnabled:` 引数を消すだけで成り立つ。

ほかにプロジェクト設定を使うテスト（`WorktreeIsolationSpawnTests` 21 か所、`AcceptanceWorktreeIsolationTests` 20 か所、`WorktreeIsolationPlannerWhiteboxTests`、`StartScreenRedesignTests`、`UITests/IsolatedLaunchOptionsTests`）は、設定オンを `isolationOverride: true`（新規）か「作業フォルダが worktree の場所」（復元）に置き換える。検証している中身は変えない。

### 7.4 対象外の既知の穴

ターミナルのセッションを `changeWorkspace`・`moveSession` で別フォルダへ移すと、作業フォルダが worktree でなくなり、復元で worktree が使われず残る（`DVM:1611`）。今もある穴で、本件では直さない。

## 8. ターミナルのセッション（要件 D1・FR-19・FR-20）

- 画面からターミナルのセッションを始める経路は作らない。`DashboardView.createSession` の `.pty` 分岐と、その呼び出し元（新規セッションの表・起動カード）は §9 で消す。
- `spawnNewSession(backend: .pty)` は Control API・CLI・復元が使うので残す。

## 8.1 カスタムエージェントの廃止（要件 D22・§8.6）

- `AgentRef` は `.builtin` だけにする。`init(from:)` は `AgentKind(rawValue:)` に失敗したら投げる。保存済みのカスタムのセッションは `JSONSessionStore` の `DiscardableSession`（`MessageStore/.../JSONSessionStore.swift:44-71`）が個別に捨てる。捨てた件数を `DashboardViewModel` に渡し、1 以上なら起動後に 1 回トーストを出す。
- 未知の ref 用に同じ形の仮 descriptor を作っている 5 か所（`SessionSpawnService.swift:823-835`、`SessionTreeSidebarSection.swift:7-18`、`ControllableSession.swift:154-165`、`ChatSessionView.swift:171-182`、`ChatTranscriptView.swift:380-391`）は、ref が常に組込になるので消す。
- 偽エージェントの E2E・UI テストは、組込ハーネス（例 Claude Code）の実行ファイルの場所を `fake-agent.sh` に差し替えて動かす（実行ファイルの場所は `AppEnvironment` の `AgentBinaryTable` が持つ）。

## 9. 消すもの

| 対象 | 場所 |
|---|---|
| 新規セッションの表 | `NewSessionTable`・`NewSessionTableRow`・`NewSessionPopoverButton`・`NewSessionKeys`（`StartScreenViews.swift:204-460`）、`NewSessionMenuModel.swift`、`AppRouter.newSessionTablePresented`、`DashboardView` の `newSessionTable(projectID:)`・`newSessionTableBinding`・`newSessionTableProjectID`・ポップオーバー 2 つ |
| 確認ダイアログ | `SpawnGuard.collision`・`SpawnGuardSheet` の確認部分・`NewSessionCollisionGate.peers`・`createSession` の確認分岐。`worktreeFailureLog`・`existingWorktree` は残す |
| 起動カード | `AgentStartCards.swift` 一式・`AgentStartProjectHeader`・`AgentStartCardSelection`・`agentStartEntries`（他に使う所が無ければ） |
| プレースホルダ | `SelectProjectPlaceholderView`・`StartAreaPolicy.selectProjectPlaceholder` |
| 既定の開き方 | `DefaultSessionBackendPreference`・設定画面の分節ボタン（`App/SettingsView.swift:37,54,158-165`）・`spawnNewSessionUsingDefaultProject`（`DVM:525`） |
| 使われていない起動関数 | `spawnNewClaudeCodeSession`（`DVM`。消した。テストは `spawnNewSession(kind: .claudeCode)` に置き換えた） |
| `DashboardView` の状態 | `isCreating`・`creatingRef`・`spawnGuard` の衝突ケース（`createSession` は新規チャットの送信処理と §8 の依頼処理に分かれる） |
| 文言 | 確認ダイアログの 4 キー・未使用の 1 キー（要件 §8.1）、表・起動カード・既定の開き方の文言 |
| ハーネスの色（要件 FR-30） | `AppTheme.agentColors`・`DSColor.agentColor(for:)`・`agentInitialFill`・`AgentDescriptor.colorRGB` と、それを渡している所（要件 §8.5）。`AgentBrandIcon.fallbackIcon` はカスタムの廃止で不要になるので消す |
| 略号・図形（要件 §6.7・§8.5） | `StateGlyph`（状態は行の右端の文字に置き換え）、`tabInitials`（`Tokens.swift`。消した）とその表示箇所、モデルのチップの色の四角、未読の丸（題名の文字色・太さに置き換え）、使用量画面の代替の印（`AgentBrandIcon` を各社の SVG ロゴに置き換え）。場所の一覧は要件 §8.5 |

> **実装との差（2026-10-12 時点のコード）**: 確認ダイアログの廃止後も、worktree 作成失敗の確認だけは残っている。`StartScreenViews.swift` に `NewSessionRequest`・`SpawnGuard`（`.worktreeFailed` のみ）・`NewSessionCollisionGate`（`worktreeFailureLog`・`existingWorktree` のみ。`peers` は無い）・`SpawnGuardSheet` が残る。`NewSessionTable` 系・`NewSessionMenuModel`・`AgentStartCards`・`SelectProjectPlaceholderView`・`StateGlyph`・`tabInitials`・`claudeCoral` は本番コードに無い。

## 9.1 配色（要件 §6.8）

- `DesignPalette.phloxLight`・`phloxDark` の `accent`・`accentFill`・`accentInk` を要件 §6.8 の値に替え、`accentFillColor`（`DesignPalette.swift:48`）を #3B469B にする。
- UI のアクセント（`DSColor.accent`・`accentInk`。`Tokens.swift:223,294`）は `theme.palette` から取る。外部テーマの palette は背景の明るさで `phloxLight` か `phloxDark` を基準に選ぶ（`DesignPalette.swift:84,102-103`）ので、**明るいテーマは #3B469B、暗いテーマは #959CD0 が自動で入る**。暗い外部テーマに #3B469B（背景との比 2 前後）が入ることはない。
- `AppTheme.claudeCoral`（`AppTheme.swift:95`）を消す。今これを読むのは、テーマ見本の印（`ThemePreviewModel.swift:44` の `theme.accent`）と、既定 2 テーマの `attention`（:250。読むのは本番で使われていない `idleHighlight` 系だけ）。`AppTheme.accent` は `palette.accent` にし、既定 2 テーマの `attention` は `palette.approval.mark` にする（画面への影響は無い）。
- `selectionFill`・`textSelection`（`Tokens.swift:296,301`）の直書き #D97757 を `accent` から取る形にする。`focusRing`（:298）は不透明度を外す。
- アクセントの使用箇所は実装時に役割（主要な操作・選択・フォーカス・リンク）で分け、どれにも当たらないものは中立の色に替える（要件 FR-29）。
- 検査は `DesignPaletteTests` に足す（要件 AC-16）。

## 10. 文言（`App/Localizable.xcstrings` に日本語キー＋英訳を手で足す）

見出し 10 種類（要件 §5.2 の表。名前は出さず、画面を出すたびにランダムに 1 つ）、「やりたいことを入力（/ でコマンド）」、「既存ディレクトリ」、「新しい worktree」、「git リポジトリではないため worktree を作れません」、「新規チャット」、「履歴から再開…」、要件 E7 の 3 つ（原因と直し方）、「メッセージ」（入力欄の読み上げ）、起動の 3 状態の読み上げ、「送信待ち」、「起動しています…」、「履歴を読み込めませんでした」「再試行」、状態の文字 6 つ（要件 FR-24）、「起動できませんでした」、「再起動」、提案チップ 5 個と定型文 5 つ。メニュー（`.commands`）はアプリ内の言語切替がその場で効かない既知の制約がある（`docs/specs/localization.md`）。

## 11. 実装の順番

プロジェクトのタブ（[project-tabs-design.md](project-tabs-design.md)）と同時に作る（project-tabs.md P9）。新規チャット画面は下段の「新規チャット」タブに入るので、タブの土台を先に作る。

| 段 | 内容 | 閉じる受け入れ基準 | 担当 |
|---|---|---|---|
| 0 | 済み: ADR 0183〜0187・§7.3 の凍結テストの書き換えの承認・§12 の確認・モック確定 | — | — |
| 1 | worktree の判断の作り直し（§7）と、それに伴うテストの置き換え | AC-3・AC-5b・AC-6 | 難 |
| 2 | 起動の配管: `initialSettings`、`ChatLaunchError`、`keepsRowOnLaunchFailure`・`markLaunchFailed`・再起動（新しいセッションで起動し直す）、`StructuredAgentClient.start()` を投げる形に、`sendFirstMessage`・`SendRejected`・初回ターンの失敗で本文を戻す規則、`LastUsedChatSettings` の拡張、Codex のモデル候補の拡張 | AC-2・AC-5・AC-5a・AC-7・AC-15 | 難 |
| 3a | タブのモデルと保存・移行（project-tabs-design §2〜4・§7）、子タブの持ち主の鍵の付け替え（§5） | PAC-1〜3・PAC-5 | 難 |
| 3b | タブの画面（§8）・共通ターミナルの廃止（§6）・ヘッダー（`.unifiedCompact`・プロジェクト名と worktree のボタンの撤去）・キーボード（§9）・グリッドのタイルから子タブを外す・worktree のセッションの変更の欄 | PAC-4・PAC-6・PAC-8・PAC-9 | 通常 |
| 4 | `NewChatDraftStore`・`NewChatView`（下段の「新規チャット」タブ）・入力欄の部品の切り出し・提案チップ | AC-2a・AC-5d〜5g・AC-8・AC-9a | 通常 |
| 5 | 入口・`showNewChat`・メニュー・§9 の削除・設定画面、カスタムエージェントの廃止（§8.1） | AC-1・AC-4・AC-9 | 通常 |
| 6 | 履歴から再開（§6） | AC-5c・AC-18 | 通常 |
| 7 | 略号・図形・ハーネスの色の廃止と状態の文字化・未読の文字色・SVG ロゴ（§9）、配色（§9.1）、使用量のバーと対応待ちの撤去（要件 §6.9） | AC-12〜AC-14・AC-16・AC-20〜AC-22 | 通常 |
| 8 | 画面外の描画（`DesignSnapshotRenderTests`）でモック（`ClaudeDesign/10`〜`12`）と見比べ、XCUITest、資料（要件 §10） | AC-10・AC-11・AC-17・AC-19・PAC-7 | 通常 |

担当（ユーザー指示 2026-10-12）: 難 = Codex `gpt-6.1-sol`・effort medium、通常 = Codex `gpt-6-luna`・effort max、テストと検証の実行 = `checker` サブエージェント、独立レビュー = Codex `gpt-6.1-sol`・effort high（読み取り専用）。指揮・資料・統合はメインのセッション。

各段の終わりに `.claude/verify.sh`（メインの checkout にある）を checker で通し、その段の受け入れ基準が green になってから次の段に進む。コードレビューは全段が終わってから 1 回まとめて行う（`AGENTS.md`「開発の進め方」）。

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
