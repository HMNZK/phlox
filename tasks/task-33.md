---
id: task-33
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceNewSessionMenuModelTests.swift
baseline_commit: TBD
contract_tests: []
allowed_paths:
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/NewSessionMenuModel.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift
  - docs/agent-output/task-33.md
---

## 目的

UX-07。サイドバーの各プロジェクト行にある「＋」メニューは「<エージェント名> — チャット／ターミナル」が平坦に 6 項目並び、
どこに作られるか・通常はどれを選べばよいかが分からない。作成先を明示し、「新しいチャット」を先頭の主操作にし、
残りをチャット／ターミナルの節に分けて短い説明を添える。既存の各エージェント×表示方式への経路は 1 つも失わない。

## 入出力契約

- 新設 `NewSessionMenuModel`（`NewSessionMenuModel.swift`、`struct`、`Equatable`、internal、SwiftUI 非依存の純粋値型）:
  - `struct Item: Equatable, Identifiable { let id: String; let title: String; let systemImage: String; let ref: AgentRef; let backend: SessionBackend }`
  - `struct Section: Equatable { let title: String; let items: [Item] }`
  - `let destinationText: String` — `"作成先: " + name.trimmed`。`projectName` が nil／空／空白のみなら `"作成先: 名称未設定のプロジェクト"`（task-31 の語彙と同じ）。
  - `let primary: Item?` — `descriptors` の順で最初の `supportsStructuredChat == true` の descriptor。`id == "primary"`、`title == "新しいチャット（\(displayName)）"`、`systemImage == "plus.bubble"`、`backend == .appServer`。該当なしなら nil。
  - `let sections: [Section]` — 順序固定で最大 2 節。
    - チャット節: `title == NewSessionMenuModel.chatSectionTitle`（`"チャット — 会話形式で応答を読む"`）。`supportsStructuredChat` の descriptor ごとに `Item(id: "chat:\(ref.id)", title: displayName, systemImage: "bubble.left.and.bubble.right", ref:, backend: .appServer)`。該当 0 件なら節ごと省く。
    - ターミナル節: `title == NewSessionMenuModel.terminalSectionTitle`（`"ターミナル — CLI をそのまま端末で操作"`）。全 descriptor ごとに `Item(id: "terminal:\(ref.id)", title: displayName, systemImage: "terminal", ref:, backend: .pty)`。descriptors が空なら省く。
    - 各節内の順序は `descriptors` の順序を保つ。
  - `static func make(projectName: String?, descriptors: [AgentDescriptor]) -> NewSessionMenuModel`
  - `static let chatSectionTitle: String` / `static let terminalSectionTitle: String`
  - `descriptors` が空 → `primary == nil`、`sections == []`（destinationText は出る）。
- 配線（`DashboardView.newSessionMenuItems(projectID:)`）: `viewModel.projects` から `projectID` に一致する `Project.name` を取り（見つからなければ nil）、`NewSessionMenuModel.make(projectName:descriptors: viewModel.availableAgentDescriptors)` で組む。描画順は ①`Text(model.destinationText)`（Menu 内の非活性行）②`if let primary` → `Button { createSession(ref: primary.ref, projectID:, backend: primary.backend) } label: { Label(primary.title, systemImage: primary.systemImage) }` ③`ForEach(model.sections, id: \.title)` → `Section(section.title) { ForEach(section.items) { Button { createSession(ref: item.ref, projectID:, backend: item.backend) } label: { Label(item.title, systemImage: item.systemImage) } } }`。
- 既存の `newSessionMenuTitle(descriptor:mode:)`／`newSessionMenuSymbol(mode:)` は削除する（モデルに集約）。`AgentStartCardsModel.modes(for:)` は他所（空状態カード・TeamTimelineView）で使われ続けるので削除しない。
- 不変条件: `createSession(ref:projectID:backend:)` のシグネチャと挙動、`AgentStartCards.swift`、`DashboardSidebarView` の Menu ラベル（＋アイコン・help）、TeamTimelineView の追加メニュー、`availableAgentDescriptors` の順序（Claude Code 先頭）を変えない。ローカライズは既存ファイルと同じくリテラル日本語。

## 成功基準

1. 凍結テスト `AcceptanceNewSessionMenuModelTests` green（作成先の trim／空／nil 3 分岐、primary は順序上最初のチャット対応 descriptor、チャット非対応のみなら primary nil かつチャット節なし、全 descriptor にターミナル項目・チャット対応 descriptor にチャット項目が順序どおり存在、id の一意性、descriptors 空、節タイトル定数）。DashboardFeature 全数 green。
2. 配線検査 `.claude/scripts/task33-wiring.rb` OK（`DashboardView.swift` に `NewSessionMenuModel.make(`／`destinationText`／`.primary` の `if let`／`Section(` の引数が section の title／`ForEach(` が `model.sections` と `section.items`／Button 内の `createSession(` に `ref:` と `backend:` が item／primary から渡る／`newSessionMenuTitle`・`newSessionMenuSymbol` が残っていない／`AgentStartCardsModel.modes(for:` が `newSessionMenuItems` 本文に無い）。`AgentStartCards.swift`・`DashboardSidebarView.swift`・`TeamTimelineView.swift` は差分なし。
3. PM 目視ゲート: 隔離 Debug で「UI検証A」行の＋を開き、先頭行に「作成先: UI検証A」、次に「新しいチャット（Claude Code）」、続いて「チャット — …」節と「ターミナル — …」節が出ること。ターミナル節から custom kind（ui01-probe）のセッションを実際に作れること。名称空のプロジェクトで「名称未設定のプロジェクト」が出ること。

## レビュー観点（Rubric）

- 以前の 6 経路（3 エージェント × チャット/ターミナル）がすべて到達可能なまま残っている。
- 「新しいチャット」が何のエージェントで開くか、項目名だけで分かる。
- 作成先の表示が UX-04/UI-08 の「対象範囲」の語彙と矛盾しない（「作成先」は task-32 の isDefaultTarget と同じ概念）。
- Menu 内の `Text` 行はクリックしても何も起きない（誤って Button にしていない）。
