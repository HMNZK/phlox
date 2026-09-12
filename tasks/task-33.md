---
id: task-33
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceNewSessionMenuModelTests.swift
baseline_commit: c615c0a
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
  - 事前条件: `descriptors` の `ref.id` は一意（製品側 `AgentCatalog` が重複排除済み。重複入力の挙動は未定義でテストも渡さない）。trim は `.whitespacesAndNewlines`（タブ・改行も除く）。
  - チャット/ターミナルの判定と backend 写像は自前で書かず、既存の `AgentStartCardsModel.modes(for:)` と `AgentStartCardMode.backend` を再利用する（ADR 0082 の単一規則を維持。敵対レビュー 9）。custom descriptor（`ref == .custom`）は `kind` を触らず `ref` だけで扱う（`AgentDescriptor.kind` は custom で preconditionFailure）。
  - `static let chatSectionTitle: String` / `static let terminalSectionTitle: String`
  - `descriptors` が空 → `primary == nil`、`sections == []`（destinationText は出る）。
- 配線（`DashboardView.newSessionMenuItems(projectID:)`）: `viewModel.projects.first { $0.id == projectID }?.name` を `projectName:` に（見つからなければ nil。**引数の `projectID` を使う。選択中プロジェクトではない**）、`NewSessionMenuModel.make(projectName:descriptors: viewModel.availableAgentDescriptors)` で組む。描画順は ①`Text(model.destinationText)`（Menu 内の非活性行）②`if let primary = model.primary` → `Button { createSession(ref: primary.ref, projectID: projectID, backend: primary.backend) } label: { Label(primary.title, systemImage: primary.systemImage) }` ③`ForEach(model.sections, id: \.title)` → `Section(section.title) { ForEach(section.items) { item in Button { createSession(ref: item.ref, projectID: projectID, backend: item.backend) } label: { Label(item.title, systemImage: item.systemImage) } } }`。`Section { … } header: { Text(section.title) }` も同等として許容。`createSession` の `projectID:` は必ず引数の `projectID` をそのまま渡す（nil 化・省略は、B 行から作ったセッションが選択中の A に入る欠陥＝敵対レビュー 4）。`Text(model.destinationText)` は Button の label に入れない。描画順は ①②③ の順。
- 既存の `newSessionMenuTitle(descriptor:mode:)`／`newSessionMenuSymbol(mode:)` は削除する（モデルに集約）。`AgentStartCardsModel.modes(for:)` は他所（空状態カード・TeamTimelineView）で使われ続けるので削除しない。
- 不変条件: `createSession(ref:projectID:backend:)` のシグネチャと挙動、`AgentStartCards.swift`、`DashboardSidebarView` の Menu ラベル（＋アイコン・help）、TeamTimelineView の追加メニュー、`availableAgentDescriptors` の順序（Claude Code 先頭）を変えない。ローカライズは既存ファイルと同じくリテラル日本語。

- 本契約は「作成先の表示」と「起動候補の分類・起動」の 2 成果を 1 メニュー改善として束ねた複合契約である（敵対レビュー 10）。双方の合格を必須とし、片方だけの pass は認めない。

## 成功基準

1. 凍結テスト `AcceptanceNewSessionMenuModelTests` green（作成先の trim（空白・タブ・改行）／空／nil、primary は順序上最初のチャット対応 descriptor（Codex→Claude の逆順入力で Codex になること、Claude 不在）、custom descriptor（`.custom("ui01-probe")`、チャット非対応）だけの入力で primary nil・`terminal:ui01-probe` のみ、チャット非対応のみなら primary nil かつチャット節なし、全 descriptor にターミナル項目・チャット対応 descriptor にチャット項目が順序どおり存在、id の一意性、descriptors 空、節タイトル定数）。DashboardFeature 全数 green。
2. 配線検査 `.claude/scripts/task33-wiring.rb` OK（コメント行を除去した `newSessionMenuItems` 本文に対して: `NewSessionMenuModel.make(` の引数が `projectName:` に `projectID` を使った `projects` の検索と `descriptors:viewModel.availableAgentDescriptors` を含む／`Text(model.destinationText)` があり Button の label 内に無い／`if let <name> = model.primary`／`Section(section.title)` または `header:{Text(section.title)}`／`ForEach(` が `model.sections` と `section.items`／`createSession(` の引数が `ref:primary.ref,projectID:projectID,backend:primary.backend` と `ref:item.ref,projectID:projectID,backend:item.backend`（空白除去後）／`Label(primary.title,systemImage:primary.systemImage)` と `Label(item.title,systemImage:item.systemImage)`／destinationText → primary → `ForEach(model.sections` の出現順／`newSessionMenuTitle`・`newSessionMenuSymbol` が残っていない／`AgentStartCardsModel.modes(for:` が `newSessionMenuItems` 本文に無い）。`NewSessionMenuModel.swift` に `AgentStartCardsModel.modes(for:` と `.backend` の参照があり `.appServer`/`.pty` のリテラルが無い。`AgentStartCards.swift`・`TeamTimelineView.swift` は基準 `TASK33_BASELINE`（verify スクリプトが固定 SHA を渡す。HEAD 自己比較にしない）から差分なし（`DashboardSidebarView.swift` は task-34 が変えるため対象外）。
3. PM 目視ゲート: 隔離 Debug で「UI検証A」行の＋を開き、先頭行に「作成先: UI検証A」、次に「新しいチャット（Claude Code）」、続いて「チャット — …」節と「ターミナル — …」節が出ること。作成先行は AX で `enabled == false`。**A を選択中に B 行の＋**からターミナル節の custom kind（ui01-probe）を作り、生成セッションが B に入ること。名称空のプロジェクトで「名称未設定のプロジェクト」が出ること。primary と組込チャット/ターミナル経路は課金セッションを起動するため実行しない（ref/backend の対応は凍結テストと配線検査で担保、AX で項目名と enabled のみ確認）と明記して記録する。

## レビュー観点（Rubric）

- 以前の 6 経路（3 エージェント × チャット/ターミナル）がすべて到達可能なまま残っている。
- 「新しいチャット」が何のエージェントで開くか、項目名だけで分かる。
- 作成先の表示が UX-04/UI-08 の「対象範囲」の語彙と矛盾しない（「作成先」は task-32 の isDefaultTarget と同じ概念）。
- Menu 内の `Text` 行はクリックしても何も起きない（誤って Button にしていない）。
