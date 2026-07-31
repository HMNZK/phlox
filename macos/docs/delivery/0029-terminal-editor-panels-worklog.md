---
status: completed
last-verified: 2026-08-01
---

# 0029: ターミナルパネル・エディタパネルの追加（terminal-editor run）

> agentic-loop run（backend=codex、途中から一部 Claude implementer へ切替）。ブランチ
> `feature/terminal-editor`。独立レビューは Claude `persona-reviewer`（実装が Codex の間は別モデル、
> task-5 終盤の一部修正のみ実装者・レビュアーが同一モデルになった区間あり、下記参照）。

## 何をしたか

Phlox にユーザー操作用のターミナルパネル（⌘⌥T）とレビュー特化エディタパネル（⌘⌥E）を追加した。
6 タスクに分解し、task-0 で凍結受け入れテスト用のスタブを作り、task-1〜4 を並行実装、task-5 で
容器を確定容器へ統合した。

| タスク | 内容 | レビュー往復 |
|---|---|---|
| task-0 | 凍結受け入れテスト5本がコンパイルできる公開面スタブ＋`AppRouter` のパネルフラグ本実装 | r1 needs_changes → fix1 pass |
| task-1 | `UserTerminalController`（PTY ライフサイクル。多重 spawn 防止・自然終了検知・世代分離） | r1〜r3 needs_changes → r4 pass（収束モード） |
| task-2 | `WorkingTreeService`（git 読み書き） | r1〜r4 needs_changes → r5 pass（収束モード） |
| task-3 | ターミナルパネル容器プロトタイプ（ドロワー／独立ウィンドウ）＋⌘⌥T | r1・r2 needs_changes → r3 pass（収束モード） |
| task-4 | `EditorPanelViewModel`/`EditorPanelView` | r1 needs_changes → r2 pass（収束モード） |
| task-5 | 確定容器への統合・プロトタイプ撤去・⌘⌥E・shutdown 配線・XCUITest | r1・r2 needs_changes → r3 pass（収束モード・限定範囲） |

決定は ADR へ蒸留した: [0148](../adr/0148-terminal-editor-panel-container-drawer.md)（容器＝ドロワー）／
[0149](../adr/0149-user-terminal-lifecycle.md)（ユーザーターミナルのライフサイクル）／
[0150](../adr/0150-editor-panel-git-semantics.md)（git 連動仕様・不変条件の意味論化）／
[0151](../adr/0151-pty-spawn-fd-hygiene.md)（PTY spawn の fd 衛生）。
現行構成は [architecture/terminal-editor-panels.md](../architecture/terminal-editor-panels.md)、
要件は [specs/terminal-editor-panels.md](../specs/terminal-editor-panels.md) に反映済み。

## ゲート①・②の決定

- **ゲート①（2026-07-31、問題設定承認時）**: ターミナルはセッション無関係・cwd はホーム固定／
  シェルは閉じても保持・アプリ終了時のみ後始末／保存競合は警告後ユーザー版上書き／変更一覧は
  staged 区別なし一本化／エディタ対象は選択中セッションのプロジェクト／パネル容器は
  「最小プロトタイプを見てから決める」方針（フェーズ1冒頭にプロトタイプタスク task-3 を配置）。
- **ゲート②（2026-07-31、task-3 完了後）**: 容器は両パネルとも**ドロワー**に確定、独立ウィンドウ
  方式は撤去。追加要件2件（①パネル幅のドラッグ調整 ②トップバーのパネル幅非依存）を task-5 の
  契約へ反映。

## レビュー運用（収束モード）の採用

task-1・task-2 で差し戻しが重なったことを受け、2026-07-31 にユーザー裁定で「収束モード」を採用した:
新規タスクの初回レビューはフル8次元、**差し戻し後の再レビューは「修正箇所＋修正が壊しうる周辺」に
限定**する。task-1 r4・task-2 r5・task-3 r3・task-4 r2・task-5 r2/r3 はこの限定範囲で実施している
（各レビューファイルの「掃いた次元」節に明記）。

## 契約欠陥の是正（run 中に発見・修正）

- **task-2 の不変条件「バイト単位不変」は達成不能だった**。git は読み取りコマンド実行時にも
  `.git/index` の stat キャッシュを日和見更新するため。3 回目の差し戻しでユーザー裁定により
  「意味論的不変（porcelain 出力・write-tree 結果が不変）」へ契約を修正して続行（[ADR 0150](../adr/0150-editor-panel-git-semantics.md)）。
- **task-3 の凍結テストがゲート②の撤去契約と矛盾**していた（プロトタイプ隔離ファイルの存在検査を
  凍結していたが、ゲート②でプロトタイプ撤去が確定した）。PM の契約設計ミスと裁定し、当該テスト
  1 件を撤去して再凍結（`.claude/verify.sh` の `BASELINE` を再凍結コミットへ更新）。

## flaky として観測された事象

- **1 回目（task-3 マージ後検証）**: `UserTerminalControllerWhiteboxTests` の 1 件（旧世代出力の
  混入防止・ポーリング待ち）が高負荷下でタイムアウト。単独 3 連続 pass・変更内容（Editor 系）と
  無関係だったため、11 日稼働していた孤児 `swift-build` プロセスによるビルド遅延が原因の一過性と
  判定して続行。
