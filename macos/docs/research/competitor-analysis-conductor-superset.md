---
status: active
last-verified: 2026-08-02
---

# 競合分析: Conductor / Superset（並列エージェント実行デスクトップアプリ）

- 作成日: 2026-08-02
- 種別: 競合調査レポート（実装なし）
- 対象バージョン: **Conductor 0.78.1** / **Superset 1.18.1**（2026-08-02 時点で macOS にインストール済みのもの）
- 調査方法: 両アプリを実機で操作（プロジェクト追加 → ワークスペース生成 → エージェント 1 回実走 → 差分レビュー）＋設定画面の全セクションを AX API でダンプ＋アプリバンドル構成の確認＋プロセスの実測メモリ計測＋公式ドキュメントの読解
- 独立レビュー: **実施済み**（Codex / GPT-5.5、read-only サンドボックス、2026-08-02）。詳細と限界は §11。**§9 の Phlox 側の記述はこのレビューで指摘された誤りを反映済み**

> **このファイルの役割**: Phlox の直接競合 2 製品の UI/UX・機能・価格・安全性モデルの調査スナップショットと、Phlox との機能差の記録。
> **書かないもの**: Phlox 側の要件・設計判断（→ `specs/`・`adr/`）。

## 誠実性の注記（この文書の読み方）

| 表記 | 意味 |
|---|---|
| **実測** | このマシン上で実際に操作・計測した事実 |
| **公式記載** | 公式ドキュメント/サイトの記述。動作は未検証 |
| **評価** | 調査者の判断。事実ではない |

- 有料プラン専用機能（Conductor Cloud、Superset の Automations / Remote Workspaces / Tasks）と、GitHub リモートを要する PR 作成〜マージのフローは **未検証**。
- 価格は 2026-08-02 時点の公開情報／アプリ内 Billing 画面の表示。
- **競合 2 製品の全機能を網羅検証したわけではない**。「競合に無い」と書ける根拠は無いため、本文では「今回調べた範囲では確認できなかった」と表記する。

---

## 0. エグゼクティブサマリ

Conductor と Superset は Phlox と同じ「複数のコーディングエージェントを並列に走らせる」課題を扱うが、**解いている問題が違う**。

| | Phlox | Conductor | Superset |
|---|---|---|---|
| 中心にあるもの | エージェント同士のオーケストレーションと遠隔監視 | タスク → PR のワークフロー | エージェント用ターミナル基盤 |
| 設計思想 | エージェント CLI を**制御する**（PTY＋構造化チャット＋設定 GUI） | エージェント CLI を**隠す**（独自チャット UI に置換） | エージェント CLI を**そのまま出す**（TUI を多重化） |
| ワークスペース隔離 | 人間が用意（`spawn --dir`） | アプリが worktree を自動生成 | アプリが worktree を自動生成 |
| 既定の安全姿勢 | Bypass は明示トグル | 承認 UI が既定 | **既定で承認スキップ** |
| 実装 | ネイティブ（SwiftUI） | Tauri（Rust + WebKit） | Electron |
| ライセンス | MIT（完全 OSS） | プロプライエタリ | ELv2（source-available） |

**この調査から導いた最も重要な論点は §9-4**（Phlox の弱点は「機能が無い」ことではなく「変更のセッション帰属が無い」ことに一本化される）。

---

## 1. 基本情報（実測）

| 項目 | Conductor | Superset |
|---|---|---|
| バージョン | 0.78.1 | 1.18.1 |
| Bundle ID | `com.conductor.app` | `com.superset.desktop` |
| 実装スタック | **Tauri**（Rust バイナリ + WebKit。`tauri-plugin-*` を実バイナリで確認。フロントは "Tauri + React + Typescript"） | **Electron**（`Electron Framework.framework` / Squirrel / Helper プロセス群を確認） |
| アプリサイズ | **194 MB** | **2.1 GB** |
| 実測メモリ（RSS 合計、1 ワークスペース稼働時） | **約 290 MB**（4 プロセス） | **約 891 MB**（11+ プロセス。ターミナル/チャット/ブラウザの 3 タブを開いた状態） |
| ライセンス | プロプライエタリ | **Elastic License 2.0**（source-available。OSI 承認の OSS ではない。ホスティング提供は不可） |
| 対応 OS | macOS のみ | macOS（Windows/Linux は「coming soon」。非公式 Windows port `SuperWin` あり） |
| worktree 置き場 | `~/conductor/workspaces/<repo>/<workspace>` | `~/.superset/worktrees/<repo>/<workspace>` |
| ユーザー設定 | `~/.conductor/settings.toml`（TOML） | アプリ内 DB ＋ クラウド組織 |
| 同梱バイナリ | `gh`(53MB) / `watchexec` / `checkpointer.sh` / `spotlighter.sh` / `git-busy-check.sh` | Electron ランタイム一式 |

### 1-1. Conductor は自アプリの操作方法を Claude Code スキルとして同梱している

`/Applications/Conductor.app/Contents/Resources/conductor-skill/` に Claude Code プラグイン形式のスキルが入っている。

