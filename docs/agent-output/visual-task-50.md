---
status: partial
task: task-50
---

# UX-10b（task-50）実画面観測記録

製品コード・テスト・契約・台帳は未変更。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke 未使用。権限 Toggle・設定 Picker・ルール保存は未操作（閲覧、DisclosureGroup 開閉なし、設定タブ選択、エージェント管理のエージェント切替と行選択、axscroll のみ）。課金セッション未作成。実エージェント未起動。Release Phlox（PID 61465、`/Applications/Phlox.app`）未接触。合否は PM が PNG を確認して判定する。

## 実行コミット SHA

- HEAD: `d16c1ad1d09c13a974e23283cdfb07bbbb3118ff`（`d16c1ad`、ブランチ `task/50`、worktree `/tmp/ui-ux-wt-50`）
- 対象バイナリ: `/tmp/phlox-t13-visual.SPfR9c/Build-t50/Build/Products/Debug/Phlox.app`（表示名 `Phlox (Debug)`）
- 実行ファイル: `/private/tmp/phlox-t13-visual.SPfR9c/Build-t50/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox`

## ビルド結果

```sh
cd /tmp/ui-ux-wt-50/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build-t50 -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t50.log 2>&1
```

`macos/App/Info.plist` は作業ツリーに配置済み。ログ末尾 `** BUILD SUCCEEDED **`。

## 隔離・起動

ハーネス `/tmp/phlox-t13-visual.SPfR9c/shoot-t50.sh`。データは `data-t33-v4` をコピー。`PHLOX_AGENTS_JSON=$B/agents-t50.json`（`agents-t30.json` に、command=`/nonexistent/phlox-t50-obs-agent`、displayName=`観測用カスタム`、id=`t50-obs-custom` を1件追加）。`PHLOX_DEFAULTS_SUITE` / `PHLOX_DATA_DIR` / `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`。テーマ `-phlox.theme phlox-light`。

| 時点 | `com.phlox.Phlox` md5（file export） | Release PID |
|---|---|---|
| 撮影前 | `82041dc8cf5f0bc76e9a78bb33bfff49` | 61465 残存 |
| ja 終了 / en 終了 / 最終 | 同左（不変） | 61465 残存 |
| 英語設定リトライ前後 | 同左 | 61465 残存 |

Release 実行ファイル md5 `9b1a1047c05e654f220a9f3a6e585e9a` は起動前後で不変。

## 言語ごとの PID・実行ファイル・suite・DATA

実行ファイルは全ランとも上記 Debug バイナリ。

| 言語 | Debug PID | suite | DATA | 備考 |
|---|---|---|---|---|
| ja | 29423 | `com.phlox.t50.ja.29292` | `$B/data-t50-ja` | 設定＋管理 完走。`kill -TERM` 後消滅 |
| en（本ラン） | 34214 | `com.phlox.t50.en.29292` | `$B/data-t50-en` | 管理4画面完走。設定は help「設定」が英語 UI では `Settings` のため未達 |
| en（設定リトライ） | 55787 | `com.phlox.t50.enretry.55546` | `$B/data-t50-en-retry` | help「Settings」で設定を開き SHOT |

起動引数:

- ja: `-AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme phlox-light`
- en: `-AppleLanguages (en) -AppleLocale en -phlox.appLanguage en`（他は同じ）

終了後 Debug `pgrep` 不在。suite は `defaults delete`。Release 61465 残存。

## ウィンドウ一覧（title, size）

ja 設定オープン後 AX:

```
idx=1 name=一般 pos=642, 172 size=520, 728
idx=2 name=Phlox (Debug) pos=306, 192 size=900, 632
```

エージェントタブ選択後: `name=エージェント` 外枠 **520×728**（コンテンツ指定 520×640＋クロム）。`set size … {520, 640}` は外枠 520×728 のまま。Quartz id=49693。

ja エージェント管理: `name=エージェント管理` bounds `306,191,900,632` id=49702。

en 設定リトライ: メイン `Phlox (Debug)` 900×632。設定 `一般`→`エージェント` 520×728 id=49784。en 管理: 900×632 id=49739。タブ名は英語 UI でも「一般／外観／エージェント／接続／詳細」。

