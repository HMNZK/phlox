---
status: active
last-verified: 2026-07-26
---

# エージェント管理コンソール

Claude Code の対話 TUI にしか無いスラッシュコマンド（`/plugin` `/permissions` `/memory`
`/hooks` `/statusline` `/output-style` `/status` `/export`）と、Codex・Cursor の
設定ファイル手編集でしか触れない項目を、Phlox ネイティブの画面として持つための構成。
なぜこの形かは [ADR-0121](../adr/0121-agent-management-console.md)。

## 入口

| 入口 | 実体 |
|---|---|
| メニュー「Phlox ▸ エージェント管理…」（Cmd+Shift+,） | `AgentConsoleCommands`（`CommandGroup(after: .appSettings)`）→ `openWindow(id: "agent-console")` |
| Dashboard 左上・歯車の右のレンチアイコン | `DashboardLeadingTopBarControls`（`agentConsoleWindowID` が nil ならボタンを出さない） |
| 設定 ▸ エージェント ▸「エージェント管理を開く」 | `SettingsView` の `openWindow(id:)` |
| メニュー「セッション ▸ 会話を書き出す…」（Cmd+Shift+E）/「会話を Markdown でコピー」 | `SessionCommands` → `ChatTranscriptExportAction` |

管理ウィンドウは `Window("エージェント管理", id: AgentConsoleCommands.windowID)`
シーン（`defaultSize` 900×620）。メインウィンドウ（`WindowGroup`）とは独立に開閉する。

## ウィンドウの構造

```
AgentConsoleWindowView（素の HStack）
├─ sidebar : AgentConsoleAgent ごとのグループ（Claude Code / Codex / Cursor）＋
│            AgentConsoleSection の行（対応コマンド名または設定の実体を併記）
└─ detail  : messageBar（いま見ているエージェントの結果/失敗の帯）＋ 各ペイン
             AgentConsolePane（見出し＋説明＋右上ツールバー＋操作帯＋本文）で枠を共通化
```

`NavigationSplitView` ではなく素の `HStack` で組む。分割ビューは列の境目に
必ずシステムの区切り線を引き、サイドバーにも独自の面を敷くため、
「窓全体を1枚の板として見せる」という方針と両立しない（項目は固定数なので
列の折りたたみ・リサイズも要らない）。同じ理由で `List(selection:)` も使わず、
選択行はテーマのアクセント色で自前に描く。

### セクション（計 18）

| グループ | セクション | 元コマンド / 実体 | ペイン | 主な操作 |
|---|---|---|---|---|
| Claude Code | 状態 | `/status` | `ClaudeStatusPane` | CLI・settings.json・モデル・各件数 |
| Claude Code | プラグイン | `/plugin` | `ClaudePluginsPane` | 一覧/追加、有効化、更新・削除、マーケットプレイス |
| Claude Code | 権限 | `/permissions` | `ClaudePermissionsPane` | 許可/確認する/拒否 の追加・削除・移動 |
| Claude Code | メモリ | `/memory` | `ClaudeMemoryPane` | `CLAUDE.md`・`AGENTS.md` の編集 |
| Claude Code | フック | `/hooks` | `ClaudeHooksPane` | イベント・matcher・コマンド・timeout |
| Claude Code | ステータスライン | `/statusline` | `ClaudeStatusLinePane` | 有効/無効・コマンド・余白 |
| Claude Code | 出力スタイル | `/output-style` | `ClaudeOutputStylePane` | 既定 / Explanatory / Learning ＋ 自作 |
| Codex | 状態 | `config.toml` | `CodexStatusPane` | CLI・config.toml の場所・各値・件数 |
| Codex | 設定 | `model` / `sandbox` | `CodexSettingsPane` | モデル・思考の深さ・人格・承認・サンドボックス・ティア |
| Codex | プラグイン | `codex plugin` | `CodexPluginsPane` | 導入・削除・マーケットプレイス |
| Codex | MCP | `codex mcp` | `CodexMCPPane` | stdio / HTTP サーバーの追加・削除 |
| Codex | メモリ | `AGENTS.md` | `CodexMemoryPane` | `~/.codex/AGENTS.md` 等の編集 |
| Codex | 信頼設定 | `[projects]` | `CodexTrustPane` | 信頼の切替・登録削除（絞り込み付き） |
| Cursor | 状態 | `cli-config.json` | `CursorStatusPane` | CLI・設定ファイルの場所・モデル・件数 |
| Cursor | 権限 | `permissions` | `CursorPermissionsPane` | 許可/拒否 の追加・削除・移動 |
| Cursor | モデル | `model` | `CursorModelPane` | 既定モデルの選択（一覧は CLI から取得） |
| Cursor | MCP | `mcp.json` | `CursorMCPPane` | サーバーの追加・削除・有効/無効 |
| Cursor | 設定 | `display` / `git` | `CursorSettingsPane` | 承認モード・サンドボックス・表示・Vim・Git 名義 |

