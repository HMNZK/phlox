---
status: active
last-verified: 2026-10-15
---

# ターミナル／エディタパネルの現行構成

> **役割**: ターミナルと変更タブの所有者・表示・終了の現行構造。決定の理由は ADR 0187・0193・0195・0196、要件は `specs/bottom-panel-shell-files-git.md`。旧ドロワーは廃止済み。

## コンポーネント

### ユーザー用シェルの選択（ADR 0193）

`UserShellSettings`（DashboardFeature/UserTerminal）が `/etc/shells` を読み、コメント・空行・重複・実行不可の項目を除く。任意パスは絶対パスの実行可能なファイルであることを保存前に検証する。保存先は `.phloxDefaults()` の `terminal.shellPath`（空文字はシステムの既定）。設定の「一般 › ターミナル › シェル」は既存の設定行を使う。

`PhloxApp.makeTerminalPanelSession` は解決関数をコントローラへ渡す。`UserTerminalController.startSession` は起動のたびに解決して `shellResolution`（実際のパス・代替した設定パス）を保持し、`SHELL` を実際のパスにする。代替時の注意を出力ストリームの先頭に流してから PTY 出力を購読する。新規起動・再起動だけに反映し、実行中のシェルやエージェントの起動には触れない。下部パネルも同じ解決関数・結果を利用し、代替したパスの注意を見出しに次の再起動まで出す。

解決結果には、有効な設定シェルを選んだ場合の代替先も保持する。存在確認後に設定シェルが消えた場合は、PTY 起動の ENOENT とそのパスの不存在を確認して代替先で一度だけ再試行する。他のエラーと代替先の失敗は伝播する。初回の注意は最初の行に出し、再起動では注意の前にも CRLF を入れ、既存の出力を消さず独立した行にする。注意のテストは有限時間の出力収集と、失敗時にも走る終了処理を使う。

