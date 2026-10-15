---
status: active
last-verified: 2026-10-16
---

# ターミナル／エディタパネルの現行構成

> **役割**: ターミナルと変更タブの所有者・表示・終了の現行構造。決定の理由は ADR 0187・0193・0195・0196、要件は `specs/bottom-panel-shell-files-git.md`。旧ドロワーは廃止済み。

## コンポーネント

表示エンジンは SwiftTerm だけを使う。Ghostty は見送り、試作コードは dev に入れない（[ADR 0211](../adr/0211-decline-ghostty-user-terminal-engine.md)）。

### 端末の描画方式（ADR 0213）

ユーザー端末の `TerminalPanelSession` と、エージェント端末の `SessionSpawnService`（新規・復元）は `TerminalCoordinator` と共通の `IMETerminalView` を使い、CoreGraphics で描画する。描画方式の設定読み取りや切り替え処理は持たない。

Metal の試用は、性能上の利点が小さく、メモリ増加と文字幅・位置の不良があったため見送った。計測値・表示の不具合・再検討条件は [ADR 0213](../adr/0213-terminal-metal-renderer-trial.md) に記録する。

### SwiftTerm 変更後のテスト生成物

SwiftTerm のクラス構造を変更した際は、それを使うパッケージの古い生成物も再構築する。`macos/scripts/run-swift-tests.sh` は通常の増分ビルドを行うため、依存先と呼び出し側の生成物の不整合が残る場合がある。構造変更後は `swift package --package-path macos/Packages/<パッケージ名> clean` を TerminalUI・DashboardFeature・SessionFeature に実行してから、通常のテスト入口で検証する。ソースや期待値を変更して回避しない。

DashboardFeature の `TerminalFontAccessTests` は、パッケージ境界を越えたフォントの取得と11・13・20ptへの変更、画面外ウィンドウへの接続・切断後のサイズ保持を検査する。既存の `BottomPanelTests.twoWindowsAndContentHeight` は実際のパネル表示から設定値を検査する。2026-10-15 の signal 11 のスタックと再構築による解消の記録は [delivery 0054](../delivery/0054-swiftterm-test-artifact-mismatch.md) に置く。フォント設定・PTYKit・ADR 0212／0213 の判断は変更しない。

### 共通端末のキー入力と応答（ADR 0212）

#### 出力の配送と流量制御（ADR 0212）

大量出力の後に `65;4;1;2;6;21;22;17;28c` が入力行に残る不具合は、配送の欠落が原因だった。修正前の `PTYManager` と `UserTerminalController.makeOutputStream()` は `.bufferingNewest(2048)` で、表示が追いつかないと古いチャンクを捨てていた。SGR の途中（`ESC [ 0`）と後続の通常文字（`c`）がつながって正当な DA1 問い合わせ `CSI 0 c` になり、SwiftTerm が正しく応答していた。SwiftTerm 側で応答を抑えると正当な DA1 も壊れるため、配送側で直す。`TerminalDA1RegressionTests` が、元の生成スクリプトと同じ入力の無欠落 feed（応答ゼロ）、旧方針の破棄による DA1 の発生、実測した欠落境界を固定する。

表示が追いつくまで PTY の読み取りを止める。

