---
status: active
last-verified: 2026-10-12
---

# プロジェクト単位のタブ（設計）

> **このファイルの役割**: [要件](project-tabs.md) をどう作るか。型・持ち主・保存・画面の分け方。
> **書かないもの**: 要件と受け入れ基準（→ [project-tabs.md](project-tabs.md)）、なぜこの設計か（→ [ADR 0187](../adr/0187-project-tabs.md)）、新規チャット画面の中身（→ [unified-new-chat-start-design.md](unified-new-chat-start-design.md)）。
> パスは `macos/Packages/DashboardFeature/Sources/DashboardFeature/` を `DF/` と略す。

## 1. 全体像

- 上段 = サイドバーの全プロジェクト（並びもサイドバーと同じ）。状態は持たず、毎回サイドバーの並びから作る。
- 下段 = 選択中のプロジェクトの「チャット」＋「項目」。
  - チャット = そのプロジェクトのセッション。状態は持たず、毎回サイドバーと同じ並び（`sessionForest(in:)` の木を上から順。今の `tabSessionNodes(in:)` の範囲）から作る。
  - 項目 = 新規チャット・ターミナル・変更・ファイル・ブラウザ・シミュレーター。プロジェクトごとに並びを持つ。
  - 表示の並びは「チャット → 項目」。
- 左右の分割・選択はプロジェクトごとに持つ。

## 2. 型（`DF/Tabs/ProjectTabs.swift`。旧 `SessionTabs.swift` を置き換えた）

```swift
/// 下段のタブ 1 つ。
public enum ProjectTab: Hashable, Codable, Sendable {
    case chat(SessionID)          // 保存しない（サイドバーから作る）
    case newChat                  // プロジェクトに 1 つまで（PE4）
    case terminal(TerminalTabID)  // 複数可（PE6）。TerminalTabID は UUID の包み
    case changes
    case browser
    case simulator
    case file(String)             // プロジェクトのフォルダからの相対パス
}

/// 1 プロジェクト分の項目の並び・選択・左右分割。今の `SessionTabLayout` の操作（open・select・close・cycle・splitRight・toggleSplit）をそのまま移す。
public struct ProjectTabLayout: Codable, Equatable, Sendable {
    public var items: [ProjectTab] = []   // .chat は入れない
    public var left: ProjectTab?          // nil = まだ何も選んでいない（チャットの先頭か新規チャットを出す）
    public var right: ProjectTab?
    public var focusesRight = false
    public var splitFraction: Double = 0.5
}

public struct ProjectTabsSnapshot: Codable, Equatable, Sendable {
    public var projects: [ProjectID: ProjectTabLayout] = [:]
}
```

- `ChildTab`・`SessionTabLayout`・`ProjectTabState`（`order`・`closed`）・`SessionTabsSnapshot` は消した。タブ列からだけ外す状態（`closed`）は P7 で無くなった。
- 同じファイルに、持ち主の `ProjectTabStore`（`@MainActor @Observable`。`layout(for:)`・`updateLayout(for:_:)`・`forgetProject(_:)`・`closeTarget(projectID:selectedSession:viewMode:)`・`migrateLegacy(sessionProjects:projects:)`。保存先は `UserDefaults` の `phlox.projectTabs.v1`）、ターミナルの識別子 `TerminalTabID`（UUID の包み）、閉じる対象 `CloseCommandTarget`、隠れた対応待ちの要約 `HiddenAttentionSummary` がある。`ProjectTabLayout` にはこのほかに `showChat(_:keeping:)`（チャットを前に出しつつ、分割中は指定のタブを残す）と `reconcileChats`（チャットが消えたときの選択の付け替え）がある。
- `ProjectTabStore` は `AppRouter.tabs` として持つ。チャットの並びは `DashboardViewModel.chatTabs(in:)` が毎回作る。
- 「会話は閉じられない」の特例は「`.chat` はこの型の中では閉じない（閉じる＝セッションの削除で、呼び出し側が確認ダイアログを出す）」に替わる。
- `cycle`・⌘1〜9 の並びは「チャット → 項目」を連結した列で数える（`DashboardViewModel.numberedTabs(router:)`）。

## 3. 選択とルーター