| 層 | 型 / 関数（パッケージ・ファイル） | 役割 |
|---|---|---|
| ルーティング | ウィンドウごとの `BottomPanelState` / `openChildTab` | 下部パネル専用の開閉・入力先状態と既存の子タブ選択 |
| PTY ライフサイクル | `UserTerminalController`（DashboardFeature/UserTerminal、`@MainActor`） | 渡された作業フォルダ（プロジェクトのフォルダ）を cwd に `PTYManagerProtocol` 経由でシェルを起動・保持・shutdown。多重 spawn 防止・自然終了検知・`spawnGeneration` による購読者の世代分離・`requestedSize` によるサイズ保留（起動前 resize の反映） |
| 表示とシェルの束ね | `TerminalPanelSession`（DashboardFeature/UserTerminal/TerminalPanelView.swift） | `UserTerminalController` と `TerminalUI.TerminalCoordinator` を束ねる。ターミナル子タブごとと、下部パネルのプロジェクトごとに1つ |
| パネル寿命の所有者 | `ProjectTerminalStore`（DashboardFeature/UserTerminal/ProjectTerminalStore.swift、`@MainActor`。`PhloxApp` の `@State` が 1 つ持つ） | `TerminalTabID` → （`TerminalPanelSession`・プロジェクト ID・作業フォルダ）の置き場。`terminal(for:projectID:workingDirectory:)` が初めて開くときだけ作る（フォルダが変わっていたら旧い場所のシェルを止めて作り直す）。子タブとは別にプロジェクトごとの下部シェルを保持する。`close(_:)` は子タブだけ、`closeProject(_:)`・`shutdownAll()` は下部シェルも止める |
| ターミナル表示 | `TerminalPanelView`（同ファイル） | `TerminalCoordinator` を `TerminalUI.TerminalView`（SwiftTerm 表示）へ橋渡しする、容器非依存の View |
| git 読み書き | `WorkingTreeService`（DashboardFeature/WorkingTree、`actor`） | `/usr/bin/git`（`--no-optional-locks` 付き）をラップし、`isGitRepository()` / `changes()` / `detail(for:)` / `fileContents(_:)` / `save(path:content:expectedDiskContent:)` を提供 |
| git 値型 | `WorkingTreeChange` / `WorkingTreeDetail` / `WorkingTreeSaveOutcome`（DashboardFeature/WorkingTree/WorkingTreeTypes.swift） | 変更エントリ（path/kind/isBinary）・詳細（diff/untrackedContent/binary）・保存結果（saved/conflict） |
| エディタ VM | `EditorPanelViewModel`（DashboardFeature/Editor、`@MainActor @Observable`） | `listState`（noProject/notARepository/ready）・`changes`・`selectedPath`・`detail`・`draft`・`isDirty` を保持し、`refresh()` / `select(_:)` / `save()` / `overwrite()` を提供。競合検出は「選択時点でロードしたディスク内容」を基準にする |
| エディタ内部レイアウト | `EditorPanelLayout`（DashboardFeature/Editor/EditorPanelView.swift、SwiftUI 非依存の純粋 enum） | 表示幅から `.split`（変更リスト＋詳細を左右分割。内在最小幅 541pt）／`.stacked`（縦積み）を決める |
| エディタ表示 | `EditorPanelView`（同ファイル） | 変更一覧・diff/内容プレビュー（`ChatCodeHighlighter.highlight` で構文ハイライト。SessionFeature の `ChatCodeBlock.swift` を共有）・`TextEditor` での編集・保存・競合アラートを持つ、容器非依存の View |
| PTY spawn 起動 | `makeTerminalPanelSession(environment:workingDirectory:)`（App/PhloxApp.swift） | `UserTerminalController` にプロジェクトのフォルダと `UserShellSettings.resolve` を渡す（`HOME` はホーム）。`ProjectTerminalStore` の factory として渡し、`AppDelegate.sessionUserTerminals` へも同じ置き場を渡す |
| 終了処理 | `AppDelegate`（App/AppDelegate.swift、extension） | `applicationShouldTerminate` から `shutdownUserTerminal()`（`ProjectTerminalStore.shutdownAll()`）→ `PTYManager.terminateAllAndWait` を待つ Task と、全チャットセッションの `flushTranscriptNow()` を待つ Task を並行実行し、両方の完了後に reply する（[ADR 0110](../adr/0110-midturn-flush-and-termination-race.md)・[ADR 0149](../adr/0149-user-terminal-lifecycle.md)） |
| fd 衛生 | `Posix.spawn`（PTYKit/Sources/PTYKit/Posix.swift） | raw は `POSIX_SPAWN_CLOEXEC_DEFAULT`（[ADR 0151](../adr/0151-pty-spawn-fd-hygiene.md)）、interactive は C の子で標準入出力と errno 通知用 pipe 以外を閉じる（[ADR 0201](../adr/0201-interactive-pty-controlling-terminal.md)） |

## データフロー（ターミナル）

1. `PhloxApp` が起動時に `ProjectTerminalStore` を 1 つ生成して `@State` として保持する（`AppDelegate.sessionUserTerminals` にも共有）。
2. 下段のタブでターミナルを開く（`ProjectTab.terminal(TerminalTabID)`）と、`SessionTabsContainer` が `terminals.terminal(for:projectID:workingDirectory:)` で `TerminalPanelSession` を取り出す（無ければ作る。作業フォルダはそのプロジェクトのフォルダ）。
3. `TerminalPanelSession.init` が `TerminalCoordinator.onInput` / `.onResize` を `UserTerminalController.send(_:)` / `.resize(cols:rows:)` に配線し、`makeOutputStream()` を継続的に消費して `TerminalCoordinator.feed(_:)` へ流す（表示器が閉じていても購読は継続）。
4. `TerminalPanelView.task` が初回表示・自然終了後の再表示のときに `ensureStarted()` を呼び、`UserTerminalController.ensureStarted()` が未起動なら作業フォルダでシェルを spawn する。
5. タブを切り替えてもシェルは残る。タブを閉じる（実行中のコマンドがあれば確認）と `ProjectTerminalStore.close(_:)`、プロジェクトを削除すると `closeProject(_:)`、アプリ終了で `shutdownAll()` がシェルを止める。ターミナルのタブは保存しない（次の起動では開き直さない）。

