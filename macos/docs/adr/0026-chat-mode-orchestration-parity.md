---
status: active
last-verified: 2026-07-04
---

# ADR 0026: チャットモードのオーケストレーション対等化（spawn / backend 継承 / wait 完了検知）

> **更新(2026-07-06, ADR 0035)**: 本 ADR §1・決定1 の「`OrchestrationGuide` 配信」前提は **ADR 0035 で廃止**——全種別で自動注入を撤去し `/phlox-cli` スキルへ移設した。本 ADR の **spawn backend 継承・wait 完了検知**の決定は存続する。

## 文脈

Phlox のセッションには2系統ある: **ターミナルモード（`SessionBackend.pty`、PTY 上で CLI を動かす）** と **チャットモード（`SessionBackend.appServer`、StructuredChatKit の構造化バックエンド。claude/codex/cursor が対応、ADR 0015）**。ターミナルモードのエージェントは `$PHLOX_CLI` で他エージェントを spawn/send/wait/kill できる（`OrchestrationGuide` を毎ターン注入されるため）。しかしチャットモードでは同じ指示をしても spawn できず、実機で次の3つの問題が連鎖的に判明した。いずれも runtime（Debug 実機）でプロセスツリーを観測して確定した非自明な事実であり、素朴な実装が外れたため決定を記録する。

観測した実データの事実（本 run で実測）:

1. **チャット子の前提はすべて揃っていた**が spawn を discover できなかった。`PHLOX_CLI`/`PHLOX_API_URL`/`PHLOX_TOKEN`/`PHLOX_SESSION_ID` の env は backend 非依存で注入され（`AgentLaunchPlanner`）、トークンも backend 分岐の前に登録され（`DashboardViewModel`）、Claude チャットは `defaultAllowedTools` に `Bash` を含む。欠けていたのは **spawn 手順を教える `OrchestrationGuide` だけ**で、`AgentLaunchPlanner.profile()` が `backend == .appServer` で `hookIntegration: .none` を返し、`DashboardViewModel.prepareSessionLaunch` の `guard backend == .pty` がガイドファイル設置をスキップしていた。修正前のチャット Claude は spawn を知らず、`codex exec` を `screen` でバックグラウンド起動して回避していた（Phlox の一覧に子が出ない）。

2. **チャットから spawn した子はターミナル（PTY）で立っていた**。CLI（`scripts/phlox spawn`）は backend を送らず、ControlServer が省略時 `.pty` を既定にしていたため。実機で子 codex が `codex --dangerously-bypass-approvals-and-sandbox`（PTY）で起動していた。

3. **チャット子は turn 完了が速く、`$PHLOX_CLI wait` がハングした**。`send` と `wait` は別プロセス・別 control action の2段階で、応答の速いチャット子は送信直後の隙間で turn を完了する。`waitUntilDone` は wait 開始時に `baselineTurnSeq = completedTurnSeq` を取り `completedTurnSeq > baseline` を待つため、完了が baseline に既に織り込まれ、以後の増分が来ず timeout(300s) までハングした。PTY 子は codex TUI が遅く wait 開始時にまだ実行中だったため露見していなかった（＝問題2でチャット子にした結果、顕在化した）。

## 決定

### 1. OrchestrationGuide はチャットクライアントの native チャネルで届ける（hookIntegration を appServer で有効化しない）

チャットは PTY フック（hook-dispatcher）経路を持たないため、`hookIntegration` を appServer で有効化するのは誤り。代わりに **ガイド配信だけをフックから切り離し**、各チャットクライアントが元々持つ system-prompt / instruction チャネルへ届ける。共通の運搬は既存の env 慣習 `PHLOX_ORCHESTRATION_GUIDE`（codex 端末が既に使う）を appServer でも `AgentLaunchPlanner` が載せる形で行い、各クライアントが消費する:

| kind | native チャネル | 実装 |
|---|---|---|
| Claude | `--append-system-prompt <guide>`（`claude -p` stream-json でも受付可） | `ClaudeChatClient.buildArguments` が env から読んで付与 |
| Codex | `thread/start`・`thread/resume` の `developerInstructions` | `CodexStructuredAgentClient` が既定値として保持・注入（呼び出し側の明示指定は尊重） |
| Cursor | `.cursor/rules/phlox.mdc`（唯一のガイド経路） | `prepareSessionLaunch` の `OrchestrationGuide.install` を guard の前へ移し appServer でも設置 |

env を全 appServer に載せても、Cursor はファイル経由・codex は app-server プロセスがその env を読まないため二重注入にはならない。**ターミナルモードの配信経路（Claude=起動引数直付け／Codex=hook additionalContext／Cursor=Always ルール）は不変**。

### 2. spawn の backend は親から継承する（appServer への「昇格のみ」）

CLI は backend を指定できない（`{kind}` のみ送る）。子の backend は **spawn 元（`from`）の backend を継承**する。ただし規則は「昇格のみ」:

- 親が appServer かつ子の kind が structured chat 対応 → 子も `.appServer`（＝チャットから spawn した子はチャットに揃う）。
- それ以外（親が pty／子が非対応 kind／親なし）→ 要求どおりの backend（既定 `.pty`）。

**降格させない**理由: モバイル（明示 `appServer` を送る）や UI 起動（明示 backend を選ぶ）の意図を壊さないため。継承は `DashboardViewModel.spawnNewSession` に局所化し、制御プロトコル・CLI・ControlServer は変更しない（projectID/CWD が既に親から継承される既存パターンに揃える）。

### 3. wait の完了検知は「submit 時スナップショット＋done で消費」で send と相関させる

`send` と `wait` が別リクエストである以上、wait 開始時に baseline を取るとレースは閉じない。**submit の瞬間に `completedTurnSeq` をスナップショット**（`submitBaselineTurnSeq`）し、`waitUntilDone` は `completedTurnSeq > submitBaselineTurnSeq` でも done を返す。これで「submit の turn が wait 開始前に完了していた」レースでも done になる。

**done を返したら `submitBaselineTurnSeq` を消費（nil 化）**する。消費しないと、fresh submit を伴わない単独の `wait`（二重 wait・ポーリング・自分が送っていない子への wait）が前 turn の古い出力で即 done を返す stale-done が残る（旧挙動は「次の turn を待つ＝timedOut」）。消費は `waitUntilDone` が done を返す**全経路**（既存 `completedTurnSeq > baselineTurnSeq`／追加 `submitBaselineTurnSeq`／sentinel 一致）で行い、`timedOut`/`notFound` では消費しない。

**タイムスタンプ（`Date()`）でなくカウンタを使う**理由: `Date()` は非単調で、NTP 巻き戻し等で「前 turn の完了時刻 ≥ 新 submit 時刻」が偽成立し running 中に false-done しうる。整数カウンタ比較なら happens-after が安全に判定でき、deadline 判定の `ContinuousClock`（単調）と整合する。

## 結果

- チャットモードのエージェント（claude/codex/cursor）がターミナルモードと同様に `$PHLOX_CLI` で他エージェントを spawn/send/wait できる。チャットから spawn した子もチャットで立つ。
- レースと stale-done を構造的に閉じた。「submit を1回性のマーカーとして消費する」状態機械が両問題を同時に解く。
- ターミナルモードの挙動は不変（回帰なし）。
- 既知の残余（実害小・非回帰）: カウンタ方式は完了を特定の submit に厳密には紐付けられず、turn 実行中の2回目 submit で aliasing しうる（turn ベースのエージェントは実行中に新 submit を受けない前提。旧タイムスタンプ方式でも同種）。
- 未解決の別事象: `spawn --kind cursor` の初回（cold）は `cursor-agent` の chat ID 生成通信で数分かかることがある（2回目以降は速い＝cold-start latency。本 ADR の対象外）。

## 参照

- 構造の現状: architecture/chat-orchestration.md
- 作業経緯: delivery/0008-chat-mode-orchestration-parity-worklog.md
- 前提: ADR 0015（structured chat backend）