### モデル層

エージェントごとに `@MainActor @Observable` のモデルを 1 つ持ち、ウィンドウが 3 つとも保持する。

| モデル | 読み込み | 書き込み |
|---|---|---|
| `ClaudeConsoleModel` | `loadSettings` / `loadVersion` / `loadPlugins` | `applySettings` / `writeMemory` / `performPluginOperation` |
| `CodexConsoleModel` | `loadConfig` / `loadVersion` / `loadPlugins` / `loadMCPServers` | `applyConfig` / `writeMemory` / `performPluginOperation` / `performMCPOperation` |
| `CursorConsoleModel` | `loadSettings` / `loadVersionAndModels` | `applySettings` / `applyMCP` / `setMCPEnabled` |

一覧の取得に CLI 起動が要るもの（Codex のプラグイン・MCP）は、ウィンドウを開いた瞬間では
なくそのペインの `.task` で読む。

### CLI パスは後から届く

アプリの composition（`claudeBinaryPath` の解決を含む）より前にウィンドウ復元が走る経路が
あるため、`AgentConsoleWindowView` は `claudeExecutablePath` を「後から届く値」として扱う。

- `.task(id: claudeExecutablePath)` で値が変わるたびに読み直す。
- 復元が先行して nil のままの場合は、`BinaryPathResolver.resolvePathEnvironment()` で
  login shell の PATH を取り直し、そこから `claude` / `codex` / `cursor-agent` を探す
  （GUI プロセスの PATH は最小限のため）。解決は 1 回の `Task.detached` にまとめる。
- 解決結果は各モデルの `updateEnvironment(...)` で流し込む。

### ペイン枠の高さ制約

`AgentConsolePane` の説明文に `fixedSize(horizontal:false, vertical:true)` を付けると、
幅が確定する前の測定で「1文字ずつ折り返した」巨大な理想高さが算出され、
レイアウト全体が上へずれて見出しがタイトルバーへ潜る。説明文は `lineLimit(2)` で
高さを抑える。

## AgentConfigKit（L0・依存なし）

UI を持たない土台。App ターゲットからのみ参照する。

### Shared（3 エージェント共通）

| 型 | 役割 |
|---|---|
| `JSONValue` / `JSONValueCoder` | 設定 JSON の型付き表現。未知キーを保ったまま部分更新する（`value(at:)` / `setting(_:to:)` でネストも辿る）。出力は `prettyPrinted + sortedKeys + withoutEscapingSlashes` ＋末尾改行 |
| `JSONSettingsStore` | JSON 設定ファイルの読み書き（無ければ空オブジェクト、壊れていれば throw、保存は原子的） |
| `TOMLDocument` | TOML の**行を保つ**外科的エディタ。読み（`string`/`bool`/`integer`/`stringArray`/`subtableKeys`）と書き（`setString`/`setBool`/`setInteger`/`setRaw`/`removeKey`/`removeTable`）を持ち、変えた行以外は 1 バイトも触らない |
| `AgentMemoryFile` / `AgentMemoryFileStore` | メモリファイルの表現と読み書き。シンボリックリンクはリンク先の実体へ書く |
| `AgentCommandRunning` / `AgentProcessCommandRunner` | CLI サブコマンドの実行（PATH と `CI=1` を与え、`waitUntilExit` の前にパイプを読む） |
| `AgentCommandOutput` | 出力から JSON 部分だけを取り出す（案内文が前置きされる CLI 用） |