### ユーザー用 PTY の起動（ADR 0201）

ユーザー用端末の環境は `TerminalEnvironment.userShell` で組み立て、`LANG` はエージェント用と共通の規則（アプリ環境の値、無ければ `en_US.UTF-8`）で渡す。Ctrl-C の判定は `sleep 20` の実行中に Ctrl-C を送ってから5秒以内にプロンプトへ戻り、次の行の `echo AFTER` が返ることとする。zsh は同じ行の残りのコマンドを取り消すため、それを成功条件にしない。

子タブと下部パネルは共通の `PTYManager(terminalMode: .interactive)` を使う。`Posix.spawn` は C の `cpty_spawn_interactive` へ渡し、fork 後の子で `setsid` と `TIOCSCTTY` により slave を制御端末にしてから標準入出力を複製し、指定の cwd・環境でシェルを exec する。zsh の前景にも Ctrl-C とサイズ変更の SIGWINCH が届く。interactive の resize は `TIOCSWINSZ` の前景グループ通知を使い、起動したシェルへの明示送信はしない。

親で fork 直前に fd 一覧と soft limit から閉鎖上限を求め、子は `close` だけで不要 fd を閉じる。fork 後に fd 列挙・メモリ確保・Swift の処理はしない。子の失敗は3以上へ移した close-on-exec の pipe で errno を返し、親が回収して `spawnFailed` にする。既定の `.raw` は従来の `posix_spawn` と起動したプロセスへの明示 SIGWINCH を維持する。

### 下部パネル（ADR 0196）

ユーザー用シェルの PTY は `PTYManager(terminalMode: .interactive)` で生成し、OS 標準の端末設定（echo・icanon・制御文字）で開始する（ADR 0198）。子タブと下部パネルは同じ工場を使う。エージェントに渡す `AppEnvironment.pty` は従来の raw 設定を維持し、ユーザー用には渡さない。

設定のシェル行は Picker の標準ラベル「シェル」を使い、追加の `.accessibilityLabel` による重複を避ける（ADR 0199）。`PTYTerminalModeTests` は `PTYManager()` の既定で実際に `stty -a` を起動し、`-echo`・`-icanon` を検査する。

Picker の AXLabel は画面外の同じ構成で手元確認し、追加ラベルを外す前の「シェル, シェル」が「シェル」になることを確認した。この調査用の検査はリポジトリのテストには未登録。設定画面全体と VoiceOver の音声は未検証。

見出しの代替シェル注意は1行・末尾省略とし、幅の優先度を下げる。再起動・閉じる操作は固定サイズと高い優先度で幅を確保し、900pt・英語でも見出し内に収める。注意の全文は既存のツールチップに残す。

画像用ウィンドウの生成は `DesignSnapshotRenderTests.makeSnapshotWindow` にまとめ、撮影と `BottomPanelTests` で同じ処理を呼ぶ。テストは標準タイトルバーと `bottom-panel-toggle` の存在を確認し、900pt・英語・注意表示では再起動と閉じる操作の矩形が見出し内に収まることを検査する。

`BottomPanelContainer` は中央列のタブ列より下にだけ配置する。初めて開くと `ProjectTerminalStore.bottomTerminal` が同じ工場からセッションを作り、初回だけ `ensureStarted` を呼ぶ。閉じても表示器・出力購読・scrollback とシェルを保持する。プロジェクトごとに `TerminalPanelSession` と表示器は1つ。複数ウィンドウでは子タブと同じ表示器の再アタッチを使い、ウィンドウ別の表示器・共有エンジンは持たない（ADR 0197）。終了後の開き直しでは起動しない。再起動は見出しと表示メニューから明示的に行う。