```
conductor-skill/.claude-plugin/plugin.json   → { "name": "conductor" }
conductor-skill/skills/conductor/SKILL.md    → 設定 TOML 階層・スクリプト仕様・環境変数・トラブルシュート
```

設定の優先順位（`managed > repository local > repository shared > user > built-in`）、環境変数一覧、`run_mode` の使い分け、`.worktreeinclude` の解決順まで記載されている。**「エージェントに自分自身を設定させる」ことを前提にした設計**であり、ドキュメントをエージェント可読な形で出荷している。

---

## 2. 設計思想の違い（本質）

### 2-1. Conductor: エージェントを隠す

内部では `claude` / `codex` を子プロセスで動かすが、UI には**独自レンダリングのチャット**を出す。

- ツール呼び出しは `Read 4 lines [math.ts]` のようなチップに圧縮
- 完了後は `4 tool calls, 3 messages` に折りたたむ（段階的開示）
- モデル選択・思考量・Plan モードはすべて Conductor 側の UI。CLI のフラグは見えない

結果として「Claude Code を使っている」という感触が消え、Linear や Graphite に近いタスク管理ツールの手触りになる。

### 2-2. Superset: エージェントをそのまま出す

ワークスペースを作ると、端末ペインに実行コマンドが表示される（実測時のキャプチャ）:

```
claude --dangerously-skip-permissions "$(cat <<'SUPERSET_PROMPT_3b11fce9...'
src/math.ts に multiply 関数（a * b）を追加して、README.md に1行説明を足してください。
SUPERSET_PROMPT_3b11fce9...
)"
```

以降は Claude Code 自身の TUI（Welcome バナー、`ctx 94% | 5h 31% | 7d 57% | $0.75` のステータスライン）がそのまま描画される。Superset は **エージェント用の高機能ターミナル multiplexer ＋ git worktree マネージャ**であり、エージェント体験そのものには介入しない。

---

## 3. UI/UX 詳細

### 3-1. Conductor

**レイアウト**: 3 ペイン固定
- 左: Home / Create / Search ＋ Projects → Workspaces
- 中央: タブ帯（チャット・差分・ファイルが同じ帯に並ぶ）＋ 下部コンポーザー
- 右上: All files / Changes / Checks、右下: Setup / Run / Terminal

**実測で確認した作り込み**

| 項目 | 内容 |
|---|---|
| タスク起点のワークスペース生成 | ⌘N のモーダルは「What do you want to work on?」のみ。プロンプト投入と同時に worktree 作成・ブランチ作成・エージェント起動が走る |
| 仮名 → 自動リネーム | ブランチは都市名（例 `Palembang`）で仮生成され、**初回メッセージから `add-subtract-function` に自動リネーム**（Git 設定でオフ可） |
| ベースブランチの追従 | 新規ワークスペースは `origin` を fetch してから作成。ルートの checkout が遅れていてもリモート最新から切る |
| チャットと差分の同居 | 差分ビューを開いても下部コンポーザーが残り、レビューしながら追加指示が出せる |
| 差分ビューア | `Viewed` チェック、revert、unified/split、空白無視、**Diff / Preview / Edit** 切替（Markdown はレンダリング表示・その場編集も可） |
| Open in メニュー | インストール済みエディタ/端末を自動検出して番号付きで列挙（実測: Finder / Cursor / Xcode / Ghostty / iTerm / WezTerm / Terminal / Antigravity / Copy path） |
| Home | 受信箱型の一覧。日付グループ、`+9` の差分バッジ、経過時間、archived フィルタ |
| コマンドパレット | ⌘K。All / Workspaces / Actions / Settings のタブ分け |

**キーボードショートカット（実測で全件取得。90 以上）**

```
General    ⌘K コマンドパレット / ⌘⌥T テーマ切替 / ⌘⇧L sidecar ログ / ⌃O Garry mode（ツール呼び出し展開）
View       ⌘B 左 / ⌘⌥B 右 / ⌘J ターミナル / ⌘. Zen mode
Navigation ⌘[ ] 履歴 / ⌘⇧[ ] タブ / ⌘⇧T タブ復元 / ⌘P Quick open / ⌃1-9 組織切替
Workspace  ⌘N 新規 / ⌘⇧A アーカイブ / ⌘O 外部で開く / ⌘R run script / ⌘E ファイル編集モード
           ⌘⇧P Create PR / ⌘⇧Y Commit and push / ⌘⇧L Pull latest from main / ⌘⇧M Merge PR
           ⌘⇧X Fix errors / ⌘⇧R Start review / ⌘⇧G GitHub で PR を開く
           ⌥C 変更 / ⌥U 未コミット / ⌥F 全ファイル / ⇧⌥C Checks / ⌥N Notes
Chat       ⌘T 新規タブ / ⌘L 入力欄フォーカス / ⇧Tab Plan mode / ⌘⇧↵ プラン承認
           ↵ ツール承認 / ⌘↵ 代替承認 / ⌫ 拒否 / ⌘⇧⌫ エージェント中断
           ⌘I イシュー紐付け / ⌘U 添付 / ⌥P モデルピッカー / ⌥T 思考レベル循環
           ⌥L 次の要対応チャット / ⌥H 前の要対応チャット
           ⌘⌥C 簡潔なトランスクリプトをコピー / ⌘⌥↵ チャットを新タブに fork / ⌘D 音声入力
Code review ⌘⇧D 差分ビュー / J K ファイル移動 / ⌘⌥J K コメント移動 / ⌃V viewed 切替
Terminal   ⌘T / ⌘W タブ / ⌘⇧B localhost を開く / ⌘F 検索
```

