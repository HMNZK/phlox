---
status: accepted
last-verified: 2026-08-01
---

# ADR 0148: ターミナル／エディタパネルの容器はメインウィンドウ内のドロワーにする

> **このファイルの役割**: ターミナルパネル・エディタパネルを表示する「容器」（分割ペイン／独立ウィンドウ／オーバーレイ）を
> ドロワー（メインウィンドウ内 trailing 分割ペイン）に確定した理由（ゲート②決定）。
> **書かないもの**: ドロワー内部の構成・コンポーネント一覧（→ [architecture/terminal-editor-panels.md](../architecture/terminal-editor-panels.md)）、
> ユーザーターミナルのライフサイクル（→ [ADR 0149](0149-user-terminal-lifecycle.md)）。

## 文脈

Phlox は操作系 UI を前面オーバーレイで描く方針（ADR 0073）だが、AppKit の `NSView`（SwiftTerm の
`TerminalView`）は SwiftUI の overlay より前面に出る（[ADR 0136](0136-pane-split-tree-layout.md) §3）。
したがってターミナルを含むパネルを `.overlay` で置くと、既存の `.pty` タイルや他の操作系 UI との
前後関係が崩れる（パネルが隠れる、あるいはパネル内 NSView が他 UI を突き抜ける）。この制約により、
容器は「オーバーレイ」を最初から不成立と判断し（フェーズ0で既知リスクとして記録）、
「メインウィンドウ内の分割ペイン（ドロワー）」と「独立ウィンドウ（`AgentConsole` と同型の `Window(id:)`）」の
2 方式に絞ってプロトタイプ（task-3）を作り、ユーザーが実機で比較して確定する運びとした
（ゲート①決定）。

## 決定

**両パネル（ターミナル・エディタ）とも、容器はメインウィンドウ内の trailing ドロワー（分割ペイン）にする。**
独立ウィンドウ方式は棄却し、プロトタイプ隔離コード（`PanelContainerPrototype.swift`）は task-5 で撤去した。

- ホットキー: ターミナルは ⌘⌥T、エディタは ⌘⌥E（`PhloxApp.swift` の `CommandGroup(after: .sidebar)` に
  それぞれ登録し、`AppRouter.toggleTerminalPanel()` / `toggleEditorPanel()` を呼ぶ）。
- ドロワーは**レイアウトフロー内**に置く（`DashboardView` の本文 `HStack` の一部として幅を確保する）。
  `.overlay` には置かない。これにより NSView の前後関係問題を構造的に回避する。
- 両パネルが同時に可視のときは `VSplitView` で縦に積む（ターミナルが上段、エディタが下段）。
- 分割線ハンドル・ドラッグのゴースト線は、`DashboardView` の overlay チェーンの**最後**（既存の
  サイドバー／インスペクタのリサイズハンドルより後）に置く。ADR 0136 §3 の「分割線ハンドルは
  ZStack の最後（最前面）」の教訓を踏襲し、ドロワー内 `TerminalView`（NSView）に掴みしろを
  奪われないようにする。
- **トップバー（Usage 等）はパネル幅から独立**させる。`DashboardTopBarControls` へ渡す
  `windowWidth` は `geometry.size.width`（ウィンドウ全幅）であり、ドロワー幅を差し引かない
  （ゲート②の追加要件②）。

## 棄却した選択肢

- **独立ウィンドウ**（`Window(id:)` + `openWindow`、`AgentConsole` と同型）: task-3 のプロトタイプで
  両方式を実装し、ユーザーが実機比較のうえ棄却（ゲート②決定）。ウィンドウ方式は同一
  `UserTerminalController` を共有できることを確認済みだったが、単一ウィンドウの一体感を優先し不採用。
  プロトタイプ隔離コードは撤去済み（task-5）。
- **オーバーレイ**: ADR 0136 §3 の z 順序制約により、フェーズ0の時点で不成立と判断し、プロトタイプ検証の
  対象にも含めなかった。

## 結果

- エディタパネルはドロワーの既定幅（420pt）・最小幅（280pt）では左右分割表示の内在最小幅（541pt）を
  満たせないため、`EditorPanelLayout.mode(forWidth:)` が幅に応じて `.split` / `.stacked`
  （変更リストと詳細ペインを縦積み）を切り替える（task-5 で追加。統合レビューで発見・修正）。
- 分割線のドラッグ開始幅は「保存値」ではなく「現在表示中の（クランプ済み）幅」から採る
  （`DashboardView.swift` の `isDraggingDrawer` フラグ）。保存値起点だとウィンドウ縮小後に
  分割線が無反応になる欠陥がレビューで見つかり、修正済み。
- 回帰保護: `AcceptanceTerminalPanelWiringTests`（task-3）・`AcceptancePanelIntegrationTests`（task-5）・
  `PanelIntegrationWhiteboxTests`・`PanelUITests`（XCUITest、⌘⌥T/⌘⌥E の出現・消滅を
  accessibilityIdentifier で検査）。