`IMETerminalView` は端末をアクセシビリティのテキスト領域として公開し、要求時に見えている行だけを値として返す。見出しはシェル・作業フォルダ・キー入力の状態を日英で読み上げる。端末内の起動・入力・サイズ変更の失敗案内は `AppLocalizedString` を通す。

フォーカス通知の登録・解除は `TerminalView` の mount が持つ。表示器を実際に保持するコンテナだけが通知先を更新・解除し、別ウィンドウの旧パネルが消えても現在の通知を解除しない。所有者が外れて残った mount へ再アタッチする際も通知先を更新する。可視行の空セルは `visibleText()` と同じ `TerminalDump.displayCharacter` で空白へ変換し、全角文字の後続セルは引き続き除く。

下部パネルの未保存時の既定高さはモックの280pt。終了帯の左右余白は内側の12pt、上端は区切り線トークンを使い、見出しの中点と文字を別要素にして間隔を揃える。Return による再起動は提供していないので、ボタンに↩を表示しない。文字サイズは子タブと同じ設定経路を維持する。画像用には文字サイズを13ptに固定して実値を検査し、代替シェルの注意の出力を待つ。全体画像は標準タイトルバーを含む画面外ウィンドウを描き、左右分割には会話の一覧を渡す。ADR 0197 の単一表示器の決定は置き換えないため、新しいADRは追加しない。

端末のプレーンテキスト抽出も SwiftTerm の行変換を使い、全角文字の後続セルを文字間の空白にしない。明示的な空白・改行と、既存のソフトラップ連結の選択は維持する。単一表示器の検査では既存の mount 所有権に従う再アタッチを確認する。別ウィンドウの有効な mount が所有している間、失効した旧 mount は表示器を奪い返さない。再表示の検査は所有中のパネルを閉じ、表示器の解放を待ってから元のウィンドウで開く。色は同じ色空間で比較する。待機失敗には呼び出し行を残し、どの状態遷移を待てなかったか区別する。ADR 0197 の決定は変更しない。

開閉状態は各 `DashboardView` の `BottomPanelState`（表示メニューへは `FocusedValues` で渡す）、高さは専用の UserDefaults キー。開く直前の入力先は弱参照で記憶し、閉じると同じウィンドウに残る入力先だけへ戻す。グリッドでは選択中セッションのプロジェクトを優先する。端末の入力先変更は見出しの文字の強調と文字サイズ操作の対象に反映し、外側の枠は描かない（ADR 0202）。高さの境界は上下向きの `ResizeGripView` を使い、ドラッグ終了時に確定する。上下キー・VoiceOver の増減を維持し、ダブルクリックで既定高へ戻す。開閉キーは ⌘J（ADR 0200）。⌘ 付きのキーは AppKit が端末のキー処理より前にメニューへ渡すので、端末側に特別な処理は無い。

下部シェルの `hasStarted` は初回起動の成功後に立つ。表示メニューの再起動はその値を条件とし、閉じていてもパネルを開く。起動中は見出しの再起動を無効にし、失敗理由は表示に残す。

## データフロー（エディタ）

右サイドバーの Git タブも `EditorPanelCoordinator.viewModel` の一覧・取得状態・ブランチ・行数を参照する（ADR 0195）。一覧の読み直しは共有モデルだけが行い、更新中の要求はまとめて追従する。Git 側は選択パスと読み取り専用の差分を別に持ち、変更タブの選択・下書きを変更しない。Git のダブルクリック／Return／メニューは `AppRouter.openChildTab(.changes)` と既存の `select(_:)` に渡す。コミット欄は変更タブの既存欄を表示し、入力フォーカスを要求する。

