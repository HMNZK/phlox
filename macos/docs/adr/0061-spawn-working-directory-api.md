---
status: active
last-verified: 2026-07-10
---

# ADR 0061: API/CLI spawn に workingDirectory を追加し、検証は ControlActionHandler の単一関所に置く

## 文脈

`POST /sessions` と `phlox spawn` には子セッションの作業ディレクトリを指定する口が無く、子は常に親（requester）の workspace を継承していた。このため「サブPMセッションを git worktree に着地させる」形の階層型オーケストレーション（loopflow 階層型）が構造的に成立しなかった（外部検証: loopflow-sandbox リポジトリの ADR 0001 で実測）。App 内部には `spawnNewSession(workingDirectoryOverride:)` の配線が復元経路（`SessionRestoreCoordinator`）用に既に存在し、欠けていたのは API 境界（ControlServer→AppBootstrap→App witness）と CLI の露出だけだった。

## 決定

1. `POST /sessions` body に省略可能な `workingDirectory`（文字列・絶対パス）を追加し、`Action.spawn(ref:backend:workingDirectory:)` → `ControlActionDashboard.spawnSession(ref:from:backend:workingDirectory:)` → App witness → `spawnNewSession(workingDirectoryOverride:)` へ透過する。CLI は `phlox spawn --dir <path>`（省略時はフィールド自体を送らない）。
2. **検証は `ControlActionHandler.handleSpawn` の1箇所だけ**で行う: 絶対パス・存在・ディレクトリ（symlink-to-dir は許容）。不正・空文字は 400（`error` に "workingDirectory" を含む）で **spawn を発火させない**。省略（nil）は現行挙動（親 projectID 継承 → Phlox 管理ワークスペース）と完全等価。

## 棄却した代替案

- **パース層（ControlServer）での検証** — ControlServer はファイルシステムに関知しない純粋なプロトコル層であり、責務が漏れる。パース層は値を verbatim に運ぶだけとした。
- **VM 層（`spawnNewSession`）での検証** — 復元経路が同じ `workingDirectoryOverride` を使っており、保存済みディレクトリが後から消えた場合に**セッション復元自体が壊れる**。信頼できない入力の入口（API 境界）だけで検証するのが正しい。
- **不正パス時の黙示フォールバック（親継承で続行）** — 呼び出し側が「指定が効いた」と誤認する。オーケストレーションでは worktree 隔離が安全性の前提のため、誤着地はデータ競合に直結する。明示の 400 で拒否する。

## 結果

- 階層型オーケストレーションの前提能力（worktree への子着地）が API/CLI から利用可能になった。利用には本変更を含むビルドの Phlox が必要。
- 受け入れテスト: `SpawnWorkingDirectoryAcceptanceTests`（ControlServer）・`SpawnWorkingDirectoryHandlerAcceptanceTests`（AppBootstrap）が契約を凍結。
- 制約: `--backend` は CLI 未露出のまま（API のみ）。必要になったら別 run で追加する。

## 関連

- 実装 worklog: `docs/delivery/0033-spawn-workdir-worklog.md`
- 現行挙動の記述: `docs/architecture/chat-orchestration.md` §2b
- ADR 0058（spawn 総数上限の撤廃）— spawn 入口の直近の変更
