---
status: active
last-verified: 2026-07-04
---

# ADR 0027: グリッドのワークスペース絞り込みは orchestration サブセッションを含める（サーフェス別の可視性ルール分離）

## 文脈

Phlox のセッション一覧には可視性の異なる複数のサーフェスがある。従来、CLI エージェントの `spawn`（Control API `spawnSession(ref:from:backend:)`）で作られる「メインからスポーンされたサブセッション」は `launchContext: .orchestration` が固定され、`DashboardViewModel.isVisibleInGrid(launchContext:)`（`launchContext != .orchestration`）で以下の**すべて**から除外されていた:

- 未選択（トップレベル）グリッド … `gridVisibleSessionNodes`
- ワークスペース（Project）絞り込みグリッド … `filteredGridSessions` → `sessionNodes(in:)`
- サイドバーのフラット一覧 … `sessionNodes(in:)` / `unassignedSessionNodes`

ワークスペース絞り込みグリッドがサイドバー用の `sessionNodes(in:)` を流用していたため、「ワークスペースを押して中身を見たい」場面でも `.orchestration` サブセッションが落ち、親（対話）セッションしか出なかった。要望は「グリッドでワークスペースを押したときは、そのワークスペース内のサブセッションを含む全セッションを表示する」。

前提事実（調査で確認）: サブセッションは `resolveProjectID(explicit:parentSessionID:)` により親と同じ `projectID` を継承する。したがって所属情報は既に存在し、`projectID` 一致で親・子孫を漏れなく拾える。`SessionLaunchContext` は `.interactive` / `.orchestration` の2値のみ。

## 決定

**サーフェスごとに可視性ルールを分離する。** ワークスペース絞り込みグリッドだけがサブセッションを含み、トップレベルグリッドとサイドバーは従来どおり除外する。

1. `DashboardViewModel` に用途専用メソッド `gridSessionNodes(in projectID:) -> [SessionNode]` を追加する。実装は `sessionNodes.filter { $0.projectID == projectID }` のみで、**`isVisibleInGrid` / `isVisibleInSidebar` を通さない**（`.orchestration` を含む全セッションを返す）。`projectID` でスコープされ、別ワークスペースを混ぜない。
2. `DashboardView.filteredGridSessions` のワークスペース選択時分岐（`gridFilterProjectID` 非 nil）を `sessionNodes(in:)` から `gridSessionNodes(in:)` へ差し替える。未選択分岐（`gridVisibleSessionNodes`）は不変更。
3. 既存メソッド `sessionNodes(in:)` / `gridVisibleSessionNodes` / `isVisibleInGrid` / `sessionForest(in:)` は無改変。これらは他に4箇所（ナビ順序・削除操作・選択復元）で使われ、`.orchestration` 除外を前提とする既存テストが固定しているため、共通メソッドを書き換えず**新メソッドで用途を足す**。

## 棄却案

- **`sessionNodes(in:)` にフラグ/条件を注入**して grid とサイドバーで挙動を切り替える: 共通メソッドの4箇所すべてに影響が波及し、既存テスト（`OrchestrationSessionOperationTests` 等）を壊す。用途で本質的に異なる可視性ルールを1メソッドに詰め、対症療法的に歪める。→ 用途専用メソッドの追加で分離。
- **トップレベルグリッドでもサブセッションを表示**: 未選択グリッドが子セッションで溢れ、俯瞰性を損なう。ユーザー確認（承認ゲート①）で「トップレベルは非表示のまま／ワークスペース選択時のみ全表示」と決定。
- **サブセッションを親の下にネスト表示**: グリッドはフラットなタイル集合という既存構造を維持。ネスト/グルーピングは今回のスコープ外（要件は「表示する」まで）。

## 結果

- グリッドでワークスペースを押すと、そのワークスペースの親＋サブセッションが全タイル表示される。トップレベルグリッドとサイドバーの `.orchestration` 除外は非退行。
- 変更は2ソースファイル・実質2箇所（新メソッド＋呼び出し1行）に収束。
- 受け入れテスト（`GridWorkspaceSubsessionAcceptanceTests`: 親＋サブ包含／未選択・サイドバー非退行／ワークスペーススコープ）で契約を凍結。DashboardFeature **584 green**、ヘッドレス E2E **17 green**、独立レビュー（persona-reviewer）pass・指摘なし。
- runtime（実 Debug 起動でのグリッド目視）は未実施。SessionGridView は任意の `SessionNode` を描画するためコード層・テスト層でカバー。

作業経緯は delivery/0010-grid-workspace-subsessions-worklog.md を参照。