更新は Git タブ表示時、対象プロジェクトに属するセッションの `lastTurnCompletedAt` の変化、`.fileTreeFileSaved`（保存と作成・名前変更・削除）、`NSApplication.didBecomeActiveNotification`、手動更新を共有モデルへ渡す。保存・ツリー操作通知は共有モデル自身が購読し、DashboardView はツリーの更新だけを行う。対象外のプロジェクトのイベントは無視する。新着は直前の成功した一覧にないパスだけとし、初回と失敗後の再試行で全行を新着にしない。差分はハンク見出しを含め60行で切り、300pt以上で行番号を出す。未追跡テキストは追加行、バイナリは専用表示。失敗理由と管理外を区別する。

1. `DashboardView.updateEditorPanel()` は `EditorPanelCoordinator.update(project:workspaces:)` に対象を渡す。
   `.task(id: editorPanel.target)` が `resolve(workspaces:)` を呼び、対象プロジェクトが変わったら
   `WorkingTreeService(repositoryRoot:)` を注入した新しい `EditorPanelViewModel` を作る（未選択時は `service: nil`）。
2. `EditorPanelView` は表示幅（`GeometryReader`）を `EditorPanelLayout.mode(forWidth:)` に通し、
   `.split`（`HSplitView`）／`.stacked`（`VSplitView`）を切り替えて変更一覧と詳細ペインを配置する。
一覧取得失敗・Git 管理外への変化でも、未保存下書きがある場合は、その選択と下書きを保持する。保存通知は通知元と共有 Git ルートが包含関係にある場合に更新するため、リポジトリ内の下位フォルダをプロジェクトとして開いた場合も対象にする。未追跡ファイルの行数は最大1MBまでの読み取りで求め、上限超過・読み取り不能・ルート外 symlink ではその行の行数だけ省く。追跡ファイルの行数とバイナリ判定は同じ numstat の結果を使う。Git の通常取得・再試行は同じ処理を通り、選択パス・取得世代・キャンセルを確認してから差分を反映する。本文中の `+++` / `---` はハンク開始後なら差分行として残す。

3. Refresh ボタン → `viewModel.refresh()` → `WorkingTreeService.snapshot()`。ファイル選択 →
   `viewModel.select(_:)` → `WorkingTreeService.detail(for:)` + `fileContents(_:)`（追跡ファイルの
   場合、diff 表示と同時に本文を読み込んで `draft` へロードする）。
   編集可否は `WorkingTreeText.maximumEditableFileSize`（5 MB）、内容の閲覧可否は `maximumReadableFileSize`（20 MB）を共有する。BOM込みで判定し、5 MB超は保存・dirtyを止め、既存のファイルタブへ閲覧を渡す。20 MB超は変更プレビューのみ。差分の色付けと500行単位のプレビューは維持し、「内容」は1 MB超を本文色とする。外部変更は再選択で読み直す。
4. 保存 → `viewModel.save()` → `WorkingTreeService.save(path:content:expectedDiskContent:)`。
   `.conflict` が返ると View がアラートを出し、ユーザーが選べば `viewModel.overwrite()` で
   `expectedDiskContent: nil` の無条件上書きを行う。

### Git タブの更新接続と表示の補正

保存通知の対象は `WorkingTreeService` が現在解決する Git ルートで判定する。管理外で開いた後に `git init` し、手動更新で復帰した場合も保存に追従する。ターン終了日時の収集と更新の接続は `GitTabPolicy` の小さな関数にまとめ、DashboardView の監視から呼ぶ。対象プロジェクトの日時が変わった場合だけ共有モデルを更新する。

差分は `diff --git` ごとにハンク状態を戻し、次のファイルの `---`／`+++` を本文に含めない。Git 側の行背景は共有色トークンの不透明度を調整し、本文の左余白は既存の最小間隔を加える。管理外見出しは通常書体・副文字色、パスは `~` 表記、管理外と失敗の本文タイトルは主文字色。失敗説明の追加行間は `DSSpacing.xs` とする。既存の決定の変更はないため、新しい ADR は追加しない。

## テスト

