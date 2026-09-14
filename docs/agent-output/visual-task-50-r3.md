---
status: partial
task: task-50
---

# UX-10b（task-50）実画面観測記録 r3

## 実行コミット SHA

- HEAD: `21e2ef77da225783a72d6bf4f7b5cc2b41a43e33`（`task/50`、`/tmp/ui-ux-wt-50`）。r2 記録と同一 HEAD。
- Debug 実行 PID: ja `77002`、en `81987`。終了時にいずれも TERM で停止し、Debug binary は残存なし。
- suite: ja `com.phlox.t50.ja.76872`、en `com.phlox.t50.en.76872`。各終了時に削除。
- ビルドは再実行していない。`/tmp/phlox-t13-visual.SPfR9c/build-t50.log` 末尾は `** BUILD SUCCEEDED **`。

## 隔離・Release 確認

- Debug のみ `PHLOX_DEFAULTS_SUITE`、`PHLOX_DATA_DIR`、`PHLOX_AGENTS_JSON`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を指定した。
- Release Phlox PID `61465` は非接触。`com.phlox.Phlox` export md5 は開始前・ja 終了後・en 終了後・最終のすべて `05b0112f1bbdde4793644f69a1ce8b00`（不変）。
- Toggle、権限 Picker、ルール保存、Apple メニュー、key code、keystroke は操作していない。設定は help `設定` / `Settings`、管理画面は自 PID の AX 操作だけで開いた。

## 起動時の子プロセス観測

- ja: `77008` の `claude --bare -p /model --output-format json`（観測時 elapsed `00:01`）。続いて `77111`〜`77115` の Claude モデル照会（`00:00`〜`00:01`）、`77269` の `cursor-agent ... models`（`00:01`〜`00:02`）を観測した。
- en: `81993` の同 Claude 照会（`00:00`）、`82050`〜`82054` の Claude モデル照会（`00:01`）、`82138` の `codex app-server`（`00:00`）、`82159` の `cursor-agent ... models`（`00:00`〜`00:01`）を観測した。いずれも次のサンプルまでに終了した。
- Claude の観測は PM 裁定どおりモデルカタログ照会として停止しなかった。en の `codex app-server` は観測できたコマンド名だけではカタログ照会か実セッションかを独立に判定できず、課金セッションの有無は未検証。

## ウィンドウ一覧

| 言語 | PID | 時点 | title | 論理寸法 | Quartz window id |
|---|---:|---|---|---:|---:|
| ja | 77002 | 起動 | Phlox (Debug) | 900×632 | 51749 |
| ja | 77002 | 設定 | エージェント | 520×728 | 51756 |
| ja | 77002 | 管理 | エージェント管理 | 900×632 | 51765 |
| en | 81987 | 起動 | Phlox (Debug) | 900×632 | 51817 |
| en | 81987 | 設定 | エージェント | 520×728 | 51840 |
| en | 81987 | 管理 | エージェント管理 | 900×632 | 51849 |

## AX 原文

AX static text 全文は UTF-8 の [`ja-ax.log`](/tmp/phlox-t50-visual/r3/ja-ax.log) と [`en-ax.log`](/tmp/phlox-t50-visual/r3/en-ax.log) に、各画面の `=== AX statics ... ===` 節としてそのまま記録した。Codex 設定は先頭と axscroll 後を連続記録し、両言語で `実行制限（サンドボックス）` / `Execution limits (sandbox)` と `sandbox_mode` を確認した。

設定・エージェント・権限の原文（先頭・末尾とも同一の static text）は次のとおり。

```text
ja
Phlox (Debug)
設定
権限
変更は次回セッション開始から反映されます。承認方式と実行制限はエージェントごとに異なります。解除は信頼できるプロジェクトでのみ有効にしてください。
エージェント
Claude Code・Codex・Cursor の設定をここから操作できます。対話 TUI のスラッシュコマンド（/plugin・/permissions 等）や、設定ファイルの手編集でしか触れない項目が対象です。

en
Phlox (Debug)
Settings
Permissions
Changes take effect from the next session start. Approval method and execution limits differ by agent. Enable lift only on projects you trust.
エージェント
Claude Code・Codex・Cursor の設定をここから操作できます。対話 TUI のスラッシュコマンド（/plugin・/permissions 等）や、設定ファイルの手編集でしか触れない項目が対象です。
```