差分レビューで **J/K が GitHub と同じ意味**なのは既存慣習への追従（ジェイコブの法則）。

**設定**（General / Account / Models / Agents / Environment / Git / Appearance / Experimental / Advanced ＋ Repositories）

細部の気配りが目立つ:
- `I'm not absolutely right, thank you very much` — AI の "You're absolutely right!" を除去
- `Caffeinate while agents are running` — エージェント稼働中はスリープ抑止、**バッテリー 10% 未満で自動解除**
- `Always show context usage` — 既定は 70% 超で表示
- `Accessible colors` — 色覚特性に最適化したテーマ
- `Auto-convert long text` — 5000 文字超のペーストを添付ファイル化
- Appearance: Code theme / Mono font / ligature / Markdown style / Terminal font & size
- Git: `Rename workspace when branch is named` / `Delete branch on archive` / `Archive on merge` / `Automerge` / `Treat optional checks as blocking` / `Set upstream on plain git push`
- Advanced: Claude Code / Codex / OpenCode の**実行ファイルパス上書き**、クラウド用 SSH 鍵、`Remote execution MCP`（リモートエージェントがローカル Mac に one-shot コマンドを要求 → 都度承認）、スクロールバック上限

Experimental（実測 17 項目）:
`Auto permission mode` / `Big terminal mode` / `Persist model picker config` / `Skip new workspace modal (Jared Mode)` / `Tab Freak Mode`（タブ 10 枚まで）/ `Split tabs` / `Fork chat to new tab` / `In-app browser preview` / `Show agent cost` / `Add projects without GitHub` / `Auto-run after setup` / `Dashboard` / `Voice mode` / `Show sidebar resource usage` / `Sidebar transparency` / `Graphite stack support`

**実測で見つかった弱点**

1. **GitHub 前提が強い**。リモート未設定のリポジトリを開くと `Create a private GitHub repo?` ダイアログのみが出て、Cancel すると**プロジェクト追加そのものが中止**される。ローカル bare リモートを `origin` に設定したところ通った。Experimental の `Add projects without GitHub` で回避できるが既定動線ではない。
2. 非 GitHub リモートだと右上が **`Loading PR info…` のまま固まる**。エラーにも「該当なし」にもならず、状態が不定のまま残る（システム状態の可視性の欠落）。

### 3-2. Superset

**レイアウト**
- 左: Workspaces / Tasks & PRs / New Workspace ＋ プロジェクト → ワークスペース
- 中央: タブ（ターミナル・チャット・ブラウザを混在可、**1 タブ内で分割ペイン**）
- 右: Changes（Diffs / Review）/ Files

**実測で確認した作り込み**

| 項目 | 内容 |
|---|---|
| プリセットバー | `claude` `amp` `codex` `gemini` `copilot` `vibe` `kimi` `grok` をワンクリックで新規ターミナル起動。**同一ワークスペースに複数エージェントを同居** |
| 分割ペイン | ターミナル（左）と差分（右）を 1 タブに並べられる。ファイルを開くと自動 split（設定で選択可） |
| タブ 3 種 | **Terminal(⌘T) / Chat(⌘⇧T) / Browser(⌘⇧B)** |
| In-app ブラウザ | 「Enter a URL above, or instruct an agent to navigate and use the browser」＝**エージェントに操作させる前提** |
| ネイティブ Chat | 独自の権限モード **Auto / Semi-auto / Manual**。ターミナル経由の CLI 起動とは別系統 |
| 右パネル | コミットメッセージ欄＋`Publish Branch`。変更はディレクトリ別グルーピング |
| ワークスペース右クリック | Rename / Open in Finder / Open in Editor / Copy Path / Copy Branch Name / **Move to Section** / Mark as Unread / Clear Status / Close Worktree |
| 通知音 | 🪕 Shamisen / 🕹️ Arcade / 📍 Ping / ⚡ Quick Ping / 🎷 Doo-Wap / 👩‍💻 Agent is Done / 🌍 Code Complete ＋ 独自音源（.mp3/.wav/.ogg） |
| テーマ | **マーケットプレイス**あり。starter のダウンロード／インポート、Markdown に **Tufte スタイル** |
| プロジェクト | 色 12 色・アイコン画像を設定可。**外部 worktree の import**（ディスク上の既存 worktree を検出して取り込み） |
| キーボード | **全項目リマップ可能**＋`Adaptive layout mapping`（QWERTZ 等で刻印基準／物理キー位置基準を選択） |

