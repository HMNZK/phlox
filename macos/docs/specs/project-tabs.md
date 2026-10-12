---
status: active
last-verified: 2026-10-12
---

# プロジェクト単位のタブ（要件）

> **このファイルの役割**: 上段のタブをプロジェクトにし、その下にそのプロジェクトのチャット・ターミナル・ファイルを並べる変更の要件。
> **設計**: [project-tabs-design.md](project-tabs-design.md)。
> **書かないもの**: 新規チャット画面そのもの（→ [unified-new-chat-start.md](unified-new-chat-start.md)）。なぜこの設計か（→ [ADR 0187](../adr/0187-project-tabs.md)）。
> **見本**: `ClaudeDesign/11 Project Tabs.dc.html`（ヘッダーと使用量のバーは `ClaudeDesign/12 Header and Usage Bar.dc.html`）。
> **状態**: 決定済み（2026-10-11）。新規チャット画面と同時に実装した（P9。段 1〜7 のコミット 07650a0e..b23855e2）。受け入れ基準の充足は本ファイルでは確認していない。「現状」「廃止する」は実装前の記述のまま残す。型・ファイル名は [project-tabs-design.md](project-tabs-design.md) を参照。

## 1. 解決したい問題

今の上段は「選択中のプロジェクトのセッション」、下段は「選択中のセッションの子タブ（会話・ターミナル・変更・ファイル・ブラウザ・シミュレーター）」を並べている（`DashboardFeature/Tabs/SessionTabs.swift:7-15,130-141`）。ターミナルやファイルがセッションに属するため、同じプロジェクトでもセッションを替えるとターミナルやファイルが見えなくなる。ユーザーは、プロジェクトを単位にして、そのプロジェクトのチャット・ターミナル・ファイルを横に並べて切り替えたい。

## 2. ユーザーが決めた事項（2026-10-11）

| # | 問い | 決定 |
|---|---|---|
| P1 | タブの構成 | 上段はプロジェクトのタブ（選択中を強調、右端に ＋）。その下に、選択中のプロジェクトのチャット・ターミナル・ファイルのタブ（右端に ＋） |
| P2 | ターミナル・変更・ファイルの基準のフォルダ | **プロジェクトのフォルダ**。worktree で動くセッションの変更（差分）は、そのセッションの会話画面の中で見る |
| P3 | 共通ターミナル（ホームで開く、タブ列の右端） | **廃止する**。ターミナルはプロジェクトのタブの下に一本化する |
| P4 | 左のサイドバー | **今のまま残す**（状態の文字を一覧で見る場所） |
| P5 | プロジェクトの削除 | そのプロジェクトのセッション（チャット・ターミナルのセッション）と、プロジェクトのターミナル・ファイル等のタブをすべて消す。今の確認ダイアログ（`DashboardView.swift:230-251`）はそのまま出す |
| P6 | ヘッダー | プロジェクト名（`DashboardToolbar` の `titleBlock`）と `WorktreeMenuButton` を消す。上段のタブに名前が出るため。「プロジェクト名を変更…」は上段のタブの右クリックへ移す（worktree の切替は新規チャット画面の作業場所のチップへ移る。新規チャットの要件 E3）。ヘッダーに残るのは、サイドバーの開閉（サイドバーを隠しているときだけ）・単体／グリッドの切替・インスペクタの開閉。**高さは必要最小にする**（§3 PE12） |
| P7 | タブの ✕ とサイドバーの関係 | **タブ列とサイドバーを常に一致させる**。上段 = サイドバーの全プロジェクト、下段のチャット = そのプロジェクトの全セッション（並びもサイドバーと同じ）。タブ列からだけ外す操作は無い。上段の ✕ はプロジェクトの削除（P5 の確認ダイアログ）、下段のチャットの ✕・⌘W はセッションの削除（今の確認ダイアログ `SessionDeletionDialogText`。今の会話タブの ⌘W `CloseCommandTarget.session` と同じ）。消すとサイドバーからも消える |
| P8 | worktree で動くセッションのフォルダでターミナルを開く（旧 U-P1） | **入口を置かない**。必要ならプロジェクトのターミナルで自分でフォルダを移る |
| P9 | 実装の順番（旧 U-P2） | **新規チャット画面と同時に作る**。今のタブ構成に一度組み込んでから作り直す手間を避ける |

