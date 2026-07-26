---
status: completed
last-verified: 2026-07-26
---

# claude-code-management run: エージェント設定を Phlox の機能にする worklog

ブランチ `feature/claude-code-management`。

きっかけは [ADR-0120](../adr/0120-slash-suggestions-from-session-init.md) の直後の
ユーザー要求「plugin のようにできるものは全て実装してください。実機検証まで行うこと」。
補完の正本をセッションの提供一覧へ移した結果、対話 TUI 専用の 8 コマンドが
補完から消え、Phlox からそれらの設定に触れなくなっていた。
その後「Codex, Cursor の設定も追加できますか？」を受けて 3 エージェントへ広げた。
設計判断は [ADR-0121](../adr/0121-agent-management-console.md)。

## やったこと

### 第1段: Claude Code（対話 TUI 専用の 8 コマンド）

| 単位 | 内容 | 主な成果物 |
|---|---|---|
| 基盤 | `~/.claude/settings.json` の安全な部分更新（未知キー保存）・メモリファイル探索・`claude` サブコマンド実行 | 新パッケージ `Packages/AgentConfigKit` |
| `/plugin` | `claude plugin ...` の一覧・有効化・導入・更新・削除・マーケットプレイス管理 | `ClaudePluginService`・`ClaudePluginsPane` |
| `/permissions` | allow/ask/deny の追加・削除・バケット間移動 | `ClaudePermissionRules`・`ClaudePermissionsPane` |
| `/memory` | ユーザー/プロジェクトの `CLAUDE.md`・`AGENTS.md` 編集 | `ClaudeMemoryFiles`・`ClaudeMemoryPane` |
| `/hooks` `/statusline` `/output-style` | settings.json 各節の編集 | `ClaudeHookSettings`・`ClaudeStatusLineSettings`・`ClaudeOutputStyleSettings` と各ペイン |
| `/status` | CLI・設定・プラグイン・メモリの現況スナップショット | `ClaudeEnvironmentStatusBuilder`・`ClaudeStatusPane` |
| `/export` | 会話の Markdown 書き出し／クリップボードコピー | `ChatTranscriptExport.swift`（SessionFeature・9 テスト）・`ChatTranscriptExportAction.swift` |
| 入口 | 管理ウィンドウのシーンとメニュー、設定画面のボタン、セッションメニューの書き出し | `PhloxApp.swift`・`SettingsView.swift` |

### 第2段: 枠線の撤去と入口の追加

- ユーザーの指摘「境界線をなくして1枚の板のようにして欲しい。今は合板みたい」を受け、
  ウィンドウから `strokeBorder` を全廃。まとまりは見出しと余白で表し、
  ホバー・選択は淡い面とアクセント色で示す。`NavigationSplitView` は列の区切り線を
  必ず引くため素の `HStack` に置き換えた。
- Dashboard 左上、歯車の右に管理ウィンドウを開くボタン（レンチ）を追加。

### 第3段: Codex と Cursor

| 単位 | 内容 | 主な成果物 |
|---|---|---|
| 改名 | `ClaudeConfigKit` → `AgentConfigKit`。共通部を `Shared/` へ、固有部を `Claude/` `Codex/` `Cursor/` へ | パッケージ全体・`project.yml` |
| TOML | `config.toml` の**行を保つ**外科的エディタ（読み・書き・削除、無変更なら 1 バイトも変えない） | `TOMLDocument`（14 テスト） |
| Codex 設定 | モデル・思考の深さ・人格・承認・サンドボックス・ティアの読み書き。控えを残す保存 | `CodexSettingKey`・`CodexGeneralSettings`・`CodexConfigStore` |
| Codex 信頼設定 | `[projects."<path>"]` の列挙・切替・削除（277 件を絞り込みで扱う） | `CodexProjectTrust`・`CodexTrustPane` |
| Codex CLI | `codex plugin` / `codex mcp` の実行と `--json` パース | `CodexPluginService`・`CodexMCPService` |
| Cursor | 15 設定項目・権限・既定モデル・MCP。`authInfo` は画面にも書き込みにも出さない | `CursorSettingKey`・`CursorPermissionRules`・`CursorModelSettings`・`CursorMCPServers` |
| UI | サイドバーを 3 グループ・計 18 区分に。新規ペイン 11 枚 | `AgentConsoleSection`・`AgentConsoleWindowView`・各 Pane |

候補値は推測せず、Codex の実行ファイル（`strings`）と cursor-agent の JS バンドルから
抽出した。加えて `options(current:)` が「ファイルに入っている見知らぬ値」も選択肢に残すので、
Phlox が知らない値を黙って上書きしない。

architecture 反映: `agent-management-console.md`、
`package-structure.md` の `AgentConfigKit`（L0）。

