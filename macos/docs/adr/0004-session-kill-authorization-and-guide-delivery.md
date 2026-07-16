---
status: active
last-verified: 2026-07-04
---

# ADR 0004: セッション kill の所有者認可とガイド配信の kind 別化

- ステータス: Accepted（実装・検証済み、v0.3.0 で出荷）
- 作成日: 2026-06-10
- コンテキスト: ControlServer はトークン認証のみで認可が無く、有効トークン1つで任意セッションを kill できた。あわせて spawn 時のオーケストレーションガイド配信がユーザーのリポジトリへ無断でファイルを書く／上書きしていた。両者の決定と、見送った理想案（リポジトリ外 hooks 注入）の検証結果を記録する。

> **更新(2026-07-06, ADR 0035)**: 本 ADR の「ガイド配信」部（後述 §2.2 と 2026-06-14 更新注記）は **ADR 0035 で廃止**——オーケストレーションガイドの全種別自動注入を撤去し、基本手順は `/phlox-cli` スキルへ移設した。本 ADR の **kill 認可**の決定は存続する。

## 1. 背景

### 課題 A: kill に認可が無い
ControlServer は Bearer トークンで「誰の要求か（requester）」を認証するが、その requester は spawn/sendText でしか使われず、remove(kill)/rename では捨てられていた（`ControlActionHandler`）。結果、有効なトークンを1つ持てば UUID 指定で**任意のセッションを kill** できた。トークンは子の環境変数（`PHLOX_TOKEN`）と平文 JSON に存在するため、子が触れたコードが他セッションを破壊し得る。エージェントが `--yolo` 相当で動く前提では、脅威の現実度は「悪意」より「事故・暴走の波及」が主。

### 課題 B: ガイド配信がリポジトリを汚す
`OrchestrationGuide.install` は spawn のたびに `CLAUDE.md` / `AGENTS.md` / `.cursor/rules/phlox.mdc` を作業ディレクトリへ書いていた。プロジェクトがユーザーの実リポジトリ（非管理ディレクトリ）のとき同意なくファイルを作り、`projectID==nil` の隔離 CWD では既存ファイルを上書きする穴もあった。Claude は `--append-system-prompt` が使えるのに短いポインタしか渡さず、手順はファイル依存だった。

## 2. 決定事項

### 2.1 kill を「自分自身＋子孫」のみに制限
- 親子関係を **`SessionViewModel.parentSessionID`** に単一ソースで保持し、`PersistedSessionDescriptor` に Optional で永続化（後方互換）。descriptor 変換は copy-update ヘルパーに集約し、全 re-persist 箇所で親 ID を引き継ぐ。
- 中間親を kill したときは子を祖父母へ **reparent**（孤児化回避）。**※ この reparent 挙動は ADR 0013（2026-06-17）で廃止され、親削除時は子孫を再帰的にカスケード削除する方式へ置換された。**
- depth は parentSessionID チェーンから都度算出（旧 `sessionDepths` 撤去）。復元は全 descriptor から親リンクを確定してから扱う（順序非依存・深さ制限の迂回防止）。
- `DashboardViewModel.isAuthorizedToRemove(_:requester:)`: `requester==nil`(UI/内部)・自分自身・祖先 のみ true。`ControlActionHandler` の `.remove` で false なら **403**。kill 限定（rename/output 等は対象外）。

### 2.2 ガイド配信を kind 別 + 非上書きに
- `OrchestrationGuide.install(kind:workingDirectory:)`: **Claude は何も書かない**（手順は `--append-system-prompt` でフル注入）、Codex は `AGENTS.md` のみ、Cursor は `.cursor/rules/phlox.mdc` のみ。既存ユーザーファイルは**常に**上書きしない（`projectID==nil` の穴も解消）。
- guide 本文を単一ソース化し、ファイル版と system prompt 版の drift を排除。
- 本文を改善：`list`/`read` の追加、委譲判断、子は会話履歴を共有しない→1メッセージで完結、`wait` 失敗時の `read`→再 `send`、並行手順を明記。