### Claude

`ClaudeConfigPaths` / `ClaudePermissionRules` / `ClaudeHookSettings` /
`ClaudeStatusLineSettings` / `ClaudeOutputStyleSettings` / `ClaudeMemoryFiles` /
`ClaudePluginService`（`ClaudePluginParsing`）/ `ClaudeEnvironmentStatus(Builder)`。

プラグインの identity は `pluginID`（`name@marketplace`）と別に
`id = "<pluginID>#<scope>"` を持つ。同じプラグインが user と project の両方に
入りうるため、`pluginID` だけだと一覧が同じ行を二重に描く。

### Codex

| 型 | 役割 |
|---|---|
| `CodexConfigPaths` | `~/.codex` 配下（`config.toml`・控え・`AGENTS.md`） |
| `CodexConfigStore` | `config.toml` の読み書き。**書き込み前に現在の内容を `config.toml.phlox-backup` へ複製**し、無変更の保存はスキップする |
| `CodexSettingKey` / `CodexGeneralSettings` | トップレベル設定 6 種の表示名・説明・候補値と読み書き。空文字を渡すとキーごと削除して既定へ戻す |
| `CodexProjectTrust(Settings)` | `[projects."<path>"]` の列挙・信頼切替・削除 |
| `CodexPluginService` / `CodexMCPService` | `codex plugin` / `codex mcp` の実行と `--json` 出力のパース |
| `CodexMemoryFiles` / `CodexEnvironmentStatus(Builder)` | メモリ探索と状態スナップショット |

候補値（思考の深さ `none…ultra`、人格 `friendly`/`pragmatic`、承認 4 種、
サンドボックス 3 種、ティア 3 種）は Codex の実行ファイルから抽出したもの。
`options(current:)` は、ファイルに入っている見知らぬ値を先頭に足して残す。

### Cursor

| 型 | 役割 |
|---|---|
| `CursorConfigPaths` | `~/.cursor/cli-config.json` と `mcp.json` |
| `CursorSettingKey` / `CursorGeneralSettings` | 15 項目の位置（`["display","zenMode"]` 等）・種別（トグル/選択）・グループ（動作/表示/Git）と読み書き |
| `CursorPermissionRules` | `permissions.{allow,deny}` の抽出・適用・追加/削除/移動。Cursor は空でもキーを持つので空配列を残す |
| `CursorModelSettings` | 既定モデル。`model` と `selectedModel` の両方を揃えて書く（片方だけだと表示と実際がずれる） |
| `CursorMCPServers` | `mcp.json` の読み書き（一覧は JSON 直読み、有効/無効だけ CLI） |
| `CursorCommandService` / `CursorEnvironmentStatus(Builder)` | `cursor-agent` の実行と状態スナップショット |

`cli-config.json` には `authInfo`（認証情報）とキャッシュが同居する。画面には出さず、
書き込みは常に部分更新なので触れない。

## 会話エクスポート

管理ウィンドウではなくセッションメニューにある（対象が選択中セッションのため）。

- `ChatTranscriptExporter.markdown(items:metadata:options:)`（`SessionFeature`）が
  `ChatItem` の全ケースを Markdown へ落とす。既定は reasoning を含めず、
  コマンド出力とタイムスタンプを含める。
- `ChatTranscriptExportAction`（App ターゲット）が、選択中セッションの解決・
  `NSSavePanel` での保存・クリップボードへのコピーを担う。
- 既定のファイル名は `<セッション名>-<yyyyMMdd-HHmm>.md`。