## 実機検証（デバッグビルド `com.phlox.Phlox.debug`）

デバッグビルドは常に**キーチェーンレス**で起動する
（`open -n --env PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1 <app>`。`open -a` では env が渡らない）。
`ps eww <pid>` で変数の到達を、`pgrep -x SecurityAgent` でダイアログ不在を確認した。

ビジョン検証で確認したもの（すべてスクリーンショットで目視）:

- メニュー「Phlox ▸ エージェント管理…」Cmd+Shift+, でのウィンドウ表示、
  Dashboard のレンチボタンの表示位置（歯車の右）
- 18 ペインすべてが実データを描画すること。主なもの:
  Claude（CLI 2.1.220 / モデル opus[1m] / 権限 33 件 / フック 18 件 / プラグイン 11 件）、
  Codex（CLI 0.144.6 / gpt-5.6-sol / medium / pragmatic / 信頼済み 277 件 /
  プラグイン 9 件 / MCP 4 件 / `~/.codex/AGENTS.md` の実体が `~/.claude/AGENTS.md` である旨の表示）、
  Cursor（CLI 2026.07.20-8cc9c0b / Composer 2.5 / allowlist / 選べるモデル 190 件）
- セッション ▸「会話を Markdown でコピー」→ クリップボードに 772 行の Markdown
- セッション ▸「会話を書き出す…」→ 既定名 `Jasmine-20260726-1105.md` で保存、44,759 バイト

### `config.toml` 書き込みの実地検証

最も壊すと痛い経路なので、実ファイルに対して 3 段で確かめた。

1. **読み取りのみ**: 実 `~/.codex/config.toml` を `TOMLDocument` で往復させ、
   テキストが 1 バイトも変わらないことと、1 キー変更が 1 行だけを変えることを確認。
2. **実書き込み**: 管理画面から思考の深さを `medium` → `high` に変更。
   `diff` の結果は `model_reasoning_effort` の 1 行のみ。
   控え `config.toml.phlox-backup` は変更前の内容と SHA-256 一致。
3. **復元**: 画面から `medium` へ戻し、ファイルが元と SHA-256 完全一致に戻ることを確認。

Cursor 側も実 `cli-config.json`（トップレベル 24 キー）に対して、
2 項目の部分更新後にキー集合が変わらず `authInfo` が同一のままであることを確認した。

## 途中で見つけて直したもの

- **ペインの見出しがタイトルバーへ潜り、サイドバーごと上へずれる**。原因は
  説明文に付けた `fixedSize(horizontal:false, vertical:true)`。
  幅が確定する前の測定で巨大な理想高さ（実測で約 886pt）が出ていた。`lineLimit(2)` に変更。
- **プラグイン一覧が同じ行を二重に描く**。user と project の両方に入っている
  プラグインで `pluginID` が衝突していた。identity を `"<pluginID>#<scope>"` に変更。
- **`Task.detached` が `sending value of non-Sendable type` でコンパイルできない**。
  可変ローカル変数（`var path`）をキャプチャしていたため。不変のコピーを渡す形に変更。

## テスト

18 パッケージ全数を `swift test` で実走、**2,950 件 pass / 0 fail**（2026-07-26）。
内訳の主なもの: DashboardFeature 1454、SessionFeature 385、AgentDomain 232、
AppBootstrap 148、ClaudeAgentKit 132、ControlServer 113、AgentConfigKit 79。

## 検証時の落とし穴（次回のため）

- AppleScript の `first process whose unix id is N` は、**同名プロセスが複数あると
  別プロセスを返す**ことがある。本番 Phlox（`com.phlox.Phlox`）とデバッグ版
  （`com.phlox.Phlox.debug`）は AX 上どちらも `Phlox` なので、`every process` を
  ループして `bundle identifier` で選ぶこと。この取り違えで「メニュー項目が出ない」と
  数回誤判定した。
- **前回 run のデバッグ版が生き残っていると、新しいビルドを起動しても古い方を掴む**。
  `bundle identifier` で選んでも同じなので、検証前に
  `pgrep -f "build-verify/.../Phlox.app"` で全数を確認して落としてから起動する。
  「新しい窓名が出ない」を実装バグと誤診しかけた。
- `screencapture -R` の切り出しを `sips -Z N` で縮小すると、**倍率は長辺基準**。
  縦長ウィンドウ（例 520×672）で横基準の倍率を使うとクリック座標が全部ずれる。
- AppleScript の `position of w as string` は要素を区切りなしで連結するため
  `1111,358` が `1111358` に見える。`item 1 of p` / `item 2 of p` で明示的に組む。
- `cliclick` が無い環境では、CGEvent の click/scroll を 1 ファイルの Swift で
  `swiftc` して使う（`macos-ui-test-applescript.md` の CGEvent ワンショット）。