> **更新(2026-06-14, merge `fac14fc`)**: §2.2 のうち **Codex の `AGENTS.md` 配信は廃止**。Codex は `UserPromptSubmit` hook の `additionalContext`（`AgentLaunchPlanner` が codex のみ付与する `PHLOX_ORCHESTRATION_GUIDE` 環境変数を `hook-dispatcher.sh` が emit）で**毎ターン注入**する方式へ移行した（`OrchestrationGuide.install` の codex ケースは何も書かない）。Cursor は `.cursor/rules/phlox.mdc` を **`alwaysApply: true` の Always ルール**化し毎リクエスト注入（既存のアプリ生成旧ルールは新形式へ自動アップグレード）。Claude は従来どおり `--append-system-prompt`。動機は「開始時1回ロードは文脈肥大で遵守率が落ちる」ため各 CLI の native な毎ターン注入経路へ揃えること。

## 3. 採用しなかった案

- **認可の一般化（operation 引数付き共通関数）**: 今回 kill 限定のため専用 `isAuthorizedToRemove` に留めた。rename/output 等へ広げる時点で一般化する。
- **kill 以外（rename/output/wait）への認可拡大**: 今回は kill のみ。将来 §2.1 の仕組みを流用して拡張可能。
- **Codex/Cursor のリポジトリ外 hooks 注入（理想案 C）**: 「ユーザーのリポジトリに一切書かない」を全 CLI で満たす案。ライブ検証の結果:
  - **Cursor は user hooks `~/.cursor/hooks.json` を TUI で発火**＝リポジトリ外注入が**可能**と実証。ただしグローバル副作用（ユーザー自身の cursor セッションでも Phlox の dispatcher が走る／既存 hooks とのマージが必要）があり、Codex は外部 hooks 機構が無い（hooks は cwd `.codex/hooks.json` 限定）。
  - 検証の知見（重要）: **`codex exec` / `cursor-agent -p` などの headless モードは hooks を発火しない**。hooks 検証はインタラクティブ(TUI)で行う必要があり、headless の非発火を No-Go の根拠にしてはならない（実際 Codex を一度 No-Go と誤判定し、TUI 再検証で Cursor の可否を確定した）。
  - 結論: 実用重視で **Codex/Cursor は cwd に hooks/guide を維持**（hooks は完了検知に必須の機能であり、外部化の利得が副作用に見合わない）。Claude は system prompt 配信で完全にリポジトリ非汚染。将来 Cursor のみ user hooks へ移す余地は残る（dispatcher の no-op 対応と既存 hooks マージが前提）。

## 4. 影響

- 親子情報を parentSessionID に集約。復元順序に依存せず depth/認可が成立。UI 経由（`requester==nil`）は無影響。
- Claude はガイド全文を system prompt に毎回載せるが、固定 ~500 トークン/セッションでプロンプトキャッシュ対象。従来 `CLAUDE.md` を読み込むのと同等で増加は無い。
- 非管理リポジトリに Claude は何も書かない。Cursor は機能上 cwd に `.cursor/rules/phlox.mdc` と hooks を置くが、既存ユーザーファイルは上書きしない（2026-06-14 更新: Codex は cwd にガイドファイルを書かず hook の `additionalContext` で毎ターン注入。上の「更新」注記参照）。

## 5. 関連

- 実装/出荷: コミット `918aa53`（kill 認可・Claude フル注入）, `4d658e5`（kind 別配信・guide 本文改善）。v0.3.0 で出荷。
- コード: `App/ControlActionHandler.swift`, `DashboardViewModel`（parentSessionID / isAuthorizedToRemove / install 呼び出し）, `OrchestrationGuide`, `PersistedSessionDescriptor`, `SessionViewModel`。
- ADR 0002（配信 readiness）、root `CLAUDE.md` / `AGENTS.md` / `.cursor/rules/phlox.mdc`（同一のガイド本文）。