**設定ツリー**（Conductor より組織/プラットフォーム寄り）

```
PERSONAL          Account / Appearance / Notifications
EDITOR & WORKFLOW General / Keyboard / Git & Worktrees / Agents / Terminal / Models
ORGANIZATION      Organization / Teams / Projects / Hosts / Integrations / Billing / API Keys
SYSTEM            Security / Permissions / Experimental
```

- `Hosts`: マシンごとに登録。worktree 既定位置、メンバー権限、ホスト削除
- `Integrations`: Linear / GitHub / Slack（いずれも未接続状態で確認）
- `API Keys`: MCP サーバ／外部連携用（`sk_live_` 形式）
- `Security`: 「Allow remote workspaces to access this device via relay」
- `Permissions`: Full Disk Access / Accessibility / Microphone / Automation / Local Network の付与状態一覧

**実測で見つかった弱点**

1. `File > Open Repo…` でリポジトリを追加すると **「Project ready — open it from the sidebar」** とトーストが出るが、サイドバーには何も現れない（サイドバーは workspace のみを表示する設計のため）。New Workspace モーダルを開いて初めて登録済みだと分かる。**フィードバックの文言と到達点がズレている**。
2. View メニューに **Reload / Force Reload / Toggle Developer Tools** が露出（Electron 素のまま）。
3. **ネイティブ Chat のモデル一覧が古い**。実測で `Claude Opus 4.8 / 4.7 / Fable 5 / Sonnet 4.6 / Haiku 4.5` ＋ `GPT-5.5 / 5.4 / 5.3 Codex` のみで、**Opus 5・Sonnet 5 が無い**。ターミナル経由の Claude Code では Opus 5 が使えるため、同一アプリ内に 2 系統の能力差が生じている。

---

## 4. 安全性・権限モデル（最大の差）

### 4-1. Superset の既定ターミナルプリセット（設定画面で実物を確認）

| プリセット | コマンド |
|---|---|
| claude | `claude --dangerously-skip-permissions` |
| codex | `codex --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust` |
| gemini | `gemini --approval-mode=auto_edit` |
| copilot | `copilot --allow-tool=write` |

実走したセッションでも `bypass permissions on (shift+tab to cycle)` と表示された。**主役であるターミナル経路には承認 UI が存在しない**。ネイティブ Chat 側には Auto / Semi-auto / Manual があるが、既定の導線はターミナル側。

### 4-2. Conductor

- `↵` 承認 / `⌫` 拒否 / `⌘↵` 代替承認 が標準ショートカットとして割り当て済み
- 承認スキップは Experimental の `Auto permission mode` として**オプトイン**
- Plan モード（`⇧Tab`）、チェックポイント、`Remote execution MCP`（都度承認、`Always allow local commands` で緩和可）
- **公式記載**: shell コマンド・ファイル変更・MCP ツール呼び出し・Web リクエストが承認対象になりうる。Enterprise data privacy モードで外部 AI 機能を無効化可能（未検証）

**評価**: 監査・統制が要る組織では Superset の既定は採用しづらい。

---

## 5. 機能マトリクス

凡例: ◎ 中核機能 / ○ あり / △ 部分的 / ✗ 今回の調査では確認できず

