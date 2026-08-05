---
status: completed
last-verified: 2026-08-05
---

# 0035: 競合比較ギャップ改善（セッション隔離・変更一覧のスコープ化・git 書き込み・テスト安定化）

> **このファイルの役割**: 2026-08-02〜05 の agentic-loop run（backend=codex・タスク10件のうち6件完了）の
> 作業経緯・状態スナップショット・積み残し。
> **書かないもの**: 恒久仕様（→ [specs/competitor-gap-remediation-plan.md](../specs/competitor-gap-remediation-plan.md)）、
> 決定の理由（→ ADR [0169](../adr/0169-editor-panel-git-write-operations.md)・[0170](../adr/0170-worktree-isolation-aborts-instead-of-falling-back.md)）。

## やったこと

| task | 内容 | 状態 |
|---|---|---|
| task-1 | 同一作業ディレクトリで動くセッションの衝突検知と可視化 | done |
| task-2 | セッションごとの git worktree 隔離（オプトイン） | done |
| task-3 | 変更一覧を選択セッション基準にし、帰属不能を明示する | done |
| task-4 | エディタパネルから commit / push / PR 作成を製品内で完結させる | done |
| task-5 | カスタムエージェント追加機構の陳腐化した記述を実装に合わせる | done |
| task-6 | コミットパネルの到達性（最小幅での崩れ）改善 | **見送り** |
| task-7 | テストスイートの安定化（`@MainActor` テストの過剰購読の解消） | done |
| task-8 / 9 / 10 | 下記「積み残し」 | pending |

## 決定の要点

- **worktree 隔離の失敗時は起動を中止する**（フォールバックしない）→ ADR 0170。計画書が
  「明示エラー後にフォールバック」と「サイレントフォールバックしない」を併記していた自己矛盾を、
  独立検証の指摘を受けてユーザー判断で確定した。
- **ADR 0150（stage/commit/push はスコープ外）を覆す新 ADR を先に起こしてから task-4 を実装した** → ADR 0169。
- **セッション復元は `spawnNewSessionImpl` を通らない**（`SessionRestoreCoordinator` が
  `prepareSessionLaunch` を直接呼ぶ）。よって衝突検知・worktree 生成は `prepareSessionLaunch` 側に置いた。
  「全経路が通る単一 choke point に置く」方針自体は ADR 0028 で既に確立している。
- **テストスイートの不安定さの原因は、548 件超の `@MainActor` テストが単一の main thread を並列で
  奪い合う過剰購読**だった。`--no-parallel` で直列化して解消（テストのソースは 1 行も変えていない）。
  走らせ方の正本は `macos/scripts/run-swift-tests.sh`（追跡済み）に置いた。

## この run で露出した既存バグ

- **隔離を中止したのにエージェントが起動する**: 復元経路の `makeRestoreErrorSession` が生きた
  `SpawnRequest` を保持しており、中止の約 150ms 後に起動していた（静穏待ちで 6/6 再現）。
  task-2 が新しい到達経路を作って露出させた潜在バグで、`AcceptanceRestoreAbortNoSpawnTests` を
  凍結して塞いだ。

## 見送った task-6

最小ドロワー幅（280pt）でのみ起きる崩れを直すタスクだったが、13pt を捻出する唯一の手段が
「無効理由ラベルを隠す」であり、それは ADR 0169 の決定 6（理由ラベルは同時に見えること）と
正面から衝突する。片方の欠陥を、決定に反する別の欠陥と交換することになるため中止した。

- 第3ラウンドの実装は `git stash`（不採用）に退避。凍結した受け入れテストは `81cfdca` で撤去（`887c90d` / `e7834cb` に残る）。
- **再開するなら**: 最小幅を上げて折り返しを減らせば何も隠さずに収まるかを先に実測すること。

## 積み残し（次 run へ持ち越し）

| task | 内容 |
|---|---|
| task-8 | `ImageRenderer` のアニメーションが収束せず main thread を占有し続ける |
| task-9 | 受け入れテストに残る壁時計依存の締切（0.5〜2 秒）の撤廃。成功基準は「並列に戻しても green」 |
| task-10 | `PHLOX_DEFAULTS_SUITE`（`setenv` によるプロセス共有状態）の DI 化。直列化で干渉は起きなくなったが、**欠陥が消えたのではなく見えなくなっただけ** |

## 検証

- `.claude/verify.sh`（AgentDomain / DesignSystem / MessageStore / SessionFeature / DashboardFeature）: 各タスクの完了確認で再実走し全 pass。
- Debug ビルド: `xcodebuild -scheme Phlox -configuration Debug` が `BUILD SUCCEEDED`（error 0 件）。
- 実行環境: 本体 `/Users/ryosuke/Projects/Phlox-oss` が別 run でロック中だったため、
  `Phlox-oss-worktrees/plan-remediation` に隔離して実施した。

## この run のプロセス上の学び

受け入れテストの欠陥が、実装が終わってから独立レビューで発覚するケースが 2 件あった（実際の
呼び出し経路と違う構成で測っていた／製品では到達しない状態から呼んでいた）。どちらも凍結前に
実物を一度動かせば判るもので、1 巡分の手戻りになった。この経験は `agentic-loop` スキル側へ
**フェーズ1.5（受け入れテストの凍結前検証）と変異検査の機械化**として反映済み。