- `OutputGate`（PTYKit、spawn ごと）: 未消費バイトが 1MiB に達したら read source を停止し、消費通知で 256KiB 以下になったら再開する。停止中も 100ms ごとに 1 回（最大 4KB）だけ読む。macOS の PTY は slave の最後の close で未読出力を約 0.6 秒待って捨てるため、終了直前の出力を失わないためである。停止のたびに世代を進め、古い予約は無視する。取り消しは停止を解除してから行う。読み手のタスクが取り消されたら停止をやめる（以後は捨てる）。同じ ID で置き換えるときは旧ストリームを終えてから旧ゲートを放棄する。終了時の読み切りもゲートに計上し、未消費量が上限を超えたら打ち切る。
- 消費通知（`PTYManagerProtocol.acknowledgeOutput`）は feed が戻った後に送る。`SessionViewModel` は feed 後。同じ ID で起動し直すため、旧世代の遅い通知が新ゲートの背圧を少し弱めることがある（固まりはしない）。
- `UserTerminalController.observeOutput` は MainActor の同期コールバックを登録し、全コールバックを呼び終えてから、その世代の SessionID へ通知する。コールバック内で非同期に配送してはいけない。購読者ゼロでも通知する（出力は捨てる）。`TerminalPanelSession` はこの経路で feed する。`makeOutputStream()` はテスト用の互換アダプタで、背圧の対象外。
- テスト: `OutputBackpressureTests`（停止中の kill・hangUp・全終了・自然終了で終了し fd が閉じ、自然終了は末尾まで一致／読み手の取り消し／同じ ID の置き換え／通知なし 1 秒の受信上限／古い世代の予約の無視／読み切りの打ち切り／競合の反復）、`PTYManagerIntegrationTests.outputStreamDeliversEveryByteWhenConsumerFallsBehind`（連番入り 9MB が上限で止まり、通知しながら読むと全量一致）、`UserTerminalBackpressureTests`（同期コールバック経路の全量・順序・通知順、購読者ゼロ、restart）。
- 実アプリ（Debug）で確認した値（2026-10-16）: 色付き 52MB の cat の後に残り文字なし（cat の終了から表示の終了まで約 0.45 秒、cat 自体は約 14 秒）。`yes` を 30 秒流しても RSS は 162〜180MB で横ばい、Ctrl-C から約 1 秒で画面が止まる。大量出力の直後に最後の行を出して終了するエージェントのスタブで、最後の行は 3 回とも表示された。
- 後続課題は ADR 0212 に記載（子孫が書き続ける場合の終了時の読み切り、write 側の fd の世代管理、旧世代の後始末、世代の境目の制御列リセット、feed のまとめ処理）。

キーの割り当ては `IMETerminalView` が継承する SwiftTerm の `TerminalView.keyDown` に置く。同メソッドは外部モジュールからオーバーライドできないため、既存のローカル fork に局所修正する。変換は現在のイベントとプロトコルの状態だけで判断し、押下記録は持たず、解放も消費しない。従来モードはキー解放を送信しない。Kitty の解放は既存処理へ渡す。

ユーザー用とエージェント用の共通 `IMETerminalView` で、Option 単独＋左右矢印を `ESC b`／`ESC f` に割り当てる。`optionAsMetaKey` は false のまま、日本語配列の Option＋¥ などの文字入力は AppKit に渡す。Command・Control・Shift を伴う矢印と IME 未確定中の入力は既存処理へ渡す。この割り当ては `keyboardEnhancementFlags.isEmpty` のときだけ有効で、通常／アプリケーションカーソルモードの両方に適用する。Kitty が有効なときは左右矢印の Option 修飾を保持して既存の Kitty 符号化へ渡す。vim での編集動作はアプリ側の ESC b／f の解釈に従う。

SwiftTerm の問い合わせ応答は PTY へ返す必要があるため、一律に抑制しない。`DCS 1!~0000 ST` は矩形チェックサム、`CSI ?65;…c` は DA1 の応答。チェックサム要求は中間文字 `*` がある場合だけ受け付ける（ローカル修正）。問い合わせではない `CSI 1y`・`CSI …$y`・`CSI … y` への誤応答は修正前に再現し、修正後に消えることを確認した。問い合わせなしの合成40万行（太字、通常／高輝度16色、256色、セミコロン／コロン形式の24bit前景・背景、4093バイトごとの分割）では応答ゼロだった。今回提供された元ファイル相当の試験と、配送時の欠落に関する確認範囲は上記の追加調査を参照する。SGR解析は変更していない。

`TerminalOptionArrowTests` は NSEvent から共通ビュー・Coordinator の `onInput` を経由して実 PTY の slave に届くバイト、カーソル／Kittyモード、Option文字入力、追加修飾キー、未確定文字を検査する。通常の矢印のモード別バイトも維持する。`TerminalWordMovementTests`（DashboardFeature）は実zshのemacs編集モードで、`echo one two three` → Option左2回 → X → Return の出力が `one Xtwo three` となることを確認する。`TerminalResponseTests` はSGRの全バイト分割位置・RGB属性と後続SGR・明示問い合わせの応答も検査する。`PHLOX_TERMINAL_SNAPSHOT=1` で共通ビューを画面外に描画し、TerminalUI/.build/terminal-validation.png へ保存する。実アプリの起動、物理キーによる日本語変換、vim実プロセスの操作はこの検証に含めない。