| 機能 | Phlox | Conductor | Superset |
|---|---|---|---|
| **オーケストレーション** ||||
| エージェントから他エージェントを spawn | **◎** `phlox list/send/spawn/rename/read/wait-ready/wait/kill` | ✗ | △ MCP 経由で外部から Superset を操作（エージェント同士ではない） |
| spawn の暴走ガード | **◎** `SpawnPolicy`：API 経由 spawn の深さ 3・毎秒 5 件・kill 認可（§9-1 に正確な条件） | ✗ | ✗ |
| サブエージェントの可視化 | **◎** 親セッション内のタブに束ねる | △ `Fork chat to new tab`（分岐であって階層ではない） | △ 別ターミナルとして並置 |
| **リモート監視・操作** ||||
| モバイルから承認 | **○ Codex の構造化承認のみ**（Claude/Cursor の PTY 承認は対象外） | ○ iOS アプリ（Cloud ワークスペース対象・Pro） | ✗（Coming Soon） |
| 通信経路 | 制御チャネルは私設 tailnet 直結（push は APNs 経由） | クラウド経由 | クラウド relay 経由 |
| Push / ウィジェット / Live Activity | **◎** ＋ Face ID ゲート | △ デスクトップ通知 | △ デスクトップ通知＋音 |
| **エージェント CLI 管理** ||||
| CLI の設定を GUI で管理 | **◎ Agent Console 18 画面**（Claude 7 / Codex 6 / Cursor 5） | △ 設定ファイルを外部エディタで開くだけ | △ 有効/無効＋起動コマンドのプリセット |
| 対応エージェント | 組込み 3（Claude Code / Codex / Cursor）＋ `agents.json` でカスタム追加可 | 4（＋OpenCode） | **15+** |
| **ワークスペース** ||||
| worktree 自動生成 | ✗（セッション用ディレクトリを作るのみ） | **◎** | **◎** |
| setup / run スクリプト自動実行 | ✗ | **◎** `.conductor/settings.toml`＋ポート 10 個割当＋`.env` 等のコピー | ○ setup/teardown＋ポート管理 |
| **レビュー・git** ||||
| 変更一覧＋diff＋その場編集 | **○ プロジェクト（リポジトリ）単位** | **◎ ワークスペース単位**＋Viewed・revert・split/unified・Preview/Edit | ○ ワークスペース単位・staging |
| 変更のセッション帰属 | **✗**（§9-4 の中心論点） | ◎（worktree＝セッション） | ◎（worktree＝セッション） |
| ブランチ切替 | ○ 一覧＋`git checkout` | ○ | ○ |
| commit / push / PR / merge | ✗ | **◎** ⌘⇧P/⌘⇧Y/⌘⇧M・automerge | ○ Publish Branch → GitHub |
| マージゲート | ✗ | **◎ Checks**（CI・レビュースレッド・未完 TODO を集約） | △ PR があれば表示 |
| **自動化・外部連携** ||||
| 定期実行 | ✗ | ✗ | **◎ Automations**（RFC 5545 RRULE） |
| 自製品を MCP サーバとして公開 | ✗ | ✗ | **◎** 26 前後のツール |
| 公開 API / CLI / SDK | ○ ローカル制御サーバ（`/sessions` `/send` `/approvals` `/question` `/model` `/usage` `/settings` `/device-tokens`）＋ `phlox` CLI | ○ REST 18 endpoints＋SQL 検索（Cloud 前提・beta） | **◎** MCP＋CLI＋SDK |
| Linear / Slack 連携 | ✗ | △ イシュー紐付け | ○（Pro） |
| **実行環境** ||||
| クラウド実行 | ✗（完全ローカル） | **◎ Conductor Cloud**（閉じても継続・組織共有の Cloud Computer） | ○ Remote Workspaces（自分の別マシン） |
| **コスト可視化** ||||
| ターン/セッション単位のコスト | **◎** `Turn cost $15.10` | △ Cloud のみ（Experimental） | △ CLI のステータスライン依存 |
| 使用量メーター（5h/7d 窓） | **◎** Claude・Codex 別に常時表示 | ✗ | ✗ |
| **統制** ||||
| 承認バイパスの既定 | 明示トグル（Bypass） | 承認 UI が既定 | **既定でバイパス** |
| 組織統制（SSO/SCIM/managed settings） | ✗ | **◎**（Teams/Enterprise） | ○ Organization/Teams/Hosts |

---

## 6. 価格（2026-08-02 時点）

| | Conductor | Superset |
|---|---|---|
| Free | $0 — ローカル並列実行、BYO API キー | $0 |
| Pro | **$50/月** — Conductor Cloud のワークスペース時間、マルチプレイヤー、API、モバイル（forthcoming） | **$20/user/月** — クラウドワークスペース、モバイル、優先サポート |
| Team | $60/user/月 — Admin portal、集中請求、SSO | Organization / Teams は無料枠にも存在 |
| Enterprise | 個別 — DPA、PO 請求、SCIM、カスタムセキュリティ、SLA、専任サポート | 記載なし |

- Superset Pro は Conductor Pro の **約 1/2.5**。ただし無料版では `Tasks & PRs` が**完全ペイウォール**（Pro 訴求モーダル: Tasks / Remote Workspaces / Team Collaboration / Slack Integration / Mobile App(Coming Soon)）。
- Conductor は無料版でも**ローカル並列実行の中核機能が制限なし**。課金はクラウド/チームに寄せている。

---

## 7. 同一タスクの実走比較（実測）

依頼内容: 「`src/math.ts` に関数を 1 つ追加して、`README.md` に 1 行説明を足す。テストは不要」

| | Conductor | Superset |
|---|---|---|
| 使用モデル | **Haiku 4.5**（アプリの UI で明示選択） | **Opus 5 (1M) xhigh**（Claude Code の既定をそのまま継承） |
| 所要 | 14s | 20s |
| 経過表示 | `8.1s` → `14s` のインライン計測 | Claude Code の `Crunched for 20s` |
| 結果表示 | ツール呼び出しを折りたたみ＋変更ファイルチップ（`README.md +5 -0` / `math.ts +4 -0`） | Claude Code の TUI 出力そのまま＋右パネルの差分が自動更新 |
| 右パネル | `Changes 2` に自動切替、`Review` ボタン出現 | `Unstaged 2` にディレクトリ別グルーピング |
| コスト表示 | なし（`Show agent cost` はクラウド用の Experimental） | Claude Code のステータスラインに **$0.75** |

**評価**: Conductor はモデルとコストをアプリが制御し、Superset はユーザーの CLI 設定に完全依存する。前者は「安く速く回す」判断をアプリ側に持たせられ、後者は「ユーザーの既定が高価なモデルなら、些細なタスクでも高価に走る」。

