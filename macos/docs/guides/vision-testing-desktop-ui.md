---
status: active
last-verified: 2026-10-12
---

# デスクトップ UI のビジョン検証（手動・非侵襲）

リリース前後に「ユーザーの操作を再現して**見た目が正しく表現されているか**」を、AI がスクリーンショットを目視して確認する手順。コード/ロジックの正しさは対象外（それは自動テスト → `specs/e2e-test-design.md`）。

- **これで見るもの**: 実行中インジケータ・停止赤枠・グリッド・Usage バー・ツールコールカード等、**実行中しか現れない動的な状態**の表示。
- **反復回帰はここでやらない**: 同じ確認を繰り返すなら `accessibilityIdentifier` ベースの XCUITest（`specs/e2e-test-design.md` の Layer B）へ寄せる。ビジョン検証は高コストな探索的確認に限る。
- **一般技法の正本**: 非侵襲キャプチャ・AppleScript/AX 駆動の汎用手順は `~/.claude/skills/swift-testing-and-perf`（SKILL.md 共通規律＋`references/macos-ui-test-applescript.md`）。ここには **Phlox 固有の束縛だけ**を書く。

## 前提（Phlox 固有）

- **Debug ビルドを使う**。データは `~/Library/Application Support/Phlox-Debug`、bundle id `com.phlox.Phlox.debug`（ADR 0034 / `guides/running-release-and-debug-together.md`）。
- **本番 Phlox（`/Applications/Phlox.app`）が起動していると、Debug のウィンドウ復元が競合**してオフスクリーン化・極小化・AX 不可視を起こす。検証中は本番 Phlox を終了しておく。復元状態が壊れたら `defaults delete com.phlox.Phlox.debug` ＋ `rm -rf "~/Library/Saved Application State/com.phlox.Phlox.debug.savedState"` で初期化。
- **フェイクエージェント注入**: 組込みハーネスの実行ファイルの場所を、環境変数 `PHLOX_TEST_AGENT_BINARY_PATHS`（JSON。例 `{"claudeCode":"/tmp/fake-agent.sh"}`）で差し替える。`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を一緒に渡したときだけ有効（`AppBootstrap/BinaryPathResolver.swift` の `testBinaryOverrides`。`UITests/IsolatedPhloxApplication.swift` が同じ形で渡す）。カスタムエージェント（`PHLOX_AGENTS_JSON`・`agents.json`）は 2026-10-12 に廃止された（ADR 0185）。ウィンドウ復元と env 注入を両立するため **`open --env` を使う**（バイナリ直起動は `windows=0` を招く。skill 側に詳細）:
  ```bash
  open --env "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1" --env 'PHLOX_TEST_AGENT_BINARY_PATHS={"claudeCode":"/tmp/fake-agent.sh"}' -a "$DEBUG_APP"
  ```
  フィクスチャ本体は `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Fixtures/fake-agent.sh`（`--exit-after N` で N 行処理後に exit）。**この注入口での実走は未検証**（旧手順の `PHLOX_AGENTS_JSON` からの置き換えをコードで確かめただけ）。画面からはターミナルのセッションを始められない（ADR 0185）ので、フェイクのターミナルセッションは Control API・CLI の `backend: pty` で作る。
- **AX 操作権限**（システム設定 > プライバシー > アクセシビリティ）が必要。

## 非侵襲キャプチャ

`screencapture -x -o -l<WID>`（`WID` は `CGWindowListCopyWindowInfo` の `kCGWindowNumber`）で**そのウィンドウだけ**を撮る。z-order 非依存でオクルードされても撮れ、**frontmost 化しない＝マウス/フォーカスを奪わない**。frontmost 化はウィンドウ位置・復元状態を壊すので撮るだけなら避ける。

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

## 報告の規律

- **コストはインスペクタの「総コスト」（セッション累計）を読む**。各メッセージ右下の単発コストをセッション総額と書かない。
- **AX で列挙できた ≠ そう描画される**。報告では「AX で確認」と「目視（スクショ）で確認」を区別する。
- flaky な状態は、状態→描画ロジックをコードで裏取り（「どの列挙値が赤枠を出すか」）してからスクショと突き合わせる。

## 後片付け

Debug インスタンス終了（`osascript -e 'tell application "Phlox" to quit'`）で fake-agent と `claude --resume` 子プロセスも止まる。テストで作った実セッションはユーザーのデータなので勝手に消さない。

## 関連

- 自動テスト設計（XCUITest / fake-agent / シナリオカタログ）: `specs/e2e-test-design.md`
- Release/Debug 同時併用: `guides/running-release-and-debug-together.md`（ADR 0034）
- 汎用の macOS UI テスト技法: `~/.claude/skills/swift-testing-and-perf`
