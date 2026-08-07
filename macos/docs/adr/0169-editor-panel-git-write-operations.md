---
status: accepted
last-verified: 2026-08-04
supersedes: 0150-editor-panel-git-semantics.md
---

# ADR 0169: エディタパネルの git 書き込み操作（commit / push / PR 作成）

> **このファイルの役割**: [ADR 0150](0150-editor-panel-git-semantics.md) が
> 「stage/commit/push はスコープ外」とした決定を覆し、変更一覧から commit → push →
> PR 作成までを製品内で完結させる書き込み面の境界と意味論を決める。
> **書かないもの**: merge・衝突解消 UI、ブランチの作成・切替（既存 `GitBranchSwitcher`）、
> 変更一覧のスコープ解決（[ADR 0150](0150-editor-panel-git-semantics.md) の読み取り側と
> task-3 の `SessionChangeScope`）。

## 文脈

ADR 0150 は phase0 時点の前提として「変更のレビュー・その場修正まで」に絞り、
stage/commit/push UI をスコープ外にした。その後、変更一覧がセッションスコープで
使えるようになり（task-3）、ユーザーは「見た変更をそのまま commit し、必要なら
push / PR まで進めたい」という一連の作業を製品の外（CLI）へ落とさずに済ませたい
状態になった。

ゲート①で「0150 の書き込みスコープ外決定を覆し、merge / 衝突解消は引き続き外す」
ことが承認された。0150 の**読み取り側**（変更一覧の一本化・保存競合・
`--no-optional-locks`・意味論的不変条件）は維持する。覆すのは「書き込み UI を
持たない」という境界だけである。

## 決定

1. **製品内に入れる書き込み操作は commit・push・PR 作成の 3 つに限る。**
   merge・衝突解消・ブランチ作成/切替はスコープ外のまま（後者は既存
   `GitBranchSwitcher` の領域）。
2. **読み取りと書き込みをサービスで分ける。**
   - 読み取り: 既存の `WorkingTreeService`（ADR 0150。公開 API を変えない）。
   - 書き込み: 新規 `GitWorkflowService`（`commit` / `remoteNames` / `push` /
     `isGitHubCLIAvailable` / `createPullRequest`）。
   分けた理由は、0150 が `WorkingTreeService.runGit` を
   「状態変更系サブコマンドを呼ばない・`--no-optional-locks` 前提」と意味論化した
   契約を壊さないため。
3. **部分コミットは選択パスだけを対象にし、他の変更と既存のステージ内容を巻き込まない。**
   `git add -A` や pathspec 無しの `git commit` は使わない。`git commit -- <paths>` は
   既に `--only` 意味論なので、追跡済みパスは add 不要。未追跡ファイルだけを
   `git add --` + `:(literal)` pathspec で index に載せたうえで、同じ literal pathspec で
   `git commit -m <msg> --` する（他パスのステージ済みエントリはコミットに入らない）。
   pathspec には必ず `:(literal)` を前置し、ファイル名中の glob メタ文字（`[` `*` `?` 等）や
   `:` 始まりの magic 解釈で未選択ファイルを巻き込んだりコミット不能になったりしないようにする。
   空文字列／空白のみのパスは `:(literal)` が git 上「全ファイル」に化けるため
   `.noPathsSelected` で拒否する。commit が失敗したときは、直前に add した未追跡パスだけを
   `git rm --cached -- :(literal)<path>` で戻し、`.git/index` をファイルコピーで差し替えない
   （git の作法に沿い、index.lock や非アトミック置換の穴を作らない）。
4. **失敗は握りつぶさない。** git / `gh` が非 0 で終了したら
   `GitWorkflowError.commandFailed(arguments:output:)` に**実行した引数と
   stdout+stderr をそのまま**載せて throw する。空メッセージは `.emptyCommitMessage`、
   パス未選択は `.noPathsSelected`、非リポジトリは `.notARepository`、
   リモート未設定の push は `.noRemoteConfigured`、`gh` 不在の PR 作成は
   `.gitHubCLIUnavailable`。
5. **製品コードはユーザーの git identity / 署名 / hooks 設定を上書きしない。**
   `user.name` / `user.email` / `commit.gpgsign` / `hooksPath` への書き込みは行わない
   （テスト側がリポジトリローカルで固定するのはテストの責務）。
6. **UI は到達可能で、無効理由を画面に出す。** エディタドロワー（⌘⌥E）内の
   変更一覧からコミット UI に届く。既定ドロワー幅（420pt → stacked）でも
   変更リストの数行と Commit / Push / Create PR ボタン・無効理由ラベルが同時に
   見えるよう、stacked 時は変更リスト（スクロール可）・コミットパネル・詳細を 3 分割の
   `VSplitView` に分け、コミット UI は常に独立ペインで表示する。変更リスト最小高は 72pt。
   コミットパネルは `stackedCommitPanelBudget`（固有高の上限）とコンパクトな余白・
   コントロールサイズで予算内に収める。`workflowStatusMessage` は `Text` を `commitStatusMaxHeight` の固定高に収め、
    長い git 失敗出力でもボタン列を押し出さない（`ScrollView` は変更リスト側と
    競合して高さ 0 に潰れるため使わない）。溢れた行はクリップし、全文は
    `.textSelection(.enabled)` でコピー可能。閉じる（消す）手段も必ず用意する。
    この表示方針は詳細を展開可能にする方式へ変更したため、固定高に関する記述は
    [ADR 0171](0171-editor-panel-workflow-status-disclosure.md) で superseded とする。
   狭い split 列では `ViewThatFits` でボタンを縦積みへ落とし、ラベルが判別できるようにする。
   リモート未設定なら push を無効化して理由を表示し、
   `gh` 不在なら PR 作成を「利用不可」と明示する（ログだけに出して UI が黙るのは不可）。
   `remoteNames()` は凍結契約どおり非 throwing のまま、失敗時は actor 内に理由を保持し
   UI が「リモート未設定」と「git 実行失敗」を区別できるようにする。
   PR タイトルは入力中のメッセージが空なら直近コミットの subject を既定にする。
   stacked / ターミナル同時表示での到達性はフェーズ4の実機確認で検証する（`NSWindow` を
   起動する描画テストは MainActor 占有により他テストを不安定化させるため採用しない）。
7. **git 実行の流儀は `WorkingTreeService.runGit` に揃える。**
   `Process` + stdout/stderr の 2 Pipe を並行排出してから `waitUntilExit()` する
   （ADR 0150/0151 のデッドロック教訓）。`GitBranchSwitcher` の単一 Pipe 方式は
   採らない。共通ヘルパーへの抽出は、読み取り側パッケージ境界を触る変更になるため
   今回は行わず、書き込み側に同型の実装を置く。

## 結果

- `GitWorkflowService` が書き込みの唯一の入口になる。`EditorPanelViewModel` /
  `GitCommitPanel` がそれを呼び、変更一覧の選択パスとメッセージから commit し、
  続けて push / PR 作成へ進める。
- 0150 の読み取り不変条件（意味論的状態を変えない・`save` 以外で
  `git add` 等を発行しない）は `WorkingTreeService` 側に残る。
- 回帰保護: `AcceptanceGitWorkflowTests`（入力検証・部分コミット・失敗出力保全・
  push・`gh` 不在）と `GitWorkflowWhiteboxTests`（他ステージ保全・特殊パス・
  削除済み・失敗出力の原因文字列・壊れた symlink）。
  `GitCommitPanel` の固有高は `NSHostingView.fittingSize` の軽量白箱で予算内であることを固定する。