---

## 8. 判明した弱点（両者）

| # | 製品 | 内容 | 種別 |
|---|---|---|---|
| 1 | Conductor | リモート未設定リポジトリは既定で追加できない | オンボーディング障壁 |
| 2 | Conductor | 非 GitHub リモートで `Loading PR info…` が永続 | システム状態の可視性 |
| 3 | Superset | 「Project ready — open it from the sidebar」直後にサイドバーが空 | フィードバックと到達点の不一致 |
| 4 | Superset | View メニューに Electron の Developer Tools が露出 | 完成度 |
| 5 | Superset | ネイティブ Chat のモデル一覧が CLI 経路より 1 世代古い | 機能の内部不整合 |
| 6 | Superset | 既定で全エージェントが承認スキップ起動 | 安全性 |
| 7 | Superset | アプリ 2.1GB / 実測メモリ 891MB | リソース効率 |

---

## 9. Phlox との機能差（実コードで検証済み）

> 本節の Phlox 側の記述は **実コードで確認した事実**のみを書く。§11 の独立レビューで指摘された誤りを反映済み。

### 9-1. Phlox の現状（根拠付き）

| 項目 | 実装状況 | 根拠 |
|---|---|---|
| エージェント間 spawn | `phlox` CLI に `list / send / spawn / rename / read / wait-ready / wait / kill` | `macos/scripts/phlox` |
| spawn ガード | **API 経由 spawn** の深さ上限 3、毎秒 5 件のレート制限 | `SpawnPolicy.swift`（`maxAPISpawnDepth` / `maxAPISpawnCountPerSecond`） |
| kill 認可 | **「祖先のみ」ではない**。requester なし・自己 kill・対象不明は**許可**。それ以外は requester が対象の祖先のときだけ許可。`privilegedRequesters` は無条件許可 | `SpawnPolicy.swift`（kill 認可のドキュメントコメント） |
| サブエージェント UI | 親セッション内のタブで切替 | `ChatSessionAccessories.swift` |
| 制御サーバ | `/sessions` `/send` `/approvals` `/approvals/{id}` `/question` `/model` `/usage` `/settings` `/device-tokens` | `macos/Packages/ControlServer/` |
| モバイル承認 | **Codex の構造化承認のみ**。Claude/Cursor の PTY 承認は対象外（コード注記に「PoC で不可確定」） | `DashboardViewModel+ControlApprovals.swift` |
| Agent Console | **18 画面**（Claude 7: status/plugins/permissions/memory/hooks/statusLine/outputStyle、Codex 6: status/settings/plugins/MCP/memory/trust、Cursor 5) | `AgentConsoleSection.swift` |
| 対応エージェント | 組込み 3 種＋**`~/.config/phlox/agents.json`（`PHLOX_AGENTS_JSON` で上書き可）でカスタム追加**。ただし構造化チャット・使用量計測・専用設定画面は組込み 3 種に偏る | `CustomAgentDefinition.swift`（`CustomAgentRegistryLoader`） |
| 変更レビュー | **プロジェクト（リポジトリ）単位**の Changes リスト＋diff＋その場編集ドロワー | `WorkingTreeService.swift`（`changes()` / `detail(for:)` / `fileContents` / `save`）、`EditorPanelView.swift` |
| ブランチ操作 | ローカルブランチ一覧＋`git checkout` | `GitBranchSwitcher.swift` |
| commit / push / PR / merge | **確認できず** | — |
| worktree 生成 | **確認できず**（セッション用ディレクトリを作るのみ） | `AgentLaunchPlanner.swift` / `SessionSpawnService.swift` |
| 定期実行 | **確認できず**（コンポーザーの `/schedule` 候補はエージェントへ送るコマンドであり、Phlox の機能ではない） | `ComposerSuggestions.swift` |
| インスペクタ | 使用量表示（`UsageSidebarView`）。差分パネルではない | `DashboardView.swift` |

### 9-2. Phlox の強み

1. **エージェント間オーケストレーション** — `spawn → wait-ready → send → wait` の連鎖をエージェント自身が組める。**今回調べた範囲では、Conductor / Superset にこの層は確認できなかった**（Superset の MCP は外部→Superset 方向であり、エージェントの階層を作るものではない）。
2. **サブエージェントを親セッションのタブに束ねる UI** — 多階層の作業を 1 つの仕事として提示する。同上、両競合では確認できなかった。
3. **CLI 設定の GUI 管理（Agent Console 18 画面）** — Conductor は設定ファイルを開くボタンのみ、Superset は起動コマンドのプリセットのみ。**エージェントの設定そのものを製品の管理対象にしている**点が異なる。
4. **コスト・使用量の可視化** — ターンコスト＋5h/7d の窓別メーター（Claude・Codex 別）。Conductor はクラウド専用の Experimental、Superset は CLI のステータスラインを表示しているだけ。
5. **モバイルからの承認**（Codex の構造化承認に限る）＋ Push / ウィジェット / Live Activity / Face ID。Conductor のモバイルはクラウドワークスペース前提、Superset は未出荷。
6. **MIT ライセンスの完全 OSS**。