| ファイル | 固定している性質 |
|---|---|
| `TerminalEnvironmentTests` | ユーザー用端末の LANG の既定値 `en_US.UTF-8`、アプリ環境の LANG の優先（空文字も従来のエージェント用規則に従って維持）、HOME・PATH・TERM の保持 |
| `UserShellSettingsTests` | `/etc/shells` の読み取り・候補の整理・実行可能性・無効パスの保存拒否・システム既定への代替・存在確認後の消失・再試行回数とエラー伝播・再起動時の反映・注意の出力順と旧プロンプトとの分離・出力待機の期限と失敗時の終了処理・実際の bash の `$0` と `$SHELL` |
| `AcceptanceUserTerminalTests` / `UserTerminalControllerWhiteboxTests` | PTY 起動の冪等性・入出力・自然終了→再起動・世代分離・drain 待ち・shutdown 冪等 |
| `AcceptanceWorkingTreeTests` / `WorkingTreeServiceWhiteboxTests` | 変更一覧・diff・保存・競合検出・リネーム/非 ASCII パス・巨大 stderr 耐性 |
| `BottomPanelTests` / `BottomPanelShortcutTests`（TerminalUI） | 高さ・保存・開閉・入力先復帰・プロジェクト所有・初回起動・再起動条件・メニュー優先・別窓を閉じた後と自動再アタッチ後の通知先・共通設定の文字サイズ・画像用の標準タイトルバー |
| `TerminalCoordinatorVisibleTextTests`（TerminalUI） | 行内の空セル・タブ移動は空白、全角文字の後続セルは除外し、VoiceOver の値にNULを含めない |
| `TerminalPanelViewWhiteboxTests` | パネルの表示器が共有コントローラを保持し、入出力を `TerminalCoordinator` へ接続すること |
| `EditorPanelVMTests` | VM の一覧/選択/編集/保存/競合フロー |
| `GitInspectorTests` / `GitInspectorServiceTests` | 複数ファイル差分のヘッダー除外・管理外から Git 管理へ復帰した後のファイルタブ保存による共有一覧更新（ルートと子フォルダ）・実際のターン終了日時から共有一覧更新への接続・別プロジェクトと同じ日時の更新抑止 |
| `PanelIntegrationWhiteboxTests` | 左右分割/縦積みの切替幅・変更種別ごとの SF Symbol |
| `PosixSpawnCloexecTests`（PTYKit） | spawn した子が無関係な fd を継承しないこと |
| `PTYTerminalModeTests`（PTYKit） | ユーザー用の echo・icanon・制御文字、従来のエージェント用 raw 設定、実 bash の stty と Return 前の入力エコー |
| `InteractiveSpawnTests`（PTYKit） | zsh/bash の前景 TPGID・Ctrl-C・前景へのサイズ変更、標準 fd 欠落時の ENOENT・子回収、高番号 fd 非継承、起動失敗反復後の fd 数・子回収、cwd・環境、既定 raw のサイズ変更通知 |
| `FileTreeInteractionTests` | 右クリック／Return から入力欄の表示・フォーカス・拡張子前の選択・確定までを通し、ファイル／フォルダ内のタブと未保存本文・Undo の同一性を保つ |
| `FocusBorderRenderTests` | 画面外のウィンドウでファイルツリー・Git 一覧・Git 差分・下部端末へ入力先を移し、左右の外周画素を検査する。アプリと窓のアクティブ状態だけをテストプロセス内で代替し、入力先は実際の SwiftUI フォーカス要素／端末の first responder から確認する。行クリックと共通の AX 押下処理→ポインタ退出→ファイル／フォルダの選択の塗り→Return の名前変更対象も検査する。画像保存は `PHLOX_DESIGN_SNAPSHOTS=1` で指定し、WS の `worktree-start` 画像と同じ実行で出力できる |
| `ToolbarInteractionTests` | 標準タイトルバーで日英の開閉ボタンの名前が独立し、実際の AX 操作後に選択状態が変わる |