## AX 原文（画面ごと）

AX 全文ログ: `/tmp/phlox-t50-visual/ja-ax.log`、`en-ax.log`、`en-settings-retry-top.ax.txt`、`en-settings-retry-bottom.ax.txt`。static の `ellipsis=` はすべて `no`。AX value に「…」なし。長文の画面上の欠けは PNG を PM が判定する。

### ja 設定・権限 Section（PID 29423、520×728）

組み込み3行の AXCheckBox `desc` は OFF 説明と ON 説明を同時に持つ（Toggle 未操作。AX value は組み込み `0`、カスタム `1`）。

```
Heading desc='権限'
Claude Code: 承認確認を省略
  OFF: 次回開始時に自動判定（auto）を指定します。
  ON: 次回開始時に承認確認の省略（bypassPermissions）を指定します。サンドボックスの解除を意味しません。
  AXCheckBox value='0' size=460,59
Codex: 承認と実行制限を解除
  OFF: チャットでは on-request と workspace-write を指定します。ターミナルでは解除引数を付けず、Codex の設定に従います。
  ON: チャットでは never と danger-full-access を指定します。ターミナルでは承認とサンドボックスの解除引数を付けます。
  AXCheckBox value='0' size=460,72
Cursor: 承認と実行制限を解除
  OFF: 次回開始時に --auto-review と --sandbox enabled を指定します。
  ON: 次回開始時に --force と --sandbox disabled を指定します。
  AXCheckBox value='0' size=460,46
観測用カスタム: 起動時の権限設定
  OFF/ON とも: このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。
  AXCheckBox value='1' size=460,46
footer: 変更は次回セッション開始から反映されます。承認方式と実行制限はエージェントごとに異なります。解除は信頼できるプロジェクトでのみ有効にしてください。
```

「フルアクセス」汎用説明は AX に無い。`観測用カスタム` はカスタム用の起動説明。`agents-t30` 由来の UI確認／終了確認／正常終了／出力ありも同じカスタム説明。

末尾 axscroll 後、SCROLLBAR value=1.0。bottom ショットでカスタム行・footer が可視域へ入る。

### en 設定・権限 Section（PID 55787、520×728、リトライ）

```
Heading desc='Permissions'
header static='Settings'
Claude Code: Skip approval prompts
  OFF: Specifies auto (automatic judgment) at the next launch.
  ON: Specifies bypassPermissions (skip approval prompts) at the next launch. This does not disable the sandbox.
Codex: Lift approval and execution limits
  OFF: Specifies on-request and workspace-write in chat. Terminal launches omit the lift arguments and follow Codex settings.
  ON: Specifies never and danger-full-access in chat. Terminal launches add arguments that lift approval and the sandbox.
Cursor: Lift approval and execution limits
  OFF: Specifies --auto-review and --sandbox enabled at the next launch.
  ON: Specifies --force and --sandbox disabled at the next launch.
観測用カスタム: Launch permission settings
  OFF/ON: Follows this agent's launch settings. Check the agent settings for the allowed scope.
footer: Changes take effect from the next session start. Approval method and execution limits differ by agent. Enable lift only on projects you trust.
```

「Full Access」汎用説明は AX に無い。

### ja エージェント管理（PID 29423、900×632）

location ident=`agent-console-location`。

Claude 権限:

```
Claude Code / 権限
権限
対話 TUI の /permissions に相当します。~/.claude/settings.json の permissions を編集します。ルール編集は設定画面の起動時トグルとは別の設定です。 size=589.5,26
許可: 確認なしで実行を許可するルールです。拒否ルールなど、他の権限設定も適用されます。
確認する: 実行前に確認を求めるルールです。確認できないモードでは実行が拒否される場合があります。
拒否: （バケット見出し AX に存在。ルール本文は既存 CLI ルール）
```

Codex 設定:

```
Codex / 設定
承認方針 / approval_policy
値は未設定です。適用される既定値はエージェントの設定を確認してください。
実行制限（サンドボックス） / sandbox_mode
値は未設定です。適用される既定値はエージェントの設定を確認してください。
```