### 9-3. Phlox の弱み

1. **worktree 隔離が製品に入っていない** — 競合はどちらも worktree 生成・`.env` 等のコピー・依存インストール・ポート割当を製品機能として持つ。Phlox はセッション用ディレクトリを作るのみ。
2. **変更のセッション帰属がない** — 変更一覧・diff・編集は**ある**が、対象は選択セッションの属する**プロジェクトのリポジトリ**。複数セッションが同一 checkout を共有するため、「どのセッションが何を変えたか」が出せない。
3. **commit / push / PR / merge が確認できない** — 「エージェントに書かせた後どうするか」が製品の外側にある。
4. **構造化サポートが組込み 3 種に偏る** — カスタムエージェントは追加できるが、構造化チャット・使用量計測・専用設定画面の恩恵は受けにくい。
5. **チーム・組織機能がない**（SSO・組織設定の強制・共有ワークスペース）。
6. **定期実行・外部連携がない**（Superset の Automations、Linear/Slack 相当）。

### 9-4. 中心論点: 弱点は「機能の不足」ではなく「セッション帰属の欠如」

Phlox には変更一覧も diff もブランチ切替も**既にある**。欠けているのは**それらがセッション単位でないこと**である。したがって施策の順序は次になる。

1. **worktree 隔離**（セッション帰属が成立する前提条件）
2. **既存の EditorPanel をセッション単位へ切り替える**（新規開発ではなく、対象リポジトリの解決を変える作業）
3. その上で commit / push / PR

**共有 checkout の競合を解決しないまま git 操作を増やしても安全性は上がらない**（§11 の独立レビューの指摘に同意）。

### 9-5. UI/UX で参考にできる点（優先度順・評価）

| 優先 | 項目 | 競合の実装 | Phlox の現状 | 留意点 |
|---|---|---|---|---|
| 高 | セッション名の自動リネーム | Conductor は都市名で仮生成 → 初回メッセージから自動リネーム、ブランチも連動 | 花の名前で固定。**手動リネームは実装済み**（`DashboardViewModel.swift`） | 「足すだけ」ではない。誤命名・命名の再現性・ユーザー編集名の保護・ブランチ連動の責任範囲を決める必要がある |
| 高 | 「要対応」への集約とジャンプ | Conductor `⌥L`/`⌥H`、Home の日付グループ＋差分バッジ＋検索。Superset は All/Active/Closed＋Section | `2/14` 表示と状態ドットのみ | **先に状態検出の誤判定率を測る**。誤った要対応通知はジャンプ UI を足すほど負債になる |
| 高 | 変更レビューのセッション帰属 | 両競合とも worktree＝セッションなので自明 | プロジェクト単位 | UI 配置（インスペクタに足す等）より先に**変更帰属モデル**を決める |
| 中 | セッション単位のコンテキスト残量 | Conductor `Always show context usage`（既定 70% 超） | 5h/7d メーターのみ | — |
| 中 | コマンドパレット ⌘K | Conductor（All/Workspaces/Actions/Settings） | なし | 自動リネームとセットで価値が出る |
| 中 | 「Open in」の外部ツール自動検出 | Conductor が番号キー付きで列挙 | 弱い | 既存の CLI 検出（`command -v`）を流用できる |
| 中 | エージェント稼働中のスリープ抑止 | Conductor `Caffeinate while agents are running`（バッテリー 10% で自動解除） | なし | 解除条件付きの設計ごと参考になる |
| 小 | 完了通知の作り込み | Superset の音源選択＋独自音源 | — | 並列運用では「どれが終わったか」の区別に効く |
| 小 | 色に依存しない状態表現 | Conductor `Accessible colors` | エージェント色分けが主要チャネル | アイコン＋テキストの併用 |

**真似しない**: Superset の既定バイパス、Electron 重量、Conductor の GitHub 必須オンボーディング、Superset の「Project ready」トースト。

---

## 10. この比較で扱っていない軸

本レポートは**機能の有無**に偏っており、実務で重要な次の軸を扱っていない。判断材料として使う場合はこの欠落を前提にすること。

- タスク完了率（同一タスクを N 回走らせたときの成功率）
- 失敗・中断からの復旧（クラッシュ後の再開、途中終了したセッションの扱い）
- 承認の安全性（承認 UI が実際に危険な操作を止められるか）
- データ保持とプライバシー（トランスクリプトの保存先・保持期間・削除手段）
- 導入時間（インストールから最初の 1 タスク完了まで）
- アクセシビリティ（VoiceOver・Dynamic Type・キーボードのみでの操作）
- 大規模リポジトリでの性能（数万ファイル規模での差分計算・ファイルツリー）

また、**価格・対応エージェント数・API 数を同じ重みで並べる比較は妥当ではない**。§5 のマトリクスは「何があるか」の一覧であり、重み付けされた評価ではない。

---

