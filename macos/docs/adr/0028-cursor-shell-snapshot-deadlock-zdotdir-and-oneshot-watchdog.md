---
status: active
last-verified: 2026-07-04
---

# ADR 0028: Cursor のシェルスナップショット・デッドロック回避（cursor 限定 ZDOTDIR）と OneShotProcessRunner ウォッチドッグ

## 文脈

Cursor 構造化チャット（appServer backend）セッションが、シェルコマンド実行を伴うメッセージで「Thinking…」のまま永久にハングする事象が観測された。1通目（計算のみ）は成功、2通目（`ls` 実行）で固着し、親の `$PHLOX_CLI wait` も待たされる。実プロセス解剖と二分探索で根本原因を2層に分解して確定した。

**層1（引き金・Phlox 外＝cursor-agent CLI × ユーザー zsh 環境）**
- cursor-agent は `ls` 実行のため子 zsh を spawn し、その zsh が `snap=$(command cat <&3)`（シェルスナップショット読み取り）で FD3 の EOF を待って永久ブロックする（`sample`/`lsof` で確認）。
- Phlox を介さず直接 `cursor-agent -p "…ls…" -f` を実行しても同じく固着 → Phlox 固有ではない。
- 二分探索で犯人を**ユーザーの `~/.zshrc:72` の `alias ls="eza …"`（core コマンド `ls` の上書き）1行**に特定。この alias を外す／空 `ZDOTDIR` で zsh 起動ファイルをバイパスすると `ls` が `result:success` まで到達し成功する。**フラグ非依存**（eza に上書きすること自体が原因）。agmsg 等の常駐プロセスは無関係（zsh 起動経路に不在）。
- 子 zsh を kill しても cursor-agent は別途 FD4 待ちで固着し、**cursor-agent 本体を kill するまで回復しない**。

**層2（Phlox 構造バグ）**
- Cursor は1ターン＝1回の使い捨て `cursor-agent -p …` 起動で、`CursorChatClient.turnStart` が `OneShotProcessRunner.run` を await する。`OneShotProcessRunner.run` は `process.terminationHandler` でしか継続を resume せず**タイムアウトが皆無**だった。プロセスが終わらないと `.turnCompleted`/`.error` が永久に発火せず status が `.running`（Thinking…）のまま固着する。
- Codex（常駐プロセス＋通知ストリーム）・Claude（長寿命ストリーム）は「プロセス終了≠ターン完了」なので無影響。Cursor だけが「プロセス終了＝ターン完了の必須条件」という構造差が非対称性の原因。

## 決定

**(A) 全 cursor spawn に cursor 限定の ZDOTDIR サニタイズを注入する（層1の引き金を Phlox 側で断つ）**
- `DashboardViewModel.prepareSessionLaunch` の**単一 choke point**で、`plan.ref.builtinKind == .cursor` のときだけ `plan.env` を `CursorShellSanitizer` 経由でサニタイズし、`ZDOTDIR` を zsh 設定ファイルの無い空ディレクトリ（`~/Library/Caches/Phlox/cursor-empty-zdotdir`、冪等に用意）へ向ける。zsh はそこからのみ起動ファイルを探すため `~/.zshrc`（の `alias ls="eza"`）を評価しない。
- この choke point は pty(Terminal)/appServer(Chat)・新規/復元の**全 cursor 経路**が通る（pty 新規＝`spawnNewSession`、pty 復元＝`restoreSession`、appServer 新規/復元＝`prepareSessionLaunch`→`makeChatSessionViewModel`→`structuredClientFactory` へ `plan.env`）。
- Claude/Codex/custom CLI は無改変（ZDOTDIR は cursor のみ）。ユーザーの `~/.zshrc` は編集しない。dir 用意失敗時は元 env にフォールバックし cursor 起動を止めない。PATH は planner が `environment.pathEnvironment` で明示設定するため .zshrc バイパスでも喪失しない。