Cursor 権限:

```
Cursor / 権限
対話 TUI 相当の intro は ja-ax.log。許可／拒否の説明が Claude の ask ルールと混在しない。
```

Cursor 設定:

```
Cursor / 設定
承認方式: 許可リスト外の操作では確認を求める設定です。サンドボックス設定とは別です。
実行制限（サンドボックス）: サンドボックスによる実行制限を無効にする設定です。
```

### en エージェント管理（PID 34214、900×632）

```
Claude Code / 権限
Permissions
Equivalent to /permissions in the interactive TUI. Edits permissions in ~/.claude/settings.json. Rule editing is a different setting from the launch toggle in Settings. size=574.5,26
Allow: Permits execution without confirmation. Other permission settings, such as deny rules, also apply.
Ask to confirm: Asks for confirmation before execution. In modes that cannot confirm, execution may be denied.
Deny: Denies execution. Takes precedence over allow rules.

Codex / 設定
Approval policy / approval_policy
The value is unset. Check the agent settings for the applied default.
Execution limits (sandbox) / sandbox_mode
The value is unset. Check the agent settings for the applied default.

Cursor / 権限
Edits permissions in ~/.cursor/cli-config.json. Deny rules take precedence over allow. Rule editing is a different setting from the launch toggle in Settings. size=596.0,26
Allow: Permits execution without confirmation. Deny rules take precedence.
Deny: Denies execution. Takes precedence over allow rules.

Cursor / 設定
Approval method: Asks for confirmation outside the allowlist. This is separate from the sandbox setting. size=331.0,26
Execution limits (sandbox): Disables sandbox execution limits.
```

権限メニューの必須判定は本目視の範囲外（契約どおり Swift Testing / Ruby）。

## PNG 一覧（`/tmp/phlox-t50-visual/`）

| ファイル | 対象 | 論理寸法 | 画素 | PID |
|---|---|---|---|---|
| `settings-permissions-ja-top.png` | 設定・エージェント・権限（先頭） | 520×728 | 1040×1456 | 29423 |
| `settings-permissions-ja-bottom.png` | 同・axscroll 末尾 | 520×728 | 1040×1456 | 29423 |
| `console-claude-permissions-ja.png` | 管理・Claude 権限 | 900×632 | 1800×1264 | 29423 |
| `console-codex-settings-ja.png` | 管理・Codex 設定 | 900×632 | 1800×1264 | 29423 |
| `console-cursor-permissions-ja.png` | 管理・Cursor 権限 | 900×632 | 1800×1264 | 29423 |
| `console-cursor-settings-ja.png` | 管理・Cursor 設定 | 900×632 | 1800×1264 | 29423 |
| `settings-permissions-en-top.png` | 設定・エージェント・権限（先頭、リトライ） | 520×728 | 1040×1456 | 55787 |
| `settings-permissions-en-bottom.png` | 同・axscroll 末尾 | 520×728 | 1040×1456 | 55787 |
| `console-claude-permissions-en.png` | 管理・Claude 権限 | 900×632 | 1800×1264 | 34214 |
| `console-codex-settings-en.png` | 管理・Codex 設定 | 900×632 | 1800×1264 | 34214 |
| `console-cursor-permissions-en.png` | 管理・Cursor 権限 | 900×632 | 1800×1264 | 34214 |
| `console-cursor-settings-en.png` | 管理・Cursor 設定 | 900×632 | 1800×1264 | 34214 |

## 設定の前後比較

隔離 suite（`defaults export`）の `phlox.bypass.*` は起動直後・設定閲覧後・管理閲覧後とも **キー無し**。suite 全体の launch→console 差分: added/removed/changed なし。

隔離 DATA の md5 一覧は launch 後に ports.json / sqlite 等が増える（file_count 6→10）。**launch 後から console 閲覧後まで DATA_UNCHANGED=yes**。閲覧操作ではこれ以上変わっていない。

