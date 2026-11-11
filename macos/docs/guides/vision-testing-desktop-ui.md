---
status: active
last-verified: 2026-10-15
---

# デスクトップ UI のビジョン検証（手動・非侵襲）

リリース前後に「ユーザーの操作を再現して**見た目が正しく表現されているか**」を、AI がスクリーンショットを目視して確認する手順。コード/ロジックの正しさは対象外（それは自動テスト → `specs/e2e-test-design.md`）。

- **これで見るもの**: 実行中インジケータ・停止赤枠・グリッド・Usage バー・ツールコールカード等、**実行中しか現れない動的な状態**の表示。
- **反復回帰はここでやらない**: 状態・API・描画の自動検査へ寄せ、必要な画面操作は XCUITest（`~/.agents/scripts/xcuitest-run` 経由。実行後に増えた入力ソースを外す）か AX/イベント送信で確認する。ビジョン検証は探索的確認に使い、[統合前検証契約](../specs/merge-verification-gates.md)に従って自動検査・画面観測・実機記録を分ける。
- **一般技法の正本**: 非侵襲キャプチャ・AppleScript/AX 駆動の汎用手順は `~/.claude/skills/swift-testing-and-perf`（SKILL.md 共通規律＋`references/macos-ui-test-applescript.md`）。ここには **Phlox 固有の束縛だけ**を書く。

## 前提（Phlox 固有）