権限トグルの AX description 原文（ja / en）は次のとおり。

```text
ja Claude Code: 承認確認を省略、OFF:、次回開始時に自動判定（auto）を指定します。、ON:、次回開始時に承認確認の省略（bypassPermissions）を指定します。サンドボックスの解除を意味しません。
ja Codex: 承認と実行制限を解除、OFF:、チャットでは on-request と workspace-write を指定します。ターミナルでは解除引数を付けず、Codex の設定に従います。、ON:、チャットでは never と danger-full-access を指定します。ターミナルでは承認とサンドボックスの解除引数を付けます。
ja Cursor: 承認と実行制限を解除、OFF:、次回開始時に --auto-review と --sandbox enabled を指定します。、ON:、次回開始時に --force と --sandbox disabled を指定します。
en Claude Code: Skip approval prompts, OFF:, Specifies auto (automatic judgment) at the next launch., ON:, Specifies bypassPermissions (skip approval prompts) at the next launch. This does not disable the sandbox.
en Codex: Lift approval and execution limits, OFF:, Specifies on-request and workspace-write in chat. Terminal launches omit the lift arguments and follow Codex settings., ON:, Specifies never and danger-full-access in chat. Terminal launches add arguments that lift approval and the sandbox.
en Cursor: Lift approval and execution limits, OFF:, Specifies --auto-review and --sandbox enabled at the next launch., ON:, Specifies --force and --sandbox disabled at the next launch.
```

管理・Claude 権限、Codex 設定、Cursor 権限、Cursor 設定の static text 全文も上記 AX ログに画面ごとに記録した。英語表示には、設定・管理画面のナビゲーションに日本語が残る混在を観測した（例: `エージェント`, `管理コンソール`, `1 件`）。

## PNG 一覧

| 言語 | 対象 | PNG | 画素 |
|---|---|---|---:|
| ja | 設定・エージェント・権限先頭 | [`settings-permissions-ja-top.png`](/tmp/phlox-t50-visual/r3/settings-permissions-ja-top.png) | 1040×1456 |
| ja | 設定・エージェント・権限末尾 | [`settings-permissions-ja-bottom.png`](/tmp/phlox-t50-visual/r3/settings-permissions-ja-bottom.png) | 1040×1456 |
| ja | 管理・Claude 権限 | [`console-claude-permissions-ja.png`](/tmp/phlox-t50-visual/r3/console-claude-permissions-ja.png) | 1800×1264 |
| ja | 管理・Codex 設定（実行制限まで axscroll） | [`console-codex-settings-ja.png`](/tmp/phlox-t50-visual/r3/console-codex-settings-ja.png) | 1800×1264 |
| ja | 管理・Cursor 権限 | [`console-cursor-permissions-ja.png`](/tmp/phlox-t50-visual/r3/console-cursor-permissions-ja.png) | 1800×1264 |
| ja | 管理・Cursor 設定 | [`console-cursor-settings-ja.png`](/tmp/phlox-t50-visual/r3/console-cursor-settings-ja.png) | 726×510 |
| en | 設定・エージェント・権限先頭 | [`settings-permissions-en-top.png`](/tmp/phlox-t50-visual/r3/settings-permissions-en-top.png) | 1040×1456 |
| en | 設定・エージェント・権限末尾 | [`settings-permissions-en-bottom.png`](/tmp/phlox-t50-visual/r3/settings-permissions-en-bottom.png) | 1040×1456 |
| en | 管理・Claude 権限 | [`console-claude-permissions-en.png`](/tmp/phlox-t50-visual/r3/console-claude-permissions-en.png) | 1800×1264 |
| en | 管理・Codex 設定（実行制限まで axscroll） | [`console-codex-settings-en.png`](/tmp/phlox-t50-visual/r3/console-codex-settings-en.png) | 1800×1264 |
| en | 管理・Cursor 権限 | [`console-cursor-permissions-en.png`](/tmp/phlox-t50-visual/r3/console-cursor-permissions-en.png) | 1800×1264 |
| en | 管理・Cursor 設定 | [`console-cursor-settings-en.png`](/tmp/phlox-t50-visual/r3/console-cursor-settings-en.png) | 1800×1264 |