`TerminalOptionArrowTests.kittyOptionArrowLifecycle` は `>1u`・`>3u`・`>7u` の左右矢印について Kitty の押下・リピートと、要求された場合の解放を検査し、ESC b／f が混在しないことを検査する。フォーカス移動で元ビューに解放が届かない経路と、長押し途中で Option を追加・解除する経路も回帰テストに含める。通常矢印が ESC b に変わらず、Kitty の解放が残ることを検査する。`TerminalResponseTests.queriesAtEverySplit` は DA1・矩形チェックサムに加えて DA2・DSR（状態／カーソル位置）・DECCKSR の計6問い合わせを全バイト境界で分割し、未完の問い合わせには応答せず、完成時にだけ期待した応答を返すことを検査する。DA2 の識別値と DECCKSR のゼロは手元の SwiftTerm の実装に従う（ADR 0212 補足）。

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
| git 読み取り・ファイル保存 | `WorkingTreeService`（DashboardFeature/WorkingTree、`actor`） | `/usr/bin/git`（`--no-optional-locks` 付き）をラップ。`snapshot()` はステージ別の一覧・行数、`detail(for:source:)` と `fileContents(_:source:)` は比較元別の差分・本文を取得。旧 `detail(for:)` の HEAD 比較とファイル保存 API も維持 |
| git 値型 | `WorkingTreeChange` / `WorkingTreeDetail` / `WorkingTreeSaveOutcome`（DashboardFeature/WorkingTree/WorkingTreeTypes.swift） | 変更エントリ（path/kind/isBinary）・詳細（diff/untrackedContent/binary）・保存結果（saved/conflict） |
| エディタ VM | `EditorPanelViewModel`（DashboardFeature/Editor、`@MainActor @Observable`） | `listState`（noProject/notARepository/ready）・`changes`・`selectedPath`・`detail`・`draft`・`isDirty` を保持し、`refresh()` / `select(_:)` / `save()` / `overwrite()` を提供。競合検出は「選択時点でロードしたディスク内容」を基準にする |
| 変更タブ表示 | `EditorPanelView`（DashboardFeature/Editor/EditorPanelView.swift） | 選択された1ファイルの差分／内容を表示。構文ハイライトは既存の `ChatCodeHighlighter.highlight` を共有し、編集はファイルタブへ渡す |
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

## Git・変更タブ（ADR 0204〜0209、GW-1〜15）

ADR 0206 により、変更の後にコミット・ブランチ・リモートブランチ・スタッシュ・グラフを配置する。読み取りは WorkingTreeService、書き込みは GitWorkflowService を使う。開いた区画は refresh から更新し、閉じた区画は次に開いたとき読む。履歴行のファイルは行を開いたときだけ取得する。履歴の差分は比較元にコミットIDを保持して変更タブに渡し、読み取り専用とする。⇧⌘R は取得、⌥⌘S はスタッシュ入力を開く。

グラフの `--all` から `refs/stash` を除外し、スタッシュのindex／未追跡を保存する内部コミットをブランチ履歴へ混ぜない。スタッシュの一覧と差分は独立した区画から読む。

ADR 0208 により、モデル交換時も開いた区画を同期する。ADR 0209 により、ブランチは現在のブランチを先頭とし、HEAD reflog の切り替え先の新しい順を各ローカル参照の改名記録から現在名へ引き継ぐ。記録のないものは最終コミット時刻順。グラフは最初200件、続きを読むでは必要件数を200件増やして先頭から再取得し、一覧とレーンを置き換える。外部でコミットが増えてもページを連結して重複させない。コミット／スタッシュのバイナリ判定は `--numstat` を使う。スタッシュ確認は操作名・対象件数・未追跡件数とHEADへ戻す説明を含む。リモート単位で開閉し（originは既定で開く）、FETCH_HEADの更新時刻とローカルのupstreamに基づく追跡中の印を表示する。取得履歴がなければ時刻を出さない。