- 下段で `.chat(id)` を選ぶ ⇔ `router.selectedSession = id`。サイドバーでセッションを選ぶと、そのプロジェクトに切り替えて `.chat(id)` を選ぶ（今の `reveal` の置き換え）。
- 新規チャット画面を出す（`router.showNewChat(projectID:)`）＝そのプロジェクトの `.newChat` を開いて選び、`selectedSession = nil`。送信して行が出たら `router.completeNewChat(sessionID:projectID:)` が `.newChat` を項目から外し、`.chat(新しい ID)` を選ぶ（PE4。下書きは `NewChatDraftStore` が持つので、タブを外しても残る）。
- セッションが 0 件のプロジェクトを選んだ・何も選んでいないときは `.newChat` を出す（新規チャットの要件 D21。`router.ensureProjectSelection(chatTabs:)`）。
- 単体表示だけで使う。グリッドのタイルは会話だけを出し、子タブを持たない（PE8。`GridTileParts`・`PaneLayoutView` から子タブを外す）。

## 4. 閉じる・削除

| 操作 | 対象 | 動き |
|---|---|---|
| 上段の ✕ | プロジェクト | 今の `pendingProjectDeletion` を立てる（確認ダイアログ。P5・P7） |
| 下段の ✕・⌘W | `.chat(id)` | 今のセッション削除の確認（`SessionDeletionDialogText`）。削除したら隣のタブを選ぶ |
| 下段の ✕・⌘W | `.newChat` | 項目から外すだけ。下書きは残す |
| 下段の ✕・⌘W | ターミナル | 実行中なら確認してから、シェルを止めて外す（今と同じ） |
| 下段の ✕・⌘W | ファイル | 未保存なら確認（今と同じ） |
| 下段の ✕・⌘W | 変更・ブラウザ・シミュレーター | 外す（今と同じ） |
| ⌘W（グリッド） | タイル | グリッドから外す（今と同じ） |

`CloseCommandTarget` は `.tab(ProjectTab)`・`.session(SessionID)`・`.project(ProjectID)`・`.gridTile(SessionID)` にする。セッション・プロジェクトを消したら、`ProjectTabsSnapshot` から自動で消える（チャットは保存していないため。プロジェクトは `forgetProject` で項目ごと消す）。

## 5. 子タブの中身の持ち主（鍵を替える）

| 持ち主 | 旧い鍵 | 今の鍵 | 作業フォルダ |
|---|---|---|---|
| `ProjectTerminalStore`（`DF/UserTerminal/ProjectTerminalStore.swift`。旧 `SessionTerminalStore`） | `SessionID` | `TerminalTabID`（プロジェクトの ID・作業フォルダも一緒に持つ） | プロジェクトのフォルダ |
| `AppRouter.browsers`（`DF/Router/AppRouter.swift`） | `SessionID` | `ProjectID` | — |
| `SimulatorHub`（`DF/Simulator/SimulatorHub.swift`） | `SessionID` | `ProjectID` | — |
| `FileTabDocuments`（`DF/Tabs/FileTabDocument.swift`。`FileTabDocumentRegistry` が未保存の確認のために `ProjectID` ごとの変更中の印を持つ） | `(SessionID, path)` | `(ProjectID, path)` | プロジェクトのフォルダ |
| 変更（`EditorPanelView(workingDirectory:)`） | セッションの作業フォルダ | プロジェクトのフォルダ | — |

- worktree で動くセッションの変更は、会話画面の上端の行（「worktree で実行中 · ブランチ名」「変更 n ファイル」）から、会話の右に幅 440pt の欄で開く。中身は `EditorPanelView(workingDirectory: セッションの作業フォルダ)`（P2・モック 11 の T6）。そのフォルダのターミナルは置かない（P8）。
- プロジェクトを消したら、そのプロジェクトのターミナル・ブラウザ・シミュレーター・ファイル文書をすべて閉じる。

## 6. 共通ターミナルの廃止（P3）