## 11. 検証範囲・独立レビュー・未検証事項

### 11-1. 実際に操作・確認したこと

- 両アプリへのプロジェクト追加、ワークスペース生成、エージェント 1 回ずつの実走、差分表示
- 設定画面の全セクション、キーボードショートカット一覧、コマンドパレット、各種ピッカーの選択肢
- アプリバンドルの構成（実装スタック、同梱バイナリ、同梱スキル）、プロセスの実測メモリ
- worktree のディスク上の実配置
- Phlox 側: 稼働中アプリの画面＋§9-1 に挙げた各ソースファイル

### 11-2. 独立レビュー（2026-08-02）

Codex（GPT-5.5）を read-only サンドボックスで実行し、本レポートの主張を敵対的にレビューさせた。全文は `docs/agent-output/codex-competitor-analysis-review.md`（生成物であり永続対象外）。

**レビューで修正された誤り**（いずれも指摘後に実コードで再確認し、§9 に反映済み）:

| 修正前の記述 | 修正後 |
|---|---|
| Agent Console 26 画面 | 18 画面 |
| git 操作がゼロ | ブランチ一覧と `git checkout` はある。無いのは commit/push/PR/merge |
| 変更一覧はメッセージ単位のみ | プロジェクト単位の Changes＋diff＋編集ドロワーがある |
| エージェント追加は enum 改修必須 | `agents.json` でカスタム追加可 |
| kill は祖先のみ許可 | requester なし・自己 kill・対象不明も許可、特権 requester は無条件 |
| モバイルから承認できる | Codex の構造化承認のみ |
| 第三者サーバを経由しない | 制御チャネルは tailnet 直結だが push は APNs 経由 |
| 「唯一無二」「競合に無い」 | 「今回調べた範囲では確認できなかった」 |

**レビューの限界**:
- レビュアーは Conductor / Superset を操作できないため、**競合側の事実（§1〜§8）は独立検証されていない**。
- レビュー実行時、本レポートのファイルがディスク上に存在せずレビュアーは全文を読めていない。評価対象は要約のみだった。

### 11-3. 未検証（公式記載の要約に留まる）

- Conductor Cloud（クラウドワークスペース、Cloud Computer、コラボレーション、iOS アプリ、公開 API）
- Superset の Automations / Remote Workspaces / Tasks / MCP サーバ / CLI / SDK
- 両者の PR 作成 → CI → マージのフロー（GitHub リモートを用意していないため）
- Conductor の Enterprise data privacy モード、managed settings による組織強制

### 11-4. 調査時に作成したローカル資産（リポジトリ外）

不要なら削除してよい。

- `~/Projects/ca-sandbox`（検証用リポジトリ）、`~/Projects/ca-sandbox-remote.git`（ローカル bare リモート）
- `~/conductor/workspaces/ca-sandbox/add-subtract-function`（Conductor の worktree）
- `~/.superset/worktrees/ca-sandbox/multiplyreadme`（Superset の worktree）
- `~/Projects/competitor-analysis-2026-08-02/`（**スクリーンショット 29 枚**。個人アカウント名・メールアドレスが写り込んでいるため**リポジトリには含めない**）

---

## 12. 関連ドキュメントの陳腐化

`ai-agent-cli-support-survey.md`（`last-verified: 2026-07-04`）の次の記述は、**現在は事実と異なる**。

> §1-2: **設定ファイル/プラグインによる外部追加機構は存在しない**（enum 改修=コード変更が必須）

`CustomAgentDefinition.swift`（`CustomAgentRegistryLoader`）は 2026-07-16 のコミット `80c6f5f` で入っており、`~/.config/phlox/agents.json` からカスタムエージェントを読み込める。同レポート §6 が「長期目標」として挙げている JSON 追加機構が実装済みの状態になっている。同レポートの更新が必要。

---

## 出典

- Conductor 公式 — https://www.conductor.build/
- Conductor 価格 — https://www.conductor.build/pricing
- Conductor ドキュメント — https://www.conductor.build/docs/
- Conductor API — https://www.conductor.build/docs/api
- Conductor Cloud — https://www.conductor.build/docs/cloud
- Conductor セキュリティと権限 — https://www.conductor.build/docs/reference/security-and-permissions
- Conductor Checks — https://www.conductor.build/docs/reference/checks
- Conductor 同梱スキル — `/Applications/Conductor.app/Contents/Resources/conductor-skill/skills/conductor/SKILL.md`
- Superset 公式 — https://superset.sh/
- Superset ドキュメント — https://docs.superset.sh/
- Superset Automations — https://docs.superset.sh/automations
- Superset MCP サーバ — https://docs.superset.sh/mcp-server
- Superset Remote Workspaces — https://docs.superset.sh/remote-workspaces
- Superset CLI リファレンス — https://docs.superset.sh/cli/cli-reference
- superset-sh/superset（GitHub） — https://github.com/superset-sh/superset
- Superset ライセンス（ELv2） — https://github.com/superset-sh/superset/blob/main/LICENSE.md