既知の制限: 旧名を別ブランチが再利用してから再度改名すると、利用順が混同される（並び順だけでデータには影響しない）。reflog では見分けられないため受け入れた。テストは既知の不具合として残す。経緯は [ADR 0209](../adr/0209-git-batch-order-and-history-continuity.md) に調査結果を記録する。

Git の書き込み欄は既存の `GitCommitPanel` と共有 `EditorPanelViewModel` を右サイドバー上部に配置する。ブランチ・更新・メッセージ・コミット／プッシュ／PR・理由・状態表示はスクロール外に置く。メッセージは1〜5行、失敗は3行の要約と詳細、×で閉じる。次の操作で状態表示を消す。⇧⌘C はメッセージへ入力先を移し、⌥⌘P はプッシュする。Git 表示中だけメニューから利用できる。

その下は保存した開閉状態と貼り付く見出しを持つ1本のスクロールとする。「変更」区画は index の「ステージ済み」と作業ツリーの「変更」に分ける。行の選択は出どころとパスで識別し、部分ステージのファイルも区別する。ホバー／選択中は行数を＋／−に置き換える。Space・VoiceOver のカスタムアクション・グループの一括操作は同じ `GitWorkflowService` を使い、操作後は同じグループの次の行へ進む。

コミットは index だけを対象とし、選択チェック状態は持たない。読み取りは `WorkingTreeService` の `--no-optional-locks` を維持し、出どころ別に一覧・行数・差分を取得する。Git タブに差分やドラッグ境界は置かない。行のクリックで既存の変更子タブへ選択パスと出どころを渡し、重ね表示の右サイドバーを閉じる。

自動更新は選択パスを保持する。元のグループから消え、反対のグループに同じパスが残った場合は出どころを切り替えて追従する。ステージ操作後の次行移動は自動更新とは別に、操作対象のグループ内で決める。初回コミット前にステージした後さらに本文を編集すると、`git rm --cached` が保護のため解除を拒否する場合がある。この場合も git の理由を表示し、index と作業ファイルを保持する。強制解除は実装しない。

変更タブは幅によらず1ファイルの差分／内容と「ファイルタブで編集」を表示する。タブ列とウィンドウ見出しの名前は件数や開き直しによらず「変更」（英語は Changes）に固定する。左一覧・コミット欄・「エディタ」の見出しは無い。見出しにはファイル名・フォルダ・追加／削除行数・比較元（作業ツリー／ステージ済み／コミットID／スタッシュ名）を示す。未選択時も無効なツールバーと、選択の案内・補足説明・Git タブを表示するキー（⇧⌃⌘G）を出す。

Git の履歴区画は区画ID、コミット行全体は `GitHistoryRowID.commit(id, graph:)` で識別する。同じコミットを2区画に表示しても遅延描画の行を共有しない。展開ファイルのAX識別子もグラフ／コミットを区別する。現在ブランチの先行数は正のときだけ表示する（ADR 0210）。

状態取得は porcelain v1 の XY と改名元を保持し、同じパスの削除レコードと未追跡レコードを潰さない。DD/AU/UD/UA/DU/AA/UU は通常分類より先に競合として分離し、専用の一覧とターミナルでの解消案内を出す。競合行はステージ／解除の対象に含めず、競合が残る間はコミットを無効にして理由を示す（ADR 0207）。ステージ済みと作業ツリーはそれぞれの状態から独立に列挙し、差分取得も出どころでレコードを選ぶ。旧一覧向けのパス単位の集約はこの2一覧へ流用しない。

削除のステージは `git rm --cached --quiet` で該当index項目だけを削除する。改名元の補完も同じ操作とする。一括ステージは対象全体の削除を追加より先に行う。解除は対象全体を分類し、HEAD にない追加を再帰指定のない `rm --cached` で先に外してから、HEAD の完全一致する項目を子から親の順で `update-index --add --cacheinfo` により戻す。同名ディレクトリの選択外の子へ対象を広げず、衝突する復元は拒否する。失敗時も共有一覧を再取得し、実際の index と失敗理由を表示する（ADR 0209）。初回前の部分ステージの解除は引き続き Git の保護に従う。