- **2 回目（task-5、パッケージ全数を並列実行したときのみ再現）**: 同系統のテストが 13 回中 4 回
  タイムアウト。今回は一過性と切り捨てず原因追及を task-5 へ委譲した結果、
  **`WorkingTreeService.runGit` の pipe を、同時に spawn されたユーザーターミナルの子シェルが
  fd 継承で握ってしまい EOF を返さない**という production の実バグ（[ADR 0151](../adr/0151-pty-spawn-fd-hygiene.md)）
  と判明。`POSIX_SPAWN_CLOEXEC_DEFAULT` で根本修正し、修正後は同一条件で 13 回連続 green
  （レビュー r3 で確認）。
  - なお、この修正過程で実装者側の開示「`UserTerminalController.swift` を修正した」という説明が
    実体（テストダブル側への `finish: true` 送出のみ）と食い違っていたことが r2 レビューで
    指摘されている（成果物自体は契約に適合し、レビューが裏取り済み）。

**この 2 件はいずれもブランチの変更（PTY とエディタの同居構成、または高負荷ビルド環境）に
起因が特定できたもの**。これとは別に、フェーズ4の全数実行では当ブランチ無関係の既存テスト
3 件（`SessionViewModelCharacterizationTests` 1 件・`waitUntilDone_*` 2 件）が負荷依存で
タイムアウト失敗した（下記「検証」節参照。テスト・対象実装とも当ブランチで差分ゼロ、
単独実行では安定 pass）。

## 検証

- `swift test --package-path macos/Packages/DashboardFeature` / `SessionFeature` / `PTYKit`:
  各レビューラウンドでレビュアー自身が実走し green を確認済み（例: task-5 r1 時点で
  DashboardFeature 1555 tests / 149 suites、SessionFeature 745 tests、いずれも 0 failures。
  最終ラウンドでは対象フィルタでの連続実行を含めて確認。詳細は各 `docs/agent-output/review-task-*.md`）。
- `verify.sh`（全数実行＋凍結テスト無改変チェック）: フェーズ4で 2 回フル実行（1561 tests /
  150 suites）。凍結テスト無改変チェックは pass。テストは 2 回とも exit 1 だが、失敗は全て
  タイムアウト型で、**失敗した 4 テストすべてが単独実行では各 2 回連続 pass**（計 8 回実走）。
  内訳: `SessionViewModelCharacterizationTests` 1 件と `waitUntilDone_*` 2 件は当ブランチで
  テスト・対象実装とも差分ゼロの既存テスト（負荷依存の既存 flaky）、
  `TerminalPanelViewWhiteboxTests` 1 件は本 run 新設のテストで並列全数実行時のみタイムアウト
  （改善候補として下記積み残しに記載）。実退行は検出されていない。
- `xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug build`:
  task-5 レビュー時点（別 derivedDataPath）で BUILD SUCCEEDED を確認済み。

## フェーズ4の実機ビジョンテスト（2026-08-01、Debug ビルド実機・スクリーンショット目視）

task-5 最終レビュー（r3）が「フェーズ4で要実施」と挙げた実機確認項目のうち、以下を Debug
ビルド（`com.phlox.Phlox.debug`）上でアクセシビリティ API＋スクリーンショット目視により実施した:

- **⌘⌥T ターミナル**: 開閉トグル、実シェル（zsh）のプロンプト表示、コマンド実行と出力表示
  （`echo VT-$((6*7))` → `VT-42`）、閉→再開でシェルと出力履歴が保持されること（ゲート①仕様）を確認。
- **⌘⌥E エディタ**: 開閉トグル、未コミット変更の一覧表示（Refresh）、ファイル選択→diff 表示
  （追記行が `+` で描画）、Edit 欄での本文編集→保存が**ディスクへ実際に書き込まれること**
  （`tail` で実測）、保存内容が diff へ反映されることを確認。
- **`.stacked` レイアウト**: ドロワー幅約 370-420pt でエディタが上下積み表示になり、一覧選択・
  diff・編集・保存の一連の操作が成立することを確認。
- **両パネル同時表示**: ターミナル上段・エディタ下段の同時表示で、下段に不要な空白が出ない
  ことを目視確認。
- **トップバー独立**: 全スクリーンショットを通じ、Usage チップがパネルの開閉・状態変化で
  移動・縮小しないことを確認。
- **保存後の diff 更新**: 保存成功後に一覧・diff が自動更新されることをコード
  （`EditorPanelViewModel.reloadAfterSaving`: `refresh()`＋`select(path)`）と AX 読み取りの両方で
  確認（外部リロード起因の競合表示のみ手動 Refresh が必要）。

## 未実施・積み残し

1. **分割線の実ドラッグ**——境界でカーソルが列リサイズ形に変わるか、境界右側 10pt でも掴めるか、
   狭める向きのドラッグでゴースト線が見えるか（ADR 0136 §3 の z 順序制約と、掴みしろが
   ターミナルの NSView に食われないかというリスク）。合成イベントでは実ユーザードラッグを完全に
   再現できないため、ユーザーの実操作が最終ゲート（凍結テスト・幅永続化のユニットテストは green）。
2. `PanelUITests`（XCUITest）の実走（verify.sh は swift test のみで XCUITest を含まない）。
3. 実アプリでの `.pty` タイル退行チェック（ADR 0151 関連）: `POSIX_SPAWN_CLOEXEC_DEFAULT` 導入後の
   Claude/Codex/Cursor CLI の TUI 描画・入力・終了検知。ビジョンテスト中に Debug 実機でチャット
   バックエンドのエージェントセッション（ツール実行・出力表示）が動作することは確認したが、
   `.pty` タイルでの CLI TUI は未確認。
4. `TerminalPanelViewWhiteboxTests` の 1 件（コントローラ保持・Coordinator 接続）が並列全数実行時
   のみタイムアウトする（単独では安定 pass）。決定論化の改善候補。