`PhloxApp.swift` の共通ターミナルの所有と ⌃⌘T 等のメニュー、`AppRouter.commonTerminalSelected`、`SessionTabBar` の右端、`FileTreeRows.openPath` 等の参照を消した（2026-10-12 に廃止済み。本番コードに `commonTerminal` は無く、`ProjectTabsPresentationTests` が確かめる）。ユーザーターミナルをセッションとして登録しないこと・アプリ終了時の後始末（ADR 0149 の 1・4）は `ProjectTerminalStore` が引き継ぐ。

## 7. 保存（PE9）

- 新しいキー `phlox.projectTabs.v1` に `ProjectTabsSnapshot` を保存する。保存するのは `.newChat`・`.changes`・`.file` と選択・分割。`.terminal`・`.browser`・`.simulator` は今どおり保存しない（保存用コピーで外す）。
- 移行: 新しいキーが無く旧キー `phlox.sessionTabs.v1` があるとき、旧 `sessions[id]` の `.file(path)` を、そのセッションのプロジェクトの `.file(path)` に移す（同じ相対パスがプロジェクトのフォルダに無ければ捨てる）。`.changes` はどれかのセッションが開いていれば移す。旧キーは消さない（E1: 新版が旧データを読めることだけを保証する）。
- 移行は 1 回だけ（新しいキーを書いたら旧キーは読まない）。

## 8. 画面

| 部品 | 変更 |
|---|---|
| `DF/Tabs/SessionTabBar.swift` | 上段＝プロジェクトのタブ。✕ は選択中・ホバー中だけ出し、説明は「プロジェクトを削除…」。右クリックに「プロジェクト名を変更…」（今の `router.projectRenameRequest` を立てる。サイドバーを隠していれば出す）。右端の ＋ はプロジェクトの追加（⌘O と同じ）。入りきらなければ 180→96pt に縮め、残りを「ほか n ⌄」 |
| `DF/Tabs/SessionTabsContainer.swift` の前半 | 下段（`ChildTabBar`）＝チャット → 項目。チャットの ✕ の説明は「セッションを削除…」、新規チャットは「外す（下書きは残ります）」、ほかは「閉じる」。＋ のメニュー（`NewTabChooser`）は 新規チャット ⌘N / ターミナル / 変更 / ファイルを開く… / ブラウザ / シミュレーター、下端に「ターミナル・変更・ファイルは <プロジェクト> のフォルダで開きます」 |
| `DF/Dashboard/DashboardToolbar.swift` | `titleBlock`・`worktreeMenu`・`WorktreeMenuButton`を消した。残るのはサイドバーの開閉（隠しているときだけ）・`ViewModeToggle`（右寄せ）・インスペクタの開閉 |
| `DF/Dashboard/WindowChromeConfigurator.swift` | `toolbarStyle = .unifiedCompact`。`DSLayout.toolbarHeight`（`DesignSystem/Tokens.swift`）は 38pt にした（旧 52。モックと同じ。macOS 26 での実測は未確認） |
| 識別子 | `tabs.project.<n>`・`tabs.project.add`・`tabs.item.<n>`・`tabs.item.add`・`tabs.overflow`（モック 11） |

## 9. キーボード（PE11）

⌃Tab・⌃⇧Tab = 下段の次／前（メニュー「次のタブ」「前のタブ」）、⌘1〜9 = 下段の n 番目（メニュー「セッションのタブ n」）、⇧⌘[・⇧⌘] = 上段の前／次（メニュー「前のプロジェクト」「次のプロジェクト」）、⌘T = 下段の ＋ のメニュー（メニュー「新しいタブ…」）、⌘W = §4、⌘\ = 左右の分割。いずれも `App/PhloxApp.swift` のメニュー項目。

## 10. テスト

- 単体（`DashboardFeatureTests/ProjectTabsTests.swift`・`ProjectTabsPersistenceTests.swift`・`ProjectTabsPresentationTests.swift`）: `ProjectTabLayout` の操作、チャットの並びがサイドバーと一致すること、`CloseCommandTarget` の振り分け、移行、削除で項目・持ち主が消えること、共通ターミナルが本番コードに無いこと。
- XCUITest: タブ列の切り替えと ✕ の確認ダイアログ（`PanelUITests`・`SimulatorTabUITests` を直す）。
- 見た目: `DesignSnapshotRenderTests` でモック 11・12 と見比べる。