ステージ／解除の完了時にも開閉状態を確認し、処理中に閉じた区画は見出しへの入力先を保つ。グラフの履歴行を展開すると、直後のレーン位置に縦線を描き、ファイル一覧・読込中・空の領域を通して次のコミットへ接続する。

折りたたみ時は見出しへ入力先を移し、行の移動・Space・Return・行メニューは表示中の行だけに適用する。プッシュはリモートがあり、コミットとブランチが存在し、追跡先なし、または先行数が正のときだけ有効とする。追跡先なしは「プッシュ（追跡先を作る）」を案内し、既存の push -u を使う。Git 表示中は ⌃↩ で行メニュー、コミット欄では ⌘↩ でコミットでき、Git メニューから PR を作成できる。

## データフロー（エディタ、共通の取得・保存）

右サイドバーの Git タブも `EditorPanelCoordinator.viewModel` の一覧・取得状態・ブランチ・行数を参照する。一覧の読み直しは共有モデルだけが行い、更新中の要求はまとめて追従する。Git のクリック／Return／メニューは `AppRouter.openChildTab(.changes)` と `select(_:source:)` に渡す。コミット欄の入力先も同じモデルへ要求する。

更新は Git タブ表示時、対象プロジェクトに属するセッションの `lastTurnCompletedAt` の変化、`.fileTreeFileSaved`（保存と作成・名前変更・削除）、`NSApplication.didBecomeActiveNotification`、手動更新を共有モデルへ渡す。保存・ツリー操作通知は共有モデル自身が購読し、DashboardView はツリーの更新だけを行う。対象外のプロジェクトのイベントは無視する。新着は直前の成功した一覧にないパスだけとし、初回と失敗後の再試行で全行を新着にしない。未追跡テキストは追加行、バイナリは専用表示。失敗理由と管理外を区別する。

1. `DashboardView.updateEditorPanel()` は `EditorPanelCoordinator.update(project:workspaces:)` に対象を渡す。
   `.task(id: editorPanel.target)` が `resolve(workspaces:)` を呼び、対象プロジェクトが変わったら
   `WorkingTreeService(repositoryRoot:)` を注入した新しい `EditorPanelViewModel` を作る（未選択時は `service: nil`）。
2. `EditorPanelView` は選択されたファイルの詳細ペインを表示する。
一覧取得失敗・Git 管理外への変化でも、未保存下書きがある場合は、その選択と下書きを保持する。保存通知は通知元と共有 Git ルートが包含関係にある場合に更新するため、リポジトリ内の下位フォルダをプロジェクトとして開いた場合も対象にする。未追跡ファイルの行数は最大1MBまでの読み取りで求め、上限超過・読み取り不能・ルート外 symlink ではその行の行数だけ省く。追跡ファイルの行数とバイナリ判定は同じ numstat の結果を使う。Git の通常取得・再試行は同じ処理を通り、選択パス・取得世代・キャンセルを確認してから差分を反映する。本文中の `+++` / `---` はハンク開始後なら差分行として残す。

3. Refresh ボタン → `viewModel.refresh()` → `WorkingTreeService.snapshot()`。ファイル選択 →
   `viewModel.select(_:source:)` → `WorkingTreeService.detail(for:source:)` + `fileContents(_:)`（追跡ファイルの
   場合、diff 表示と同時に本文を読み込んで `draft` へロードする）。
   編集可否は `WorkingTreeText.maximumEditableFileSize`（5 MB）、内容の閲覧可否は `maximumReadableFileSize`（20 MB）を共有する。BOM込みで判定し、5 MB超は保存・dirtyを止め、既存のファイルタブへ閲覧を渡す。20 MB超は変更プレビューのみ。差分の色付けと500行単位のプレビューは維持し、「内容」は1 MB超を本文色とする。外部変更は再選択で読み直す。
4. 保存 → `viewModel.save()` → `WorkingTreeService.save(path:content:expectedDiskContent:)`。
   `.conflict` が返ると View がアラートを出し、ユーザーが選べば `viewModel.overwrite()` で
   `expectedDiskContent: nil` の無条件上書きを行う。

### Git タブの更新接続と表示の補正