**(B) OneShotProcessRunner にタイムアウト（ウォッチドッグ）を追加する（層2＝原因を問わない堅牢化 backstop）**
- `OneShotProcessRunner(timeout: TimeInterval?)`（既定 nil）。非 nil で期限内にプロセスが終了しなければ、親を SIGKILL（＋プロセスグループへ best-effort kill）し `OneShotProcessTimeoutError` を throw resume する。`CursorChatClient` の既定 runner を `OneShotProcessRunner(timeout: 300)`（backstop 値）にし、既存 catch が `.error` 化してセッションを回復させる。
- termination と timeout を**単一 NSLock 下の `pending/terminated/timedOut` claim** に集約し、kill を claim と同一排他区間で実行する（正常終了後の pid 再利用への SIGKILL/TOCTOU を根絶）。継続の二重 resume は既存 `OneShotContinuationBox` が防ぐ。`timeout=nil` は完全非退行。

## 棄却案

- **ユーザーの `~/.zshrc` を編集して `alias ls` を直す**: ユーザー資産。Phlox の修正としない（ただしユーザーが望めば別途可能）。
- **`SHELL=/bin/bash` を注入**: デッドロックは解けるが cursor の全シェルコマンドの挙動を変える。ZDOTDIR（zsh 維持＋起動ファイルのみバイパス）の方が影響が小さい。
- **ZDOTDIR 注入を AppEnvironment の appServer factory だけに置く**（初版）: cursor の Terminal(`.pty`) 経路を迂回し同じデッドロックが再発する。全経路が通る `prepareSessionLaunch` choke point へ移動し、factory の注入は撤去（単一の真実源）。
- **ウォッチドッグ(B)だけ／ZDOTDIR(A)だけ**: B だけでは cursor コマンドが毎回 timeout→error で失敗し実用にならない。A だけでは別要因の非終了で再びハングする。両方採用。
- **timeout kill 経路を terminationHandler と非排他のまま `DispatchWorkItem.cancel()` だけで抑止**: cancel は実行開始済み work item を止められず、正常終了直後の pid 再利用に SIGKILL を撃つ TOCTOU が残る。claim-lock で排他化して根絶。

## 受容したトレードオフ / 既知の限界

- **cursor のシェルコマンドはユーザーの zsh エイリアス/関数無しで走る**（PATH は明示注入で保持）。オーケストレーション用途では素の coreutils の方がむしろ決定的で許容。
- **ウォッチドッグ発火時の reader/FD リーク（稀）**: timeout で親を kill した後、もし kill された子の**孫**が stdout pipe の write 端を握って生存し続けると、reader スレッド/FD の後始末（`terminationHandler` 内の `readGroup.notify`）が走らずリークしうる。ただし (1) 呼び出し元は resume 済みで**セッションのハングは再発しない**（一次目的達成）、(2) 300s の稀な backstop（A が実デッドロックを断つため通常発火しない）、(3) cursor-agent の子 zsh は cursor-agent の stdout pipe を握らないため親 kill で reader が EOF して後始末が走る（実際、固着 cursor-agent を kill した際に子 zsh も reaped されたことを実測）。reader handle を並行 read 中に close する修正はホットパスに悪い並行バグを持ち込むリスクがあるため見送り、既知限界として受容。
- `sanitizeCursorLaunchPlanIfNeeded` は `AgentLaunchPlan` を手動全フィールド複製する。将来デフォルト値付き stored プロパティが追加されると silent 欠落しうるため、同期を促すコメントを同所に付置。

## 結果

- 全 cursor spawn（Terminal/Chat・新規/復元）が `~/.zshrc` を読まなくなり、`alias ls="eza"` 由来のデッドロックを回避。万一 cursor-agent が別要因で終了しなくてもウォッチドッグが 300s で kill→`.error` 化しセッションが回復（永久ハング根絶）。
- 検証（PM ゼロ信頼実走）: DashboardFeature **588 green**、StructuredChatKit **20 green**、CursorAgentKit **22 green**、ヘッドレス E2E **17 green**。独立レビュー（persona-reviewer）task-1 **pass**、task-2 は TOCTOU 修正を claim-lock で確認。
- 白箱で「cursor .pty/.appServer に ZDOTDIR あり・PATH 保持・claude/codex に無し」「掃除分岐で残骸 .zshrc が消える」「timeout で非終了プロセスが kill され throw・二重 resume なし」を凍結。
- **runtime（実 Debug 起動での cursor コマンド成功）は未実施**。root cause の機構（空 ZDOTDIR で `ls` が成功）は実 cursor-agent で実証済み、env 注入はコード・白箱でカバー。

作業経緯は delivery/0011-cursor-hang-fix-worklog.md を参照。
