---
status: accepted
last-verified: 2026-08-01
---

# ADR 0150: エディタパネルの git 連動仕様（変更一覧の一本化・保存競合・不変条件の意味論化）

> **このファイルの役割**: エディタパネル（`WorkingTreeService` / `EditorPanelViewModel`）が
> git のワーキングツリーをどう読み書きするかの決定——変更一覧の粒度・保存競合時の挙動・
> 更新タイミング・対象プロジェクトの決定、および「読み取り操作は git の状態を変えない」という
> 不変条件をテストでどう表現するかの決定。
> **書かないもの**: PTY 側の fd 継承対策（→ [ADR 0151](0151-pty-spawn-fd-hygiene.md)）、
> 現行のコンポーネント構成（→ [architecture/terminal-editor-panels.md](../architecture/terminal-editor-panels.md)）。

## 文脈

Superset・Conductor 等の競合ツールは stage/commit/push まで含む本格的な git 操作 UI を持つが、
phase0 の時点でスコープを「変更のレビュー・その場修正まで」に絞ることを決めていた（stage/commit/push
UI はスコープ外）。この前提のもとで、変更一覧の粒度（staged と未ステージを分けるか）・保存時の
競合検出・対象プロジェクトの決め方をゲート①で確定した。

## 決定

1. **変更一覧は staged / 未ステージ / 未追跡を区別せず「HEAD からの変更」として一本化する。**
   `WorkingTreeService.changes()` は `git status --porcelain=v1 -z --untracked-files=all` を
   1 回読み、`kind`（`modified` / `added` / `deleted` / `untracked` / `renamed`）付きの一覧を
   ステージ状態と無関係にリポジトリルート相対パス昇順で返す。stage/commit UI がない以上、
   ユーザーにとって staged かどうかは意味を持たないため。
2. **保存競合は「警告後にユーザー版で上書き」。** `WorkingTreeService.save(path:content:expectedDiskContent:)`
   は、選択（ロード）時点のディスク内容 `expectedDiskContent` が現在のディスク内容と一致する
   場合のみ書き込み `.saved` を返す。不一致なら**書き込まずに** `.conflict` を返す。
   `EditorPanelViewModel` はこれを受けて `SaveResult.conflictDetected` を返し、View がアラートを出す。
   ユーザーが `overwrite()` を選ぶと `expectedDiskContent: nil` で無条件上書きする。
   競合判定の基準は「draft」ではなく「選択時点でロードしたディスク内容」——draft を基準にすると
   自分自身の編集が常に競合として検出されてしまうため。
3. **エディタの対象は選択中セッションのプロジェクト。** 未選択時は `EditorPanelViewModel.ListState.noProject`
   の空状態。対象が git リポジトリでなければ `.notARepository` の空状態。
4. **一覧・diff の更新は手動 Refresh のみ。** ファイル監視による自動リロードは実装しない
   （phase0 スコープ外）。`EditorPanelView` の Refresh ボタンが `viewModel.refresh()` を呼ぶ。

## 不変条件の意味論化（契約欠陥の是正）

task-2 の当初契約は「`save` 以外のいかなる操作も git の状態を変更しない」を**バイト単位**の
不変条件として暗黙に要求していたが、これは達成不能だった。git は `status`/`diff` のような読み取り
コマンドの実行時にも `.git/index` の stat キャッシュを日和見的に書き換えるため、リポジトリ内容や
`git status --porcelain` の出力・`git write-tree` の結果は不変でも、`.git/index` のバイト列は
不変にならない（task-2 の 3 回目差し戻しで実測・PM 裁定により契約を修正）。

**確定した不変条件**: 読み取り操作（`isGitRepository()` / `changes()` / `detail(for:)` /
`fileContents(_:)`）は git の**意味論的状態**（追跡内容・ステージ状態・HEAD・
`git status --porcelain` の出力・`git write-tree` の結果）を変更しない。`.git/index` のバイト単位の
不変性はテストの対象にしない。`git add` 等の状態変更コマンドは一切発行しない
（`WorkingTreeService.runGit` は状態変更系のサブコマンドを呼ばない）。

併せて、全 git 呼び出しに `--no-optional-locks` を付与し（`WorkingTreeService.runGit`）、
読み取り操作が index ロックの取得で他の git プロセスと衝突しないようにしている。

## 結果

- `runGit` は `Process` + 2 本の `Pipe`（stdout/stderr）を**並行排出**してから
  `waitUntilExit()` する（[ADR 0151](0151-pty-spawn-fd-hygiene.md) と隣接する教訓: 逐次排出だと
  stderr が 64KiB を超えるだけで恒久デッドロックする実バグが task-2 レビューで発見・修正された）。
- `save` は symlink を解決してから `Data.write(to:options:.atomic)` する。symlink 自体を
  差し替えず（symlink 保持）、かつ atomic 書き込み（クラッシュ時に空ファイルになる窓が無い）を
  両立する。
- 回帰保護: `AcceptanceWorkingTreeTests`（task-2）・`WorkingTreeServiceWhiteboxTests`
  （リネーム・非 ASCII パス・空リポジトリ・巨大 stderr・symlink 保存 等）・
  `AcceptanceEditorPanelVMTests`（task-4）・`EditorPanelVMWhiteboxTests`。