## 3. AI が提案しユーザーが承認した事項（2026-10-11）

| # | 事項 | 既定 |
|---|---|---|
| PE1 | 上段の ＋ | プロジェクトを追加（今の「プロジェクトを追加…」⌘O と同じ。フォルダを選ぶ） |
| PE3 | 下段の ＋ | メニュー: 新規チャット（新規チャット画面を出す）/ ターミナル / 変更 / ファイルを開く… / ブラウザ / シミュレーター。今の子タブの種類をそのまま使う |
| PE4 | 新規チャット画面の置き場所 | 下段に「新規チャット」のタブとして出す（プロジェクトごとに 1 つ。下書きと同じ単位）。送信するとそのタブがセッションのタブになる。このタブだけはサイドバーに無いので、✕ はタブを外すだけで下書きは残す |
| PE5 | 下段のチャット以外のタブの ✕・⌘W | ターミナル・変更・ファイル・ブラウザ・シミュレーターは今どおり閉じる。ターミナルは実行中なら確認、ファイルは未保存なら確認（チャットのタブは P7） |
| PE6 | ターミナルの数 | プロジェクトごとに複数持てる（今はセッションごとに 1 つ） |
| PE7 | 左右の分割 | 今のセッション単位の分割（`SessionTabLayout` の left/right）をプロジェクト単位に移す |
| PE8 | グリッド表示 | 残す。タイルは会話だけを出す（タイルの子タブのターミナル・変更はセッションに属さなくなるので出さない） |
| PE9 | 保存 | プロジェクトとチャットのタブはサイドバーから作るので保存しない。チャット以外の項目の並び・開いているファイル・選択中の項目を保存する（新しいキー。今の `phlox.sessionTabs.v1` からは、セッションのファイルタブをそのプロジェクトへ移して読む）。ターミナルは今どおり保存しない |
| PE10 | 複数ウィンドウ | 今どおり全ウィンドウでタブの状態を共有する（`AppRouter` が 1 つ） |
| PE11 | キーボード | ⌃Tab・⌃⇧Tab で下段の次／前、⌘1〜9 で下段の n 番目、⇧⌘[ ・⇧⌘] で上段の前／次のプロジェクト、⌘T で下段の ＋ のメニュー。今の割り当てと重ならないか実装時に確かめる |
| PE12 | ヘッダーの高さ | ウィンドウの `toolbarStyle` を `.unified` から `.unifiedCompact` に替え、`DSLayout.toolbarHeight`（今 52pt）を信号（閉じる・しまう・拡大）の帯の高さに合わせる。28pt のボタンが収まる。値は macOS 26 の実機で測って決める（未計測） |

## 4. 現状（2026-10-11 の調査）

- 子タブはすべて `SessionID` を鍵にしている: 配置 `SessionTabsSnapshot.sessions`、ターミナル `SessionTerminalStore.terminals`（`UserTerminal/SessionTerminalStore.swift:12`）、ブラウザ `AppRouter.browsers`（`Router/AppRouter.swift:66`）、シミュレーター `SimulatorHub`、ファイル文書 `(sessionID, path)`（`FileTabDocumentRegistry.swift:238`）。
- ターミナル・変更・ファイルの基準はセッションの作業フォルダ（worktree なら worktree）（`SessionTabsContainer.swift:91-103`、`FileTabOpening.swift:6-11`）。
- 共通ターミナルは `PhloxApp.swift:137-145` が持ち、ホームで開く（ADR 0149）。
- 上段・下段の描画は `SessionTabBar.swift`、`SessionTabsContainer.swift:1-515`（`ChildTabBar`・`NewTabChooser`・`ChildTabPanes`）。単体表示だけで使う（`DashboardView.swift:758-771`）。
- タブ列に `accessibilityIdentifier` は無い。

## 5. 修正範囲（見込み）

