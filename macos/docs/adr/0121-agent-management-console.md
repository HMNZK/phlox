---
status: active
last-verified: 2026-07-26
---

# ADR-0121: 対話 TUI・設定ファイル手編集でしか触れない設定を Phlox の管理画面へ集約する（Claude Code / Codex / Cursor）

## 文脈

[ADR-0120](0120-slash-suggestions-from-session-init.md) で、補完候補の正本を
セッションの `system`/`init` が運ぶ `slash_commands` に移した。その結果、
`/plugin` `/permissions` `/memory` `/hooks` `/statusline` `/output-style`
`/status` `/export` は**補完から消えた**。これらは Claude Code の対話 TUI が
自前の画面として実装しているコマンドで、Phlox が使うヘッドレスの
`--print --output-format stream-json` セッションには存在しないためである。

補完の正しさは回復したが、「Phlox からはこれらの設定に触れない」という機能欠落が残った。
同じ欠落は Codex・Cursor にもある。どちらも設定変更の入口は対話 TUI か
設定ファイル（`~/.codex/config.toml` / `~/.cursor/cli-config.json`）の手編集しかなく、
Phlox から起動したセッションの設定を Phlox の中で確認・変更できなかった。

調査の結果、置き換えの手段は 3 系統あった:

1. **非対話 CLI がある**: `claude plugin {list,install,...}`、`codex plugin ...`、
   `codex mcp ...`、`cursor-agent models` / `cursor-agent mcp {enable,disable}` は
   `--json` などを備え、TTY なしで完結する。
2. **設定ファイルが正本**: Claude の権限・フック・ステータスライン・出力スタイルは
   `~/.claude/settings.json`、Codex のモデル・思考の深さ・サンドボックス・信頼設定は
   `~/.codex/config.toml`、Cursor の承認モード・表示・Git 名義は
   `~/.cursor/cli-config.json` が正本で、TUI はその編集 UI にすぎない。
   メモリ（`CLAUDE.md` / `AGENTS.md`）も同じくファイルが正本。
3. **Phlox 側にデータがある**: `/export`（会話の書き出し）は Claude Code ではなく
   Phlox のトランスクリプトから生成できる。

## 決定

3 エージェント分の設定を、Phlox ネイティブの1つの画面へ集約する。

- **「エージェント管理」ウィンドウ**（`Window` シーン、Cmd+Shift+,）のサイドバーに
  **Claude Code / Codex / Cursor の 3 グループ**を縦に並べ、計 18 区分を置く。
  Claude の各行には対応するスラッシュコマンド名（`/status` 等）を、
  Codex・Cursor の各行には設定の実体（`config.toml`・`permissions` 等）を併記する。
- エージェントの**切替器（セグメント/タブ）にはしない**。3 エージェントを見比べながら
  触る用途が主で、切替器だと「いま何を見ているか」を保持する状態が増えるため。
- **会話エクスポート**はウィンドウではなくセッションメニューに置く（対象が
  「いま選んでいるセッション」であり、グローバルな設定ではないため）。
- 土台は新パッケージ **`AgentConfigKit`**（L0・依存なし）に置く。
  `Shared/`（JSON・TOML・CLI 実行・メモリファイル）を 3 エージェントで共有し、
  `Claude/` `Codex/` `Cursor/` に各エージェント固有のモデルを置く。UI は App ターゲット側。

### 設定書き込みの原則: 知らないキーを壊さない

3 つの設定ファイルはいずれもユーザーが手で育てる資産で、Phlox が知らないキーが
必ず含まれる。そのため書き込みは常に**部分更新**にする。

| ファイル | 方式 |
|---|---|
| `~/.claude/settings.json` | `JSONValue`（型付き列挙）で読み書きし、触るキーだけを差し替える。出力は `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` ＋末尾改行 |
| `~/.cursor/cli-config.json` | 同じ `JSONValue`。`authInfo`（認証情報）とキャッシュは**画面に出さず、書き込みでも触らない** |
| `~/.codex/config.toml` | `TOMLDocument`（下記）で該当行だけを差し替える |

### `config.toml` を編集する（従来方針の転換）

Phlox はこれまで `~/.codex/config.toml` を**編集しない**方針だった
（`CodexUserHooksManager` の "It never edits `~/.codex/config.toml`"）。
理由は、あのファイルがコメント・順序・手書きの構造を持つユーザー資産で、
汎用 TOML ライブラリで読んで書き戻すと**元の見た目が失われる**ためである。

今回この方針を転換し、編集を解禁する。代わりに壊さないための仕掛けを 3 つ置く。

1. **行を保つ外科的エディタ `TOMLDocument`**。文書を行の配列として持ち、
   目的のキーの**その行だけ**を差し替える。再シリアライズしない。
   無変更なら 1 バイトも変わらないことをテストで固定する。
2. **書き込み前に 1 世代の控え**を `config.toml.phlox-backup` へ残す。
   内容が変わらない保存はスキップし、控えを無駄に潰さない。
3. **プラグインと MCP は CLI に任せる**。`[plugins.*]` / `[mcp_servers.*]` の
   組み立ては引数の引用規則まで含めて Codex 側の契約なので、Phlox は
   `codex plugin` / `codex mcp` を呼ぶだけにする。Phlox が直接書くのは
   スカラーのトップレベル設定と `[projects."<path>"]` の信頼設定に限る。

選択肢のあるキー（思考の深さ・人格・承認・サンドボックス等）の候補値は
推測せず、**Codex の実行ファイルと cursor-agent の JS バンドルから抽出**した。
そのうえで、ファイルに入っている見知らぬ値も選択肢として残す
（知らない値を選択肢から外して黙って上書きしないため）。

### なぜ TUI を埋め込まないのか

各 CLI の TUI をそのまま PTY で開いて `/plugin` を送る、という選択肢もあった。
採らなかった理由:

- Phlox のセッションはヘッドレスで、そこへ TUI を混ぜると1セッションの状態が二重になる。
- 設定変更のために別 PTY を起こすのは、目的（設定を1つ変える）に対して重い。
- TUI の画面遷移をスクレイプする形になり、CLI の更新で壊れる。

非対話 CLI と設定ファイルはどちらも公開された契約で、TUI の内部描画より安定している。

## 結果

- Phlox 単体で、3 エージェントの設定を確認・変更できる。
  Claude: プラグイン・権限・メモリ・フック・ステータスライン・出力スタイル。
  Codex: モデル/思考の深さ/人格/承認/サンドボックス・プラグイン・MCP・メモリ・信頼設定。
  Cursor: 承認/表示/Git 名義・権限・既定モデル・MCP。
- CLI が見つからない環境では、その CLI を必要とする区分だけが
  「〜コマンドが見つかりません」になり、設定ファイル系の機能は動く。
- `AgentConfigKit` は UI を持たず依存もないため、CLI 出力・設定ファイルの
  パースと再構成をユニットテストで固定できる（79 件）。
- `config.toml` を壊すと Codex が起動しなくなるため、`TOMLDocument` の
  往復不変性テストが最重要の回帰ゲートになる。実ファイル（`[projects]` 277 件）
  に対しても往復が 1 バイトも変わらないことを確認済み。
- 各 CLI が JSON 形状や列挙値を変えたら、対応する `*Parsing` / `*SettingKey` の
  テストが落ちる。未知キー・未知値は無視せず温存する実装なので、追加では壊れない。