保存通知の対象は `WorkingTreeService` が現在解決する Git ルートで判定する。管理外で開いた後に `git init` し、手動更新で復帰した場合も保存に追従する。ターン終了日時の収集と更新の接続は `GitTabPolicy` の小さな関数にまとめ、DashboardView の監視から呼ぶ。対象プロジェクトの日時が変わった場合だけ共有モデルを更新する。

差分は `diff --git` ごとにハンク状態を戻し、次のファイルの `---`／`+++` を本文に含めない。Git の行背景には共有色トークンを使う。管理外見出しは通常書体・副文字色、パスは `~` 表記、管理外と失敗の本文タイトルは主文字色。失敗説明の追加行間は `DSSpacing.xs` とする。

## テスト

ブランチ行の先行数は、`GitDisplayRegressionTests` で製品の `branchRow` を画面外描画し、右端の画素を文字なし／`↑1` の参照描画と比較する。0件では文字がなく、1件では `↑1` があることを検査し、AX値の上書きに依存しない。表示条件を旧条件へ戻した場合の失敗も手元で確認する（この一時変更は製品コードに残さない）。

| ファイル | 固定している性質 |
|---|---|
| `TerminalCoreGraphicsTests`（TerminalUI） | 共通端末をウィンドウに接続・再接続しても CoreGraphics を維持し、全角を含む表示内容を保持する |
| `TerminalEnvironmentTests` | ユーザー用端末の LANG の既定値 `en_US.UTF-8`、アプリ環境の LANG の優先（空文字も従来のエージェント用規則に従って維持）、HOME・PATH・TERM の保持 |
| `GitHistoryWorkflowTests` | 一時リポジトリの履歴50件と続き、初回／空状態、参照、コミット／スタッシュの差分と本文、改名・削除・バイナリ、ブランチ操作、追跡付きチェックアウト、取得、未マージ削除、切り替え失敗、スタッシュ衝突とID保持、開閉に応じた更新。グラフ200件取得後の外部コミットでもIDが重複せず、先頭と末尾へ届くこと、現在／非現在／連続改名で利用順を引き継ぐことも検査 |
| `GitHistoryPolicyTests` / `FocusBorderRenderTests` | 分岐・合流・複数親のレーン、札の束ね、実行中と作業フォルダの確認条件、開いた区画と展開行だけの操作、画面外ウィンドウへのキー入力とindex保全 |
| `GitHistoryRenderTests` | `PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=git-history` で通常・空・展開・確認・失敗・グラフ・履歴差分の144画像（260/340pt、日英、明暗）を書き出す。通常の全件テストでは画像生成を行わない |
| `UserShellSettingsTests` | `/etc/shells` の読み取り・候補の整理・実行可能性・無効パスの保存拒否・システム既定への代替・存在確認後の消失・再試行回数とエラー伝播・再起動時の反映・注意の出力順と旧プロンプトとの分離・出力待機の期限と失敗時の終了処理・実際の bash の `$0` と `$SHELL` |
| `AcceptanceUserTerminalTests` / `UserTerminalControllerWhiteboxTests` | PTY 起動の冪等性・入出力・自然終了→再起動・世代分離・drain 待ち・shutdown 冪等 |
| `AcceptanceWorkingTreeTests` / `WorkingTreeServiceWhiteboxTests` | 変更一覧・diff・保存・競合検出・リネーム/非 ASCII パス・巨大 stderr 耐性 |
| `BottomPanelTests` / `BottomPanelShortcutTests`（TerminalUI） | 高さ・保存・開閉・入力先復帰・プロジェクト所有・初回起動・再起動条件・メニュー優先・別窓を閉じた後と自動再アタッチ後の通知先・共通設定の文字サイズ・画像用の標準タイトルバー |
| `TerminalCoordinatorVisibleTextTests`（TerminalUI） | 行内の空セル・タブ移動は空白、全角文字の後続セルは除外し、VoiceOver の値にNULを含めない |
| `TerminalPanelViewWhiteboxTests` | パネルの表示器が共有コントローラを保持し、入出力を `TerminalCoordinator` へ接続すること |
| `EditorPanelVMTests` | VM の一覧/選択/編集/保存/競合フロー |
| `GitStagingTests` / `GitWorkflowTests` | 実リポジトリでのステージ・解除・部分ステージの index だけのコミット・特殊名・削除・改名・初回コミット前・失敗時の状態保全・次行移動・外部操作後の選択パス維持・比較元別の差分／本文／行数／バイナリ。未マージ7種類の分離・一括ステージの除外・コミット禁止、同名ディレクトリの子を巻き込まない削除／改名／解除も検査。ファイルと同名ディレクトリの相互置換の一括操作、引数の正順／逆順、途中失敗後および外部変更後の一覧と実際のindexの一致も検査 |
| `EditorPanelGitCommitUITests` / `GitWorkflowRenderTests` | 未選択と比較元の AX 静的テキスト値・ホバー操作・260/340pt・プッシュ前後の PR 可否。差分取得の待機中に区画を閉じ、＋／−の完了後もAXの入力先が見出しであることを検査。`PHLOX_DESIGN_SNAPSHOTS=1 PHLOX_DESIGN_SNAPSHOT_SCOPE=git-workflow` で競合を含む Git 40 状態と変更タブ12状態を画面外に描画。`git-rereview` は履歴144画像も同じ実行で生成 |
| `GitInspectorTests` / `GitInspectorServiceTests` | 複数ファイル差分のヘッダー除外・管理外から Git 管理へ復帰した後のファイルタブ保存による共有一覧更新（ルートと子フォルダ）・実際のターン終了日時から共有一覧更新への接続・別プロジェクトと同じ日時の更新抑止 |
| `EditorPanelGitCommitUITests` / `GitInspectorTests` | 320/760ptの1ペイン表示・選択の世代競合・非表示行のキー操作抑止・見出しと未選択案内 |
| `PanelIntegrationWhiteboxTests` | 変更種別ごとの SF Symbol |
| `GitDisplayRegressionTests` / `ProjectTabsPresentationTests` | 同じコミットをコミット区画とグラフ区画で繰り返し展開し、行とファイルのAX識別子・グラフ行の高さ・ファイルの左余白・先頭の空白を検査する。変更タブは件数0〜3で開閉・再選択し、1枚だけを保持して日英の名前を固定する。`PHLOX_INTEGRATION_FIX_SNAPSHOTS=1` と `GitDisplayRegressionTests` の絞り込みで全区画展開の画面外画像を保存する |
| `PosixSpawnCloexecTests`（PTYKit） | spawn した子が無関係な fd を継承しないこと |
| `PTYTerminalModeTests`（PTYKit） | ユーザー用の echo・icanon・制御文字、従来のエージェント用 raw 設定、実 bash の stty と Return 前の入力エコー |
| `InteractiveSpawnTests`（PTYKit） | zsh/bash の前景 TPGID・Ctrl-C・前景へのサイズ変更、標準 fd 欠落時の ENOENT・子回収、高番号 fd 非継承、起動失敗反復後の fd 数・子回収、cwd・環境、既定 raw のサイズ変更通知 |
| `FileTreeInteractionTests` | 右クリック／Return から入力欄の表示・フォーカス・拡張子前の選択・確定までを通し、ファイル／フォルダ内のタブと未保存本文・Undo の同一性を保つ |
| `FocusBorderRenderTests` | Git の折りたたみ後の見出しへの入力先移動とindex保全・⌃↩の行メニュー・コミット欄の⌘↩と非表示時の抑止。画面外のウィンドウでファイルツリー・Git 一覧・変更タブの差分・下部端末へ入力先を移し、左右の外周画素を検査する。差分は中立の通常行を測り、追加・削除の色と外枠を混同しない。アプリと窓のアクティブ状態だけをテストプロセス内で代替し、入力先は実際の SwiftUI フォーカス要素／端末の first responder から確認する。行クリックと共通の AX 押下処理→ポインタ退出→ファイル／フォルダの選択の塗り→Return の名前変更対象も検査する。画像保存は `PHLOX_DESIGN_SNAPSHOTS=1` で指定する |
| `ToolbarInteractionTests` | 標準タイトルバーで日英の開閉ボタンの名前が独立し、実際の AX 操作後に選択状態が変わる |