| 対象 | 変更 |
|---|---|
| モデル | `SessionTabs.swift` を「プロジェクト → 項目（チャット・ターミナル・変更・ファイル・ブラウザ・シミュレーター）」に作り直す。ターミナルは項目ごとの ID を持つ |
| 子タブの持ち主 | `SessionTerminalStore`・`AppRouter.browsers`・`SimulatorHub`・`FileTabDocumentRegistry` の鍵を `SessionID` から項目またはプロジェクトに替える |
| 画面 | `SessionTabBar`（プロジェクトのタブに）、`SessionTabsContainer` の前半（下段・追加メニュー・分割）、`GridTileParts`・`PaneLayoutView`（タイルは会話だけ） |
| 共通ターミナル | `PhloxApp.swift` の所有と ⌃⌘T 等、`AppRouter.commonTerminalSelected`、`SessionTabBar` の右端、`FileTreeRows.openPath` 等の参照を消す |
| worktree のセッションの差分 | 会話画面の中で開く手段（P2）。今の `EditorPanelView(workingDirectory:)` をそのセッションの作業フォルダで使う |
| ショートカット | ⌘T・⌘W・⌘1-9・⌃Tab・⌘\\ の対象をプロジェクト・項目に合わせる（`App/PhloxApp.swift`） |
| ヘッダー | `DashboardToolbar` の `titleBlock`・`worktreeMenu`・`WorktreeMenuButton` を消す。「プロジェクト名を変更…」を上段のタブの右クリックへ。`WindowChromeConfigurator` の `toolbarStyle`、`DSLayout.toolbarHeight`（P6・PE12） |
| 削除の連動 | 上段の ✕ を今のプロジェクト削除の確認（`pendingProjectDeletion`）へ、下段のチャットの ✕ を今のセッション削除の確認へつなぐ（P7） |
| 新規チャット仕様との関係 | `unified-new-chat-start.md` の FR-1a（`commonTerminalSelected` を外す）は共通ターミナルの廃止で不要になる。新規チャット画面は PE4 で下段のタブになる |
| 資料 | `delivery/0037-ui-redesign-c-decided.md`（今のタブの決定。履歴として残す）、ADR 0149（共通ターミナル）を置き換える ADR、`architecture/terminal-editor-panels.md` |

規模の見込み: ソース 12〜15 ファイル、1,500〜2,500 行の変更。テストは `SessionTabsTests`・`SessionTabsPersistenceTests` の大半の書き直し、XCUITest 2〜3 本（`PanelUITests`・`SimulatorTabUITests`）、`DesignSnapshotRenderTests` の撮り直し。

## 6. 未決

なし（旧 U-P1・U-P2 は P8・P9 で決定）。

## 7. 受け入れ基準

| # | 基準 | 確かめ方 |
|---|---|---|
| PAC-1 | 上段にプロジェクト、下段に選択中のプロジェクトのチャット・ターミナル・ファイルが並ぶ。セッションを替えてもプロジェクトのターミナル・ファイルのタブは残る | 単体テスト（タブのモデル）＋ XCUITest |
| PAC-2 | ターミナル・変更・ファイルはプロジェクトのフォルダで開く | 単体テスト |
| PAC-3 | プロジェクトを削除すると、そのセッションとターミナル・ファイル等のタブがすべて消える | 単体テスト |
| PAC-4 | 共通ターミナルが無い（メニュー・ショートカット・タブ列） | 単体テスト＋ビルド |
| PAC-5 | 旧 `phlox.sessionTabs.v1` のファイルタブが、そのプロジェクトのタブとして読み込まれる | 単体テスト |
| PAC-6 | タブ列のボタン・タブに `accessibilityIdentifier` があり、キーボードで切り替えられる | XCUITest |
| PAC-8 | ヘッダーにプロジェクト名と worktree のボタンが無く、高さが `.unifiedCompact` の帯と同じ。信号とボタンの縦の中心が揃う | 単体テスト（定数）＋ `DesignSnapshotRenderTests` |
| PAC-9 | 上段・下段のチャットのタブがサイドバーと常に一致し、✕ で確認の後にプロジェクト・セッションが消え、サイドバーからも消える | 単体テスト＋ XCUITest |
| PAC-7 | 見た目が見本と揃っている | `DesignSnapshotRenderTests`（ユーザー承認） |