- **Debug ビルドを使う**。データは `~/Library/Application Support/Phlox-Debug`、bundle id `com.phlox.Phlox.debug`（ADR 0034 / `guides/running-release-and-debug-together.md`）。
- **通常アプリを終了させない**。[併存ガイド](running-release-and-debug-together.md)に従い、検証版のデータ・設定・ポート・必要なbundle IDを分ける。ウィンドウ復元の競合やAX不可視を観測したら失敗を記録し、他作業の設定や保存状態を削除せず原因を調べる。
- **フェイクエージェント注入**: 組込みハーネスの実行ファイルの場所を、環境変数 `PHLOX_TEST_AGENT_BINARY_PATHS`（JSON。例 `{"claudeCode":"/tmp/fake-agent.sh"}`）で差し替える。`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を一緒に渡したときだけ有効（`AppBootstrap/BinaryPathResolver.swift` の `testBinaryOverrides`。`UITests/IsolatedPhloxApplication.swift` が同じ形で渡す）。カスタムエージェント（`PHLOX_AGENTS_JSON`・`agents.json`）は 2026-10-12 に廃止された（ADR 0185）。ウィンドウ復元と env 注入を両立するため **`open --env` を使う**（バイナリ直起動は `windows=0` を招く。skill 側に詳細）:
  ```bash
  open --env "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1" --env 'PHLOX_TEST_AGENT_BINARY_PATHS={"claudeCode":"/tmp/fake-agent.sh"}' -a "$DEBUG_APP"
  ```
  フィクスチャ本体は `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Fixtures/fake-agent.sh`（`--exit-after N` で N 行処理後に exit）。この環境変数によるCodexの注入は、2026-11-04の[Markdownスクロール調査](../delivery/markdown-scroll-freeze-20261103.md)で隔離したDebugと8件のフェイクチャットを実走した。この段落のClaude Code用 `fake-agent.sh` 経路は未再検証（旧手順からの置き換えはコードで確認）。画面からはターミナルのセッションを始められない（ADR 0185）ので、フェイクのターミナルセッションは Control API・CLI の `backend: pty` で作る。
- **AX 操作権限**（システム設定 > プライバシー > アクセシビリティ）が必要。

## 非侵襲キャプチャ

`screencapture -x -o -l<WID>`（`WID` は `CGWindowListCopyWindowInfo` の `kCGWindowNumber`）で**そのウィンドウだけ**を撮る。z-order 非依存でオクルードされても撮れ、**frontmost 化しない＝マウス/フォーカスを奪わない**。frontmost 化はウィンドウ位置・復元状態を壊すので撮るだけなら避ける。

## 比較用画像を画面外で描画する

`DesignSnapshotRenderTests` はウィンドウを表示せずに比較用画像を作る。エージェントが実行するときは、worktree のルートで次の環境変数を設定し、共通の `managed-build` と `compact-test` を経由して標準のパッケージテスト入口を実行する。XCUITest は不要。

```bash
export PHLOX_DESIGN_SNAPSHOTS=1
export PHLOX_DESIGN_SNAPSHOT_OUTPUT_DIR="$PWD/.verification/ui-review/design-snapshots"
export PHLOX_DESIGN_SNAPSHOT_FRAME_IDS="10-A1-dark-ja 11-T1-dark"
```

`PHLOX_DESIGN_SNAPSHOT_OUTPUT_DIR` には、その作業が所有するディレクトリの絶対パスを渡す。画像・描画用データ・`結果.md` は指定先に出力する。空文字・相対パス・ディレクトリとして作れないパスはエラーにする。未指定時の画像出力先は従来どおり `<worktree>/.build/design-snapshots`。

`PHLOX_DESIGN_SNAPSHOT_FRAME_IDS` は、`比較用画像を書き出す` で描画する状態 ID を空白で区切って指定する。既存の `PHLOX_DESIGN_SNAPSHOT_SCOPE` で絞った候補から選ぶ。空文字や候補にない ID はエラーにする。未指定時は従来の範囲を描画する。結果は指定した状態の描画について報告する。

新規チャットの描画は `renderStage8NewChat`、承認待ちセッションを含むタブ列の描画は `renderStage8ProjectTabs` を参照する。入口は `比較用画像を書き出す`。承認確認カード専用の画像書き出しは、このテストには未設定。

タイトル付きの描画用ウィンドウは、SwiftUI のツールバー初期化でフレームが変わることがある。固定寸法の検査では、初期化後にウィンドウの寸法を設定し、ウィンドウ自体と表示領域の寸法を両方検証する。

## Phlox の UI を AX で駆動する要点

- **チャットのセッション生成は新規チャット画面から**: メニュー「ファイル ▸ 新規チャット」（⌘N）で画面を出し、入力欄（識別子 `newChat.composer`）に書いて送る（送信ボタン `newChat.sendButton`）。送るとセッションができて自動選択される（`AppRouter.completeNewChat`）。旧「メニューバー『セッション』経由の生成」・ツールバーの「追加」ボタンは無い。macOS 標準メニューバーは完全 AX 対応だが、SwiftUI の in-window `Menu` は AX に出ないことがある → 開いてキーボードナビ（↓×N→Return）。ただしキーが背面ターミナルに漏れるので事前にフォーカスを外す。
- **サイドバー（NavigationSplitView）の行選択は AX で駆動できないことがある**（`AXStaticText` click も `select row` も detail を切り替えない）。自動選択される生成経路を使う。
- チャット入力: `AXTextArea` に `set focused ... to true` → `keystroke` → **Return で送信**（Cmd+Return や送信ボタン座標は不安定）。`entire contents` は `with timeout of 200 seconds`＋リトライで取り、`as text` 一括 coerce しない（`-1700`）。
- ビュー切替（単一/グリッド/インスペクタ）はヘッダー（`DashboardToolbar`、右寄せ）の `button` を位置で特定。

## 動的状態の再現レシピ

| 見たい状態 | 再現手順 |
|---|---|
| 実行中インジケータ（サイドバーの題名を流れる帯と右端の「実行中」・Thinking・赤い停止ボタン。緑ドットなどの図形は廃止済み） | Haiku チャットに読み取り専用プロンプトを送信し、実行中を `-l<WID>` で連写 |
| ツールコールカード | Haiku チャットに `ls`/`Read` 等を促し、ターミナル/Reasoning カードとコスト表示を確認 |
| グリッド・最下部の使用量のバー | ビュー切替ボタンで表示。複数セッションを事前に作っておく |
| **停止セッションの赤枠** | 下記「停止赤枠の再現」参照 |

### 停止赤枠の再現（交絡に注意）

赤枠は `SessionGridView.swift` の `tileBorderColor` が（2026-10-12 時点で `tileBorderColor` は本番コードに見当たらず、枠の判断は `GridTileBorderPolicy`。以下は 2026-07 時点の記述で未再確認） `session.hasUnseenCompletion`（`SessionStatus` が `.completed`/`.error`/`.awaitingApproval` に入るとラッチ）で赤(`DSColor.stoppedHighlightGridBorder`)を返す仕様。（ハーネスごとの識別色は廃止済みなので、ブランド色との交絡は無い。）**チャットのターン中断は `.idle` に戻り赤枠にならない**（`ChatSessionViewModel.turnInterrupt`）。

手順:
1. （ハーネスごとの識別色は廃止済みなので、色を中立に変える手順は不要。）
2. フェイクのターミナルセッションを Control API・CLI の `backend: pty` で spawn。
3. **アプリの直接の子 PTY プロセスを終了させる**（`ps -ax -o pid,ppid,command | awk -v app=<APP_PID> '$2==app'` で特定して `kill -TERM`）。`--exit-after 0` の即時終了はアプリが exit を購読する前に消えてレースするので使わない。
4. グリッドに**赤枠**が出れば OK（サイドバーの行の状態は図形でなく右端の文字）。生存中の別セッションが緑のままなら対照として正しい。

## 長いユーザー発言の復元後に画面が固まるとき

- 実データの本文をログやfixtureへ転記せず、合成した無改行文、改行、絵文字、結合文字で切り分ける。`sample`が`UserBubbleWidth.sizeThatFits`とCoreTextに集中していたら、保存・復元と表示を別々に計時する。実行サービスの準備期限切れと画面の文字計算を同一原因と決めつけない。
- `session-runtime-long-user-message.test.py`を固有bundle IDの隔離アプリと空の`--work-dir`で実行する。496万文字の発言と3件のエラーを合成し、cold restore、AXによる別会話への切替、GUI再接続、保存全文のSHA一致を検査する。実行は`compact-test`経由。API応答だけを画面応答の証拠にしない。
- ユーザー発言の表示には文字を構成するUnicode scalarと改行の両方に上限がある。「先頭のみ表示」と常時見える「全文をコピー」を確認する。通常のコピーも元の全文を使い、保存本文を切り詰めない。

測定条件、結果、再実行コマンドは[長文ユーザーメッセージの調査記録](../delivery/0226-long-user-message-freeze.md)を参照する。通常検査には`LongUserMessageTests`も含まれる。セル単体のPNGと実アプリの撮影を、画面全体の`DesignSnapshotRenderTests`と区別する。

## Markdownスクロールの固着を調べるとき

- 現在のファイルだけで未再現と判定しない。FileTabDocumentは初回の読み込み内容を保持するため、障害後の変更時刻とGit履歴を照合し、障害前の候補版を隔離したfixtureへ保存する。版・バイト数・SHA-256を記録し、原本を変更しない。
- 応答しないAXだけで原因を決めず、対象PIDのsampleとCPU・メモリ推移を採る。通常のRelease／Debugとは実行パスで区別する。
- 小文書だけの対照にせず、表を含む障害時の版、狭い幅、大文書、チャット更新中を確認する。スクロールに伴う編集確定・文書Undoも既存の自動テストで確認する。

根拠と今回の配置方式の対照は [Markdownスクロールの調査記録](../delivery/markdown-scroll-freeze-20261103.md)。

## 報告の規律

- **日本語入力の確定は CGEvent の合成キーでは検証できない**。`CGEvent.postToPid` の試験結果だけで IME の合否を判断せず、人の手入力で確認する。対照として既存の端末にも同じ試験を当て、試験方法の問題を切り分ける（[ADR 0211](../adr/0211-decline-ghostty-user-terminal-engine.md)）。
- **各メッセージ右下のコストは 1 ターン分**。セッション総額と書かない（総額を出す画面は 2026-10-13 に廃止。ADR 0192）。
- **AX で列挙できた ≠ そう描画される**。報告では「AX で確認」と「目視（スクショ）で確認」を区別する。
- flaky な状態は、状態→描画ロジックをコードで裏取り（「どの列挙値が赤枠を出すか」）してからスクショと突き合わせる。

## 後片付け

画面を終了しても、独立した実行サービスとその子プロセスは動き続ける。検証の終了時は、今回の所有記録でPID・実行パス・起動時刻を照合し、検証用の画面・実行サービス・fake-agentだけを終了して残存を確認する。`session-runtime-lifecycle.test.py`と大履歴受入のハーネスはこの所有確認と後片付けを行う。通常利用中のReleaseや別のDebugには触れない。テストで作った実セッションはユーザーのデータなので勝手に消さない。

## カードと入力履歴の実画面受入

カードと入力履歴の隔離受入には `macos/scripts/tests/session-runtime-semantic-chat.test.py` を使う。固有 bundle ID のアプリと未使用の `.verification/<作業名>/` 内の `--work-dir` を渡し、`compact-test --full` 経由で実行する。カード・履歴の追加取得・最古入力への移動・末尾復帰・9セッション・中断・GUI再接続を扱う。API の独立した対照読取は GUI の通信を捕捉した証拠ではない。最終ソースのビルドと一致する記録であることも確認する。

Phlox の SwiftUI 識別子は、状態行の title/timer や入力欄の container/editor に継承される。生の node 数をセッション数とせず、既知の owner ID 集合と role を照合する。0件の検査は完全な tree と対象ウィンドウの存在を先に確認し、AX 読取失敗による空配列を成功としない。ウィンドウ変更の限定 probe と、その後の全 tree 検査は分けて記録する。

撮影対象は所有 PID の layer 0 の実ウィンドウから選び、PNG の寸法も検査する。細い補助ウィンドウの画像や AX の列挙だけを見本比較の根拠にしない。9タイルの窓内収容と、スクロール領域内に全見出しが描画されることも別の検査である。[今回の設計・検証記録](../delivery/0231-semantic-chat-read-model.md)を参照する。

## AXで会話名を読み取るとき

`AXChildren`の配列から得た要素を生ポインタで訪問済み集合へ入れる場合、各要素を探索終了まで`CFRetain`で保持し、終了時の`finally`で解放する。枝ごとの配列を解放すると、別の要素が同じアドレスを使い、未訪問の枝を読み落とすことがある。読み取れないことだけで画面の欠落と判定せず、実画面と保持期間を確認する。[同一画面での比較記録](../delivery/0225-send-input-delay.md)を参照する。

## 関連

- 自動テスト設計（必須fake集合・シナリオカタログ。XCUITestは自動ゲート外）: `specs/e2e-test-design.md`
- Release/Debug 同時併用: `guides/running-release-and-debug-together.md`（ADR 0034）
- 汎用の macOS UI テスト技法: `~/.claude/skills/swift-testing-and-perf`