ja: `~/.claude/settings.json` / `~/.codex/config.toml` / `~/.cursor/cli-config.json` の md5 は起動前と管理閲覧後で一致。

en 本ラン: `~/.cursor/cli-config.json` が `1ae3ec42d0c8c0c55afd287295614300` → `20af92c132f54c43f3b42362e266937d`（mtime 2026-09-14 01:55:24）。Claude / Codex の利用者ファイルは不変。Picker・ルール保存は未操作。Cursor 管理の `loadSettings` は読み取り。原因は未確定（表示時の既存下書き同期、または Cursor IDE の同時書き込み）。元バイトはバックアップ無しのため復元していない。

## できなかった手順と理由

1. 英語本ランの設定 SHOT: 英語 UI の設定ボタン help が `Settings`（日本語は `設定`）。`dump-t38` の help「設定」が外れ、フォールバック `dump-t38-menu` が Apple メニューの「システム設定…」を押した。macOS System Settings を誤開し、観測後に quit。Release Phlox には未接触。設定 en は PID 55787 で help「Settings」により撮り直し済み。
2. 設定ウィンドウ外枠を 520×640 にはできなかった。AX `set size` 後も 520×728（t38 と同じクロム込み）。コンテンツ ScrollArea は 520×576。
3. エージェント管理のエージェント切替は権限 Picker ではなく、ナビゲーション用ポップアップ（`agent-console-agent-picker`）の AXPress＋メニュー項目 click。権限値の Picker は未操作。
4. `~/.cursor/cli-config.json` の en 閲覧中変化は、元ファイルを復元できず。隔離 suite / 隔離 DATA は非変更。
5. 権限メニューの目視は契約どおり本ゲートの範囲外。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定 r1（2026-09-14、レビュー r1 差し戻し前のビルド d16c1ad、PNG 12 枚のうち 8 枚を PM が閲覧）

判定: **保留（再撮影待ち）**。差し戻し r1 の製品修正（設定の ON/OFF 表示、管理画面の導入説明、Codex 権限以外の行）が入るため、設定・権限 Section と管理 4 画面は修正後に再撮影して判定する。

r1 ビルドで確認できたこと:
- 設定・権限 Section（ja/en）: Claude／Codex／Cursor の 3 組み込みで説明が異なる。Claude は「サンドボックスの解除を意味しません」、Codex はチャット／ターミナルの区別、Cursor は --auto-review／--force と --sandbox。カスタム descriptor 行は「このエージェントの起動設定に従います」で「フルアクセス」汎用説明ではない。切れ・重なりなし。
- レビュー r1 MEDIUM(2) を目視でも確認: OFF／ON の 2 行が同じ書式で並び、どちらの状態の説明か読み分けられない。カスタム行は 2 行が同文で重複。
- 管理・Claude 権限（ja）: 導入説明は 900pt 幅で 2 行に収まり欠けていないが、subtitle 経路（lineLimit 2）のためレビュー r1 MEDIUM(3) の指摘どおり狭幅では欠けうる。
- 管理・Codex 設定（ja/en）: 承認方針「値は未設定です。適用される既定値は…」「既定（未設定）」、en では「Approval policy / Default (unset)」に追随。管理・Cursor 設定: 承認方式「許可リストで確認」、実行制限「実行制限を無効化」と説明。管理・Cursor 権限: 許可／拒否の説明。
- 設定の前後比較: 隔離 suite・隔離 DATA は閲覧で不変。`~/.cursor/cli-config.json` の en 閲覧中の変化は、同時刻に cursor-agent（ヘッドレス実装ジョブ 2 本）が稼働していたため Phlox 起因と断定できない（未確定・記録のみ。Cursor 管理の loadSettings は読み取りで、Picker・保存は未操作）。

範囲外の観察（Phase 5 フォローアップ）: en 起動の Codex 設定画面で、権限以外の行（モデル・思考の深さ・応答の人格）と管理コンソールの見出しが日本語のまま（UX-10 の対象外の既存文言）。設定ウィンドウは AX で 520×640 にできず 520×728（ハーネス制約、t38 と同じ）。

=== REPORT COMPLETE ===
