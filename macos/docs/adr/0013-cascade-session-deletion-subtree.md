---
status: active
last-verified: 2026-07-04
---

# ADR 0013: セッション削除をサブツリー・カスケード化（子孫の reparent を廃止）

- ステータス: 採用（Accepted, 2026-06-17）
- 作成日: 2026-06-17
- 関連: `DashboardViewModel.removeSession` / `SessionPersistenceCoordinator`。子プロセスのライフサイクル堅牢化（ADR 0009）と対になる「Phlox セッションツリー側」の削除挙動の決定。認可は `SpawnPolicy.isAuthorizedToRemove`（無変更）。
- コンテキスト: 従来、親セッションを削除すると `removeSession` が冒頭で `reparentChildren(of:to:)` を呼び、**直接の子の `parentSessionID` を祖父へ付け替える（reparent）だけ**で、子・孫…の各セッションとそのプロセスは生き残っていた。OS プロセスツリー（その CLI が起動した子孫プロセス）は対象セッションを `terminate()`→`killpg` すれば落ちるが、Phlox の**セッションツリー上の子孫セッション**には終了処理が伝播せず、ユーザーから見ると「親を消したのに配下のセッションが残る」状態だった。要望は「親セッションを削除したら、その配下の全子孫セッションを必ずまとめて削除する」。

## 1. 決定

1. **core `removeSession` をサブツリー・カスケード化**: `removeSession(id)` は `id` を根とするサブツリー（自身＋全子孫）を列挙し、各メンバーに per-session の終了・除去処理を適用する。reparent は廃止。これにより削除の全入口（サイドバー / Cmd+W / メニュー / Control API `/remove` / `removeProject` / `abortLoopflowSession`）が自動的にカスケードする（「必ず」を一箇所で担保）。

2. **サブツリー列挙は post-order の深い順**: `subtreeSessionIDsDeepestFirst(rootedAt:)` が `sessionNodes` を `parentSessionID` でグルーピングし、子を再帰してから自身を append する post-order DFS で「深い子孫 → 根」の順に列挙する。`visited.insert(_:).inserted` で循環・重複に耐性を持たせ、`existingIDs` guard で欠損リンクをスキップする。深い順に除去するため途中失敗でも孤児を残しにくい。

3. **per-session 処理を `removeSingleSession` に抽出**: 旧 `removeSession` 本体から reparent だけを除いたもの（hooks cleanup / `terminate()` / owned workspace 破棄 / continuation finish / codex native discovery cancel / unseenCompletion 更新 / `sessions`・`sessionNodes` 除去 / `spawnTimestamps` 除去 / `tokenStore.remove` / `persistence.removeSession`）を、サブツリー各メンバーへ漏れなく適用する。`reparentChildren` と `SessionPersistenceCoordinator.persistReparentedChildren` は未使用となるため削除した。

4. **確認ダイアログに子孫件数を表示**: `DashboardViewModel.descendantCount(of:)`（= サブツリー数 − 1、根を除く子孫数。**読み取り専用の純関数**で `@Observable` state を mutate しない＝view body 評価中の再無効化ループを作らない）を追加し、サイドバーの削除確認ダイアログは件数>0 のとき「このセッションと子孫◯件を削除しますか?」、0 件のとき従来文言を表示する。

## 2. 根拠 / トレードオフ

- **single-writer 的な一箇所担保**: 削除入口が複数あるため、各入口でカスケードを書くと漏れる。core の `removeSession` 一点でカスケードすることで「どの消し方でも必ず子孫まで消える」を構造的に保証する（reparent 撤去で旧経路の生き残りも消える）。
- **認可との整合**: `isAuthorizedToRemove` は「requester が対象の祖先なら可」。サブツリーの子孫は定義上、根の子孫なので、根の削除が認可されればカスケードも整合する（認可ロジックは無変更）。
- **AppServer（Codex Chat）セッションは既存仕様のまま**: per-session の `terminate()` は PTY backend では `killpg`、AppServer backend では `client.close()`（単一プロセスへ SIGTERM）。AppServer の killpg 化・SIGKILL エスカレーションは本決定のスコープ外（別問題）。

## 3. スコープ外 / 既知の受容したエッジケース

- **`removeProject` のクロスプロジェクト・カスケード（受容）**: カスケードは `projectID` ではなく `parentSessionID`（subtree）で決まる。`moveSession`（サイドバーのドラッグ）はセッションの `projectID` だけを変え親子リンクを保持するため、「親=プロジェクトA・子=プロジェクトB」というクロスプロジェクト親子を作れる。この状態で `removeProject(A)` を呼ぶと、A の親を削除する際に **B に表示中の子（とその子孫）まで巻き込んで削除**される（旧 reparent 挙動では生き残っていた）。これは「subtree = 親子関係」という一貫した設計の直接の帰結であり、PM 裁定で**現状維持（受容）**とした。プロジェクト境界でカスケードを止める特別扱いは導入しない（稀な構成・設計の単純さ優先）。
- AppServer セッションの killpg 化 / 個別削除パスへの SIGKILL エスカレーション追加 / セッションツリー UI の見た目変更（確認ダイアログ文言以外）。

## 4. 検証

- 単体（`DashboardFeatureTests`）: 新規 `removeSession_cascadesToAllDescendantsAndKeepsOutsideSessions`（祖父→親→子→孫＋兄弟。`removeSession(親)` で親・子・孫が消え祖父・兄弟が残る／PTY `kill` が親・子・**孫（深さ2）**の3件呼ばれる／永続化が {祖父, 兄弟} になる、を `MockPTYManager` で検証）。`ControlAuthorizationTests` の旧 `removeSession_reparentsChildrenToRemovedSessionsParent` を `removeSession_cascadesChildrenInsteadOfReparenting` へ書き換え（reparent 期待 → カスケード期待。仕様変更に伴う正当な強化でアサーション弱体化ではない）。`E2EControlServerTests` は孫を追加し Control API kill 経由でカスケードを検証。
- 実走（PM）: `swift test`（DashboardFeature）**592 green** + ヘッドレス E2E（`PHLOX_E2E=1 … --filter E2E --no-parallel`）**16 green**。Claude reviewer **go（blocker/major 0）**（再帰の正しさ・per-session クリーンアップの完全温存・再入安全な除去順序・reparent 撤去の完全性・ダイアログの純粋読み取りを確認）。
- **runtime（実 Debug 起動での実カスケード目視）は未実施**。コード層・E2E でカバー。