設定末尾と Codex 設定の axscroll は ja/en とも exit 0 で完了し、他アプリによる被覆は今回観測されなかった。ja の Cursor 設定だけは撮影直前の Quartz bounds が 363×255 となり、PNG は 726×510 である。画面内容は記録済みだが、他の管理画面と異なる寸法として明記する。

## 設定の前後比較

- suite export: ja は全観測点 `8faae59c475d13ddef2b3eaa9f64016f`、en は全観測点 `bed49005811290a10216206f8f77b0c0`。各キーは `phlox.grid.paneLayout` と `phlox.panelDrawer.width.migratedTo560` のみ。launch→console の追加・削除・変更はなし、`phlox.bypass.*` は 0 件。
- 隔離 DATA: ja は起動前 `file_count=6 combined=2d594e5a31631c392924e5439161e54b`、起動後から console 後まで `file_count=10 combined=13356725d12e8c826e3175053b72ebad`。en は起動前同値、起動後から console 後まで `file_count=10 combined=a8f42feb0a01f348a5be0edb98ed8ac5`。各言語で launch→console は不変。
- 利用者ファイル md5（ja/en、起動前→設定閲覧後→console 後で一致）: `~/.claude/settings.json` `ee6aee919f5659a790f9df6c84d3ecc6`、`~/.codex/config.toml` `5dc46a2a6e47f8d0e32189e65aa4008a`、`~/.cursor/cli-config.json` `233e30320e04bd400f4f8cc2209b26dd`。並行ジョブとの因果は判定していない。

## できなかった手順と理由

1. 全指定画面は撮影したが、ja の管理・Cursor 設定だけは撮影直前に Quartz window の論理寸法が 363×255 へ変化したため、他の管理画面と同じ解像度の再撮影はしていない。指定された PNG は存在し、内容と AX 原文は取得済み。
2. en 起動時の `codex app-server` が実セッションではないことは、この観測だけでは確認できなかった。課金セッション作成・チャット送信・Toggle/Picker/保存操作は行っていない。

## PM 判定 r3（2026-09-14、PNG 12 枚のうち 5 枚を PM が閲覧）

判定: **pass**（契約「### 5. PM 目視ゲート：設定画面」）。

レビュー r1 の 3 指摘が実画面で解消していることを確認:
1. 設定・権限 Section の各行に `OFF:` / `ON:` の状態名が付き、どちらの状態の説明かを読み分けられる（日本語・英語とも）。
2. 管理・Codex 設定で、権限以外の行（応答の人格 `pragmatic`、サービスティア `default`）は原文表示に戻り、承認方針・実行制限だけが「値は未設定です。適用される既定値はエージェントの設定を確認してください。」を出す。
3. 管理の権限ペインで、導入説明がスクロール本文に全文表示される（Claude は `~/.claude/settings.json の permissions を編集します。ルール編集は設定画面の起動時トグルとは別の設定です。` まで欠けずに読める）。見出し直下の subtitle は短文。

そのほかの合格点:
- Claude／Codex／Cursor の 3 組み込みで説明が異なる（Claude は「サンドボックスの解除を意味しません」、Codex はチャットとターミナルの区別、Cursor は `--auto-review` / `--force` と `--sandbox`）。
- カスタム descriptor（観測用カスタム）の行は「このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。」で、汎用の「フルアクセス」説明にならない。
- 英語表示で管理・Cursor 権限が `Permissions` / `Allow` / `Deny` と説明文まで英語に追随する。
- 設定の前後比較: 隔離 suite・隔離 DATA とも閲覧だけでは変化なし。Toggle・Picker・ルール保存は未操作。

未検証として残す 2 点（いずれも合否に影響しない）:
- 日本語の管理・Cursor 設定だけ、撮影直前にウィンドウの論理寸法が 363×255 に変化したため他画面と解像度が揃っていない。内容と AX 原文は取得済み。
- 英語起動時に走る `codex app-server` が実セッションでないことは本観測では確認できなかった。Phlox 起動時のカタログ照会経路であり、チャット送信・課金セッション作成は行っていない（task-48 の観測でも同様の短命プロセスを記録済み）。

PM 目視ゲートは PM が PNG を確認して判定する。

=== REPORT COMPLETE ===
