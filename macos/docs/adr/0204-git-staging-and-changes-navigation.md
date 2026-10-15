---
status: accepted
last-verified: 2026-10-15
supersedes: 0169-editor-panel-git-write-operations.md（選択パスのコミットと配置）、0171-editor-panel-workflow-status-disclosure.md（配置と折りたたみ）、0195-inspector-git-shared-working-tree.md（Git 内差分）
---

# ADR 0204: Git タブにステージと書き込みを集約し、差分は変更タブで開く

## 文脈

GW-1〜6 により、チェックしたパスの作業ツリーを直接コミットする方式から、Git の index に置いた内容をコミットする方式へ変更する。右サイドバー内の差分と変更タブの一覧は二重になる。

## 決定

- 既存の `GitCommitPanel` と `EditorPanelViewModel` を Git タブ上部へ移す。ブランチ・更新・1〜5行のメッセージ・常に主のコミット・先行数付きプッシュ・PR・理由を固定する。失敗は3行と詳細・閉じる操作を持ち、次の操作で消す。
- チェックボックスと `pathsSelectedForCommit` を廃止する。`GitWorkflowService` にステージ／外すを集約し、パスは literal pathspec とする。初回コミット前の外す操作は `rm --cached`、通常は `restore --staged`。コミットはパスを渡さず index だけを使い、失敗しても index を巻き戻さない。identity・署名・hooks は変更しない。
- `WorkingTreeService` は読み取り専用を維持し、index と作業ツリーの変更・行数・差分を別々に取得する。部分ステージのパスは両グループに現れる。
- 区画は全体で1本のスクロールと貼り付く見出し、保存する開閉状態を持つ。前半では変更区画だけを表示する。行はホバー／選択中に行数を＋／−へ置き換える。Space と VoiceOver でも操作でき、操作後の入力先は同じグループの次の行へ進む。
- 行のクリックは必ず既存の変更子タブを開き、選択パスと出どころを渡す。重ね表示のインスペクタは既存の経路で閉じる。変更タブは1ファイルの差分／内容とファイルタブへの編集操作だけとし、未選択の案内を表示する。
- ⇧⌘C と ⌥⌘P は Git タブ表示中だけ有効とし、メニューへ接続する。

## 理由と結果

index をそのまま使えば、外部で部分ステージした内容も保てる。既存の書き込みサービス・表示モデル・タブ経路を使い、別の git 実行器や二重のコミット状態は作らない。ADR 0169 のエラー保全・設定非変更と ADR 0195 の共有取得・更新時機は維持する。

仕様: [GW と決定](../specs/git-tab-workflow-and-worktree-start.md)。検証結果は作業報告に記録し、この決定だけで実装・検証済みとは扱わない。
